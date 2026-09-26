-- services/media_player.lua -- mpv wrapper with IPC control.
-- Daemon mode: mpv runs idle with --input-ipc-server, LÖVE sends commands
-- through tools/mpv_ipc.py. Fullscreen video: mpv takes over screen.
local sh = require("core.sh")
local M  = {}

M.SOCKET    = "/tmp/fgd_mpv.sock"
M.IPC_HELPER = "tools/mpv_ipc.py"

-- ============================================================
--  Availability
-- ============================================================
function M.available()
  return sh.exec("command -v mpv >/dev/null 2>&1") == 0
end

function M.daemon_running()
  return sh.exec("pgrep -x mpv >/dev/null 2>&1") == 0
end

-- ============================================================
--  Daemon lifecycle (background, no window)
-- ============================================================
function M.start_daemon()
  if M.daemon_running() then return true end
  if not M.available() then return false, "mpv not installed" end

  sh.exec("rm -f " .. sh.shq(M.SOCKET))

  -- Audio-only daemon: no video output, no terminal output
  local cmd = "setsid mpv --idle=yes --no-video --no-terminal " ..
    "--vo=null --ao=alsa --volume=70 " ..
    "--input-ipc-server=" .. sh.shq(M.SOCKET) ..
    " </dev/null >/dev/null 2>&1 &"
  os.execute(cmd)

  -- Wait for socket to appear (max 3s)
  for i = 1, 30 do
    love.timer.sleep(0.1)
    if sh.exists(M.SOCKET) then return true end
  end
  return false, "mpv socket not created"
end

function M.stop_daemon()
  os.execute("pkill -x mpv 2>/dev/null")
  sh.exec("rm -f " .. sh.shq(M.SOCKET))
end

-- Public kill alias (legacy screens compat).
function M.kill() M.stop_daemon() end

-- One-shot playback: start daemon if needed, load file, unpause.
function M.play_path(path)
  if not path or path == "" then return false, "no path" end
  if not M.daemon_running() then
    local ok, err = M.start_daemon()
    if not ok then return false, err end
  end
  M.send("loadfile", path, "replace")
  M.send("set_property", "pause", false)
  return true
end

-- ============================================================
--  IPC primitive
-- ============================================================
local function json_escape(s)
  return s:gsub('\\', '\\\\'):gsub('"', '\\"')
end

local function json_array(...)
  local parts = {}
  for _, v in ipairs({...}) do
    local ty = type(v)
    if ty == "string" then
      parts[#parts+1] = '"' .. json_escape(v) .. '"'
    elseif ty == "number" or ty == "boolean" then
      parts[#parts+1] = tostring(v)
    elseif ty == "table" then
      parts[#parts+1] = json_array(unpack and unpack(v) or table.unpack(v))
    end
  end
  return "[" .. table.concat(parts, ",") .. "]"
end

-- Send a command; returns the raw response (may be empty)
function M.send(...)
  if not sh.exists(M.SOCKET) then return nil end
  local arr = json_array(...)
  local json = '{"command":' .. arr .. '}'
  local cmd = "python3 " .. sh.shq(M.IPC_HELPER) .. " " ..
    sh.shq(M.SOCKET) .. " " .. sh.shq(json)
  return sh.read(cmd)
end

-- Get a property (returns number, boolean, string or nil)
function M.get_property(name)
  local raw = M.send("get_property", name)
  if not raw then return nil end
  -- mpv replies with {"data": <value>, "error": "success"}
  local _, data = raw:match('"data":(%s*[^,}]+)')
  if not data then return nil end
  data = data:gsub("^%s+", ""):gsub("%s+$", "")
  if data == "null" then return nil end
  if data == "true" then return true end
  if data == "false" then return false end
  local n = tonumber(data)
  if n then return n end
  local s = data:match('^"(.*)"$')
  if s then return s end
  return data
end

function M.set_property(name, value)
  return M.send("set_property", name, value)
end

-- ============================================================
--  Playback API (daemon)
-- ============================================================
function M.load(path, replace)
  if not M.daemon_running() then
    local ok, err = M.start_daemon()
    if not ok then return false, err end
  end
  M.send("loadfile", path, replace and "replace" or "append-play")
  return true
end

function M.play()           M.send("set_property", "pause", false) end
function M.pause()          M.send("set_property", "pause", true) end
function M.toggle_pause()   M.send("cycle", "pause") end
function M.next()           M.send("playlist-next", "weak") end
function M.prev()           M.send("playlist-prev", "weak") end
function M.stop()           M.send("stop") end
function M.clear_playlist() M.send("playlist-clear") end

function M.seek_relative(sec) M.send("seek", sec, "relative") end
function M.seek_absolute(sec) M.send("seek", sec, "absolute") end
function M.set_volume(v)      M.send("set_property", "volume", math.max(0, math.min(200, v))) end
function M.set_speed(v)       M.send("set_property", "speed", v) end
function M.set_eq(preset)
  local filters = {
    flat    = "",
    bass    = "equalizer=f=60:t=q:w=1:g=8,equalizer=f=170:t=q:w=1:g=4",
    vocal   = "equalizer=f=3000:t=q:w=2:g=6",
    rock    = "equalizer=f=100:t=q:w=1:g=5,equalizer=f=3000:t=q:w=2:g=4",
    jazz    = "equalizer=f=200:t=q:w=1:g=3,equalizer=f=4000:t=q:w=2:g=2",
    electro = "equalizer=f=60:t=q:w=1:g=6,equalizer=f=12000:t=q:w=2:g=5",
  }
  local f = filters[preset] or ""
  M.send("set_property", "af", f ~= "" and f or "")
end

-- ============================================================
--  Metadata via ffprobe
-- ============================================================
function M.probe(path)
  local out = sh.read("ffprobe -v quiet -print_format json -show_format -show_streams " ..
    sh.shq(path) .. " 2>/dev/null")
  if not out or out == "" then return nil end
  local JSON = require("core.json")
  local ok, data = pcall(JSON.decode, out)
  if not ok or type(data) ~= "table" then return nil end

  local info = { path = path }
  if data.format then
    info.duration = tonumber(data.format.duration or 0) or 0
    info.size     = tonumber(data.format.size or 0) or 0
    info.bitrate  = tonumber(data.format.bit_rate or 0) or 0
    info.format   = data.format.format_name or "?"

    -- Tags (title, artist, album, etc.)
    local tags = data.format.tags or {}
    info.title  = tags.title  or tags.TITLE  or tags.Title
    info.artist = tags.artist or tags.ARTIST or tags.Artist
    info.album  = tags.album  or tags.ALBUM  or tags.Album
    info.year   = tags.date   or tags.DATE   or tags.Year
    info.genre  = tags.genre  or tags.GENRE  or tags.Genre
    info.track  = tags.track  or tags.TRACK  or tags.Track
  end
  for _, s in ipairs(data.streams or {}) do
    if s.codec_type == "video" and not info.video then
      info.video = {
        codec = s.codec_name, w = s.width, h = s.height,
        fps = s.r_frame_rate,
      }
    elseif s.codec_type == "audio" and not info.audio then
      info.audio = {
        codec = s.codec_name, channels = s.channels,
        rate = s.sample_rate,
      }
    end
  end
  return info
end

-- ============================================================
--  Fullscreen video playback (blocking)
-- ============================================================
function M.play_fullscreen(path)
  if not M.available() then return false, "mpv not installed" end
  -- Kill any daemon first
  M.stop_daemon()

  local args = "--vo=sdl --ao=alsa --hwdec=v4l2request " ..
    "--profile=fast --no-osc --no-osd-bar --term-status-msg= "

  local cmd = "mpv " .. args .. sh.shq(path) .. " >/dev/null 2>&1"
  local rc = sh.exec(cmd)
  return rc == 0
end

-- ============================================================
--  Helpers
-- ============================================================
-- Alias retro-compatibile (audio_player.lua usa human_duration)
function M.human_duration(sec) return M.human_time(sec) end

function M.human_time(sec)
  if not sec or sec ~= sec or sec < 0 then return "0:00" end
  sec = math.floor(sec)
  local h = math.floor(sec / 3600)
  local m = math.floor((sec % 3600) / 60)
  local s = sec % 60
  if h > 0 then return string.format("%d:%02d:%02d", h, m, s) end
  return string.format("%d:%02d", m, s)
end

function M.is_audio(path)
  local ext = (path:match("%.([^.]+)$") or ""):lower()
  local AUD = {
    mp3=1, ogg=1, oga=1, wav=1, flac=1, opus=1, m4a=1, aac=1,
    wma=1, ape=1, alac=1,
  }
  return AUD[ext] == true
end

function M.is_video(path)
  local ext = (path:match("%.([^.]+)$") or ""):lower()
  local VID = {
    mp4=1, mkv=1, avi=1, webm=1, mov=1, mpg=1, mpeg=1, m4v=1,
    flv=1, wmv=1, ["3gp"]=1, ogv=1, ts=1, m2ts=1, vob=1,
  }
  return VID[ext] == true
end

return M
