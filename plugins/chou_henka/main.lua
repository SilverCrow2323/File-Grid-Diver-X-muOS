-- plugins/chou_henka/main.lua -- Chou Henka media center v2.
-- 3 tabs: PLAYER / LIBRARY / SETTINGS.
-- Persist: data/chou_henka_library.json + data/chou_henka_config.json.
local A     = require("core.assets")
local State = require("core.state")
local Input = require("core.input_map")
local Frame = require("ui.frame")
local D     = require("ui.draw")
local Notify= require("ui.notify")
local Modal = require("ui.modal")
local KB    = require("ui.keyboard")
local MP    = require("services.media_player")
local sh    = require("core.sh")
local JSON  = require("core.json")

local S = {}
local W, H = 640, 480
S.reserve_select = true
S.escape_passthrough = true

local ACC    = {0.95, 0.40, 0.85}
local ACC_HI = {1.00, 0.60, 0.95}
local GRN    = {0.35, 0.90, 0.50}
local RED    = {0.95, 0.35, 0.30}
local CYA_HI = {0.60, 0.95, 1.00}

local function col(c, a) love.graphics.setColor(c[1], c[2], c[3], a or 1) end
local function human(n)
  if not n or n <= 0 then return "0 B" end
  local u = {"B","KB","MB","GB","TB"}; local i = 1
  while n >= 1024 and i < #u do n = n / 1024; i = i + 1 end
  if i == 1 then return string.format("%d %s", n, u[i]) end
  return string.format("%.1f %s", n, u[i])
end
local function base(p) return (p or ""):match("([^/]+)$") or p or "?" end
local function ext_of(p)
  local e = p:match("%.([^.]+)$"); return e and e:lower() or ""
end

local AUD = { mp3=1, ogg=1, oga=1, wav=1, flac=1, opus=1, m4a=1, aac=1,
              wma=1, ape=1, alac=1 }
local VID = { mp4=1, mkv=1, avi=1, webm=1, mov=1, mpg=1, mpeg=1, m4v=1,
              flv=1, wmv=1, ["3gp"]=1, ogv=1, ts=1, m2ts=1 }
local function kind_of(p)
  local e = ext_of(p)
  if AUD[e] then return "audio" end
  if VID[e] then return "video" end
  return nil
end

local LIB_PATH = "data/chou_henka_library.json"
local CFG_PATH = "data/chou_henka_config.json"

local function read_json(path)
  local f = io.open(path, "r"); if not f then return nil end
  local c = f:read("*a"); f:close()
  local ok, d = pcall(JSON.decode, c)
  if ok and type(d) == "table" then return d end
  return nil
end
local function write_json(path, t)
  sh.exec("mkdir -p data")
  local f = io.open(path, "w"); if not f then return false end
  local ok, s = pcall(JSON.encode, t)
  if not ok then f:close(); return false end
  f:write(s); f:close(); return true
end

local cfg = { paths = {}, scan_on_boot = false, autoplay = true,
              volume = 70, eq = "flat" }
local function load_cfg()
  local d = read_json(CFG_PATH)
  if d then for k, v in pairs(d) do cfg[k] = v end end
  if type(cfg.paths) ~= "table" then cfg.paths = {} end
end
local function save_cfg() write_json(CFG_PATH, cfg) end

local lib = { tracks = {}, scanned_at = 0 }
local function load_lib()
  local d = read_json(LIB_PATH)
  if d then
    lib.tracks = d.tracks or {}
    lib.scanned_at = d.scanned_at or 0
  end
end
local function save_lib()
  write_json(LIB_PATH, { tracks = lib.tracks, scanned_at = lib.scanned_at })
end

local scan_state, scan_msg, scan_job, scan_found = "idle", "", nil, 0

local function start_scan()
  if #cfg.paths == 0 then
    Notify.show("warning", "no scan paths configured"); return
  end
  scan_state = "scanning"; scan_found = 0; scan_msg = "Scanning..."
  local parts = {}
  for _, p in ipairs(cfg.paths) do
    if p and p ~= "" then
      parts[#parts+1] = "find " .. sh.shq(p) ..
        " -type f -printf '%s\\t%T@\\t%p\\n' 2>/dev/null"
    end
  end
  local id = tostring(os.time()) .. "_" .. tostring(math.random(1000, 9999))
  local script = "/tmp/fgd_ch_" .. id .. ".sh"
  local out    = "/tmp/fgd_ch_" .. id .. ".out"
  local done   = "/tmp/fgd_ch_" .. id .. ".done"
  local body = "#!/bin/sh\nset +e\nOUT=" .. sh.shq(out) ..
    "\nDONE=" .. sh.shq(done) .. "\n: > \"$OUT\"\n" ..
    table.concat(parts, "\n") .. "\ntouch \"$DONE\"\n"
  local f = io.open(script, "w")
  if not f then scan_state = "error"; scan_msg = "write failed"; return end
  f:write(body); f:close()
  sh.exec("chmod +x " .. sh.shq(script))
  sh.exec("setsid sh " .. sh.shq(script) .. " </dev/null >/dev/null 2>&1 &")
  scan_job = { script = script, out = out, done = done }
end

local function poll_scan()
  if scan_state ~= "scanning" or not scan_job then return end
  local lines = {}
  local f = io.open(scan_job.out, "r")
  if f then for line in f:lines() do lines[#lines+1] = line end; f:close() end
  local tracks = {}
  for _, line in ipairs(lines) do
    local size, mt, path = line:match("^(%d+)%s+([%d%.]+)%s+(.+)$")
    if path then
      local kind = kind_of(path)
      if kind then
        tracks[#tracks+1] = {
          path = path, name = base(path), ext = ext_of(path),
          kind = kind, size = tonumber(size) or 0,
          mtime = tonumber(mt) or 0,
        }
      end
    end
  end
  lib.tracks = tracks
  scan_found = #tracks
  scan_msg = string.format("Found %d files...", scan_found)
  local d = io.open(scan_job.done, "r")
  if d then
    d:close()
    lib.scanned_at = os.time()
    save_lib()
    sh.exec("rm -f " .. sh.shq(scan_job.script) .. " " ..
      sh.shq(scan_job.out) .. " " .. sh.shq(scan_job.done))
    scan_job = nil; scan_state = "done"
    scan_msg = string.format("Done: %d files", scan_found)
    Notify.show("success", scan_msg)
    lib_sel, lib_scroll = 1, 0
  end
end

local queue = {}
local queue_idx = 1
local current = nil
local paused = false
local position = 0
local duration = 0
local volume = 70
local eq_preset = "flat"
local viz_bars = {}
local VIZ_N = 32
local refresh_acc, t = 0, 0
local EQ_PRESETS = { "flat", "bass", "vocal", "rock", "jazz", "electro" }

local function update_viz(dt)
  if #viz_bars ~= VIZ_N then
    viz_bars = {}
    for i = 1, VIZ_N do viz_bars[i] = 0.1 end
  end
  local active = not paused and MP.daemon_running()
  for i = 1, VIZ_N do
    local target
    if active then
      local n1 = math.sin(t * 6 + i * 0.7) * 0.5 + 0.5
      local n2 = math.sin(t * 11 + i * 1.3) * 0.3 + 0.5
      local n3 = math.sin(t * 2.7 + i * 0.2) * 0.2 + 0.5
      target = math.max(0.05, n1 * 0.5 + n2 * 0.3 + n3 * 0.2)
      target = target * (1 - (i / VIZ_N) * 0.5)
    else
      target = 0.05
    end
    viz_bars[i] = viz_bars[i] + (target - viz_bars[i]) * math.min(1, dt * 8)
  end
end

local function track_of(path)
  for _, tr in ipairs(lib.tracks) do
    if tr.path == path then return tr end
  end
  return { path = path, name = base(path),
           kind = kind_of(path) or "audio", size = 0 }
end

local function play_path(path)
  if not path or path == "" then return end
  current = track_of(path)
  position, duration, paused = 0, 0, false
  if current.kind == "video" then
    Notify.show("info", "Opening video in mpv...")
    MP.play_fullscreen(path)
  else
    local ok, err = MP.play_path(path)
    if not ok then Notify.show("error", err or "playback failed"); return end
    MP.set_volume(volume)
    MP.set_eq(eq_preset)
  end
end

local function play_queue(idx)
  if idx < 1 or idx > #queue then return end
  queue_idx = idx
  play_path(queue[idx].path)
end

local function next_track()
  if queue_idx < #queue then play_queue(queue_idx + 1)
  elseif cfg.autoplay and current then
    for i, tr in ipairs(lib.tracks) do
      if tr.path == current.path and i < #lib.tracks then
        play_path(lib.tracks[i + 1].path); return
      end
    end
  end
end

local function prev_track()
  if queue_idx > 1 then play_queue(queue_idx - 1) end
end

local TABS = { "PLAYER", "LIBRARY", "SETTINGS" }
local NTAB = 3
local tab = 1
local lib_sel, lib_scroll, lib_filter = 1, 0, 1
local FILTERS = { "ALL", "AUDIO", "VIDEO" }
local cfg_sel = 1
local cfg_paths_mode = false
local path_sel = 1

local function filtered_lib()
  local out = {}
  local f = FILTERS[lib_filter]
  for _, tr in ipairs(lib.tracks) do
    if f == "ALL" then out[#out+1] = tr
    elseif f == "AUDIO" and tr.kind == "audio" then out[#out+1] = tr
    elseif f == "VIDEO" and tr.kind == "video" then out[#out+1] = tr
    end
  end
  table.sort(out, function(a, b)
    return (a.name or ""):lower() < (b.name or ""):lower()
  end)
  return out
end

function S.enter()
  t = 0
  load_cfg()
  load_lib()
  volume = cfg.volume or 70
  eq_preset = cfg.eq or "flat"
  local p = State.chou_henka_path
  State.chou_henka_path = nil
  if p and p ~= "" then
    queue = { track_of(p) }
    queue_idx = 1
    tab = 1
    play_path(p)
  end
  if cfg.scan_on_boot and scan_state ~= "scanning" then start_scan() end
  local ok, PI = pcall(require, "ui.plugin_intro")
  if ok and PI.start then
    PI.start("chou_henka_v2", "Chou Henka", ACC, "hex")
  end
end

function S.leave()
  cfg.volume = volume
  cfg.eq = eq_preset
  save_cfg()
end

function S.update(dt)
  t = t + dt
  update_viz(dt)
  poll_scan()
  refresh_acc = refresh_acc + dt
  if refresh_acc >= 0.5 then
    refresh_acc = 0
    if MP.daemon_running() and current and current.kind == "audio" then
      local p = MP.get_property("time-pos")
      local d = MP.get_property("duration")
      local pa = MP.get_property("pause")
      if type(p) == "number" then position = p end
      if type(d) == "number" and d > 0 then duration = d end
      if type(pa) == "boolean" then paused = pa end
      if MP.get_property("idle-active") then
        if cfg.autoplay then next_track() else paused = true end
      end
    end
  end
end

local function change_tab(d)
  tab = tab + d
  if tab < 1 then tab = NTAB end
  if tab > NTAB then tab = 1 end
end

local function player_input(b)
  if b == Input.A then
    if current and current.kind == "video" then play_path(current.path)
    else
      if MP.daemon_running() then MP.toggle_pause()
      elseif current then play_path(current.path) end
    end
  elseif b == Input.R1 then next_track()
  elseif b == Input.L1 then prev_track()
  elseif b == Input.X then
    if #queue > 1 then
      for i = #queue, 2, -1 do
        local j = math.random(i)
        queue[i], queue[j] = queue[j], queue[i]
      end
      Notify.show("info", "queue shuffled")
    end
  elseif b == Input.Y then
    for i, name in ipairs(EQ_PRESETS) do
      if name == eq_preset then
        eq_preset = EQ_PRESETS[i % #EQ_PRESETS + 1]; break
      end
    end
    MP.set_eq(eq_preset)
    Notify.show("info", "EQ: " .. eq_preset)
  elseif b == Input.LEFT then MP.seek_relative(-10)
  elseif b == Input.RIGHT then MP.seek_relative(10)
  elseif b == Input.UP then
    volume = math.min(200, volume + 5); MP.set_volume(volume)
  elseif b == Input.DOWN then
    volume = math.max(0, volume - 5); MP.set_volume(volume)
  end
end

local function lib_input(b)
  local list = filtered_lib(); local n = #list
  if b == Input.UP then lib_sel = math.max(1, lib_sel - 1)
  elseif b == Input.DOWN then lib_sel = math.min(n, lib_sel + 1)
  elseif b == Input.LEFT then
    lib_filter = math.max(1, lib_filter - 1); lib_sel, lib_scroll = 1, 0
  elseif b == Input.RIGHT then
    lib_filter = math.min(#FILTERS, lib_filter + 1); lib_sel, lib_scroll = 1, 0
  elseif b == Input.A then
    local tr = list[lib_sel]
    if tr then queue = { tr }; queue_idx = 1; tab = 1; play_path(tr.path) end
  elseif b == Input.X then
    local tr = list[lib_sel]
    if tr then queue[#queue+1] = tr; Notify.show("info", "queued: " .. tr.name) end
  elseif b == Input.Y then start_scan()
  elseif b == Input.L1 then lib_sel = math.max(1, lib_sel - 10)
  elseif b == Input.R1 then lib_sel = math.min(n, lib_sel + 10)
  end
end

local CFG_ROWS

local function prompt_add_path()
  KB.open({
    title = "Add scan path",
    initial = "/mnt/mmc/Music",
    on_accept = function(txt)
      if txt and txt ~= "" then
        cfg.paths[#cfg.paths+1] = txt
        save_cfg()
        Notify.show("success", "path added")
      end
    end,
  })
end

CFG_ROWS = {
  { kind = "toggle", key = "scan_on_boot", label = "Scan library on boot",
    hint = "rebuild index every time the plugin opens" },
  { kind = "toggle", key = "autoplay", label = "Autoplay next track",
    hint = "continue with next file when a track ends" },
  { kind = "slider", key = "volume", minv = 0, maxv = 100, step = 5,
    label = "Default volume", hint = "starting volume for new sessions" },
  { kind = "action", key = "paths", label = "Manage scan paths",
    hint = "folders where the library looks for media",
    act = function() cfg_paths_mode = true; path_sel = 1 end },
  { kind = "action", key = "rescan", label = "Rescan library now",
    hint = "index the configured folders",
    act = function() start_scan(); tab = 2 end },
  { kind = "action", key = "clear", label = "Clear library",
    hint = "forget every indexed file",
    act = function()
      lib.tracks = {}; lib.scanned_at = 0; save_lib()
      Notify.show("warning", "library cleared")
    end },
  { kind = "action", key = "stats", label = "Library stats",
    hint = "how many files are indexed",
    act = function()
      local n, a, v = #lib.tracks, 0, 0
      for _, tr in ipairs(lib.tracks) do
        if tr.kind == "audio" then a = a + 1 else v = v + 1 end
      end
      local when = lib.scanned_at > 0 and
        os.date("%Y-%m-%d %H:%M", lib.scanned_at) or "never"
      Modal.show("Library stats",
        string.format("%d files indexed\n%d audio, %d video\nLast scan: %s",
          n, a, v, when),
        { accept_label = "OK", hide_cancel = true })
    end },
}

local function cfg_input(b)
  if cfg_paths_mode then
    if b == Input.UP then path_sel = math.max(1, path_sel - 1)
    elseif b == Input.DOWN then
      path_sel = math.min(#cfg.paths + 1, path_sel + 1)
    elseif b == Input.A then
      if path_sel > #cfg.paths then prompt_add_path()
      else Notify.show("info", cfg.paths[path_sel]) end
    elseif b == Input.X then
      if path_sel <= #cfg.paths then
        table.remove(cfg.paths, path_sel)
        if path_sel > #cfg.paths then path_sel = math.max(1, #cfg.paths) end
        save_cfg()
        Notify.show("warning", "path removed")
      end
    elseif b == Input.Y then prompt_add_path()
    elseif b == Input.B or b == Input.SELECT then cfg_paths_mode = false end
    return
  end
  if b == Input.UP then cfg_sel = math.max(1, cfg_sel - 1)
  elseif b == Input.DOWN then cfg_sel = math.min(#CFG_ROWS, cfg_sel + 1)
  elseif b == Input.A then
    local r = CFG_ROWS[cfg_sel]
    if r.kind == "toggle" then cfg[r.key] = not cfg[r.key]; save_cfg()
    elseif r.kind == "action" and r.act then r.act() end
  elseif b == Input.LEFT or b == Input.RIGHT then
    local r = CFG_ROWS[cfg_sel]
    if r.kind == "slider" then
      local d = (b == Input.RIGHT) and 1 or -1
      cfg[r.key] = math.max(r.minv, math.min(r.maxv,
        (cfg[r.key] or 0) + d * r.step))
      volume = cfg.volume
      save_cfg()
    end
  end
end

function S.pad(b)
  if Modal.is_open() then
    if b == Input.A then Modal.accept()
    elseif b == Input.B then Modal.cancel() end
    return
  end
  if KB.is_open() then KB.pad(b); return end
  if b == Input.B or b == Input.SELECT then
    if cfg_paths_mode then cfg_paths_mode = false
    else State.back() end
    return
  end
  if b == Input.L1 then change_tab(-1); return end
  if b == Input.R1 then change_tab(1); return end
  if     tab == 1 then player_input(b)
  elseif tab == 2 then lib_input(b)
  elseif tab == 3 then cfg_input(b) end
end

function S.hat(dir)
  local map = { up = Input.UP, down = Input.DOWN,
                left = Input.LEFT, right = Input.RIGHT }
  if map[dir] then S.pad(map[dir]) end
end

function S.key(k)
  if Modal.is_open() then
    if k == "return" then Modal.accept()
    elseif k == "escape" then Modal.cancel() end
    return
  end
  if KB.is_open() then KB.key(k); return end
  if k == "up" then S.hat("up")
  elseif k == "down" then S.hat("down")
  elseif k == "left" then S.hat("left")
  elseif k == "right" then S.hat("right")
  elseif k == "return" or k == "space" then S.pad(Input.A)
  elseif k == "x" then S.pad(Input.X)
  elseif k == "y" then S.pad(Input.Y)
  elseif k == "q" then change_tab(-1)
  elseif k == "e" then change_tab(1)
  elseif k == "escape" or k == "backspace" then S.pad(Input.B) end
end

local function draw_tabs()
  local x, y = 20, Frame.TOP_H + 4
  local w = W - 40
  local h = 26
  local tw = w / NTAB
  for i, name in ipairs(TABS) do
    local tx = x + (i - 1) * tw
    local active = (i == tab)
    if active then
      col({ACC[1]*0.22, ACC[2]*0.22, ACC[3]*0.22}, 0.95)
      love.graphics.rectangle("fill", tx, y, tw - 4, h, 3, 3)
      col(ACC_HI, 0.95)
      love.graphics.setLineWidth(1.6)
      love.graphics.rectangle("line", tx+0.5, y+0.5, tw-5, h-1, 3, 3)
      love.graphics.setLineWidth(1)
    else
      col({0.05, 0.03, 0.06}, 0.8)
      love.graphics.rectangle("fill", tx, y, tw - 4, h, 3, 3)
      col(ACC, 0.35)
      love.graphics.rectangle("line", tx+0.5, y+0.5, tw-5, h-1, 3, 3)
    end
    love.graphics.setFont(A.font(A.FONT_BODY_BOLD, 11))
    col(active and {1,1,1} or {0.65, 0.60, 0.70}, 1)
    love.graphics.printf(name, tx, y + 7, tw - 4, "center")
  end
end

local function draw_header()
  love.graphics.setFont(A.font(A.FONT_TITLE, 14))
  col(ACC_HI, 1)
  love.graphics.print("CHOU HENKA", 20, Frame.TOP_H + 6)
  love.graphics.setFont(A.font(A.FONT_MONO, 9))
  col(ACC, 0.7)
  love.graphics.print("// rich media player", 132, Frame.TOP_H + 12)
  draw_tabs()
end

local function draw_player()
  local th = State.theme
  local x, y, w = 24, Frame.TOP_H + 40, W - 48
  love.graphics.setFont(A.font(A.FONT_TITLE, 20))
  col(ACC_HI, 1)
  local title = current and current.name or "No track loaded"
  if #title > 34 then title = title:sub(1, 33) .. "..." end
  love.graphics.printf(title, x, y, w, "center")
  love.graphics.setFont(A.font(A.FONT_MONO, 10))
  col(ACC, 0.75)
  local meta = current and string.format("%s  .  %s  .  %s",
    (current.kind or "?"):upper(), (current.ext or "?"):upper(),
    human(current.size or 0)) or ""
  love.graphics.printf(meta, x, y + 26, w, "center")
  if current and current.kind == "audio" then
    local vy, vh = y + 54, 70
    local bw = (w - (#viz_bars - 1) * 2) / #viz_bars
    for i = 1, #viz_bars do
      local v = viz_bars[i]
      local bx = x + (i - 1) * (bw + 2)
      local bh = math.max(2, v * vh)
      local by = vy + (vh - bh)
      local tt = (i - 1) / (#viz_bars - 1)
      col({0.40 + 0.55 * tt, 0.40 + 0.20 * (1 - tt),
           0.95 - 0.15 * tt}, 0.95)
      love.graphics.rectangle("fill", bx, by, bw, bh, 1, 1)
    end
  else
    love.graphics.setFont(A.font(A.FONT_BODY, 12))
    col(ACC, 0.7)
    love.graphics.printf("Video plays fullscreen via mpv",
      x, y + 80, w, "center")
  end
  local py = y + 140
  local pct = (duration > 0) and math.min(1, position / duration) or 0
  col({0.06, 0.05, 0.08}, 1)
  love.graphics.rectangle("fill", x, py, w, 6, 3, 3)
  col(ACC, 0.9)
  love.graphics.rectangle("fill", x+1, py+1, (w-2)*pct, 4, 2, 2)
  local thumb = x + w * pct
  col(ACC_HI, 1)
  love.graphics.circle("fill", thumb, py + 3, 5)
  love.graphics.setFont(A.font(A.FONT_MONO, 10))
  col(th.text_dim, 0.85)
  love.graphics.print(MP.human_time(position), x, py + 12)
  love.graphics.printf(MP.human_time(duration), x, py + 12, w, "right")
  local cy = py + 44
  local cx = x + w / 2
  col(th.text_bright, 0.85)
  love.graphics.polygon("fill", cx-70, cy-10, cx-70, cy+10, cx-58, cy)
  love.graphics.rectangle("fill", cx-80, cy-10, 3, 20, 1, 1)
  col({ACC[1]*0.20, ACC[2]*0.20, ACC[3]*0.20}, 1)
  love.graphics.circle("fill", cx, cy, 20)
  col(ACC_HI, 1)
  love.graphics.setLineWidth(2)
  love.graphics.circle("line", cx, cy, 20)
  love.graphics.setLineWidth(1)
  if paused or not MP.daemon_running() then
    love.graphics.polygon("fill", cx-6, cy-10, cx-6, cy+10, cx+10, cy)
  else
    love.graphics.rectangle("fill", cx-7, cy-9, 5, 18, 1, 1)
    love.graphics.rectangle("fill", cx+2, cy-9, 5, 18, 1, 1)
  end
  col(th.text_bright, 0.85)
  love.graphics.polygon("fill", cx+70, cy-10, cx+70, cy+10, cx+58, cy)
  love.graphics.rectangle("fill", cx+77, cy-10, 3, 20, 1, 1)
  love.graphics.setFont(A.font(A.FONT_MONO, 10))
  col(th.text_dim, 0.85)
  love.graphics.print(string.format("VOL %d%%", volume), x, cy - 6)
  love.graphics.printf("EQ: " .. eq_preset, x, cy - 6, w, "right")
  if #queue > 0 then
    local qy = cy + 34
    love.graphics.setFont(A.font(A.FONT_MONO, 9))
    col(ACC, 0.85)
    love.graphics.print("QUEUE (" .. #queue .. ")", x, qy)
    local ry = qy + 14
    for i, tr in ipairs(queue) do
      if i > 3 then break end
      local is_cur = (i == queue_idx)
      love.graphics.setFont(A.font(A.FONT_BODY, 10))
      col(is_cur and ACC_HI or th.text, 1)
      local nm = tr.name or "?"
      if #nm > 46 then nm = nm:sub(1, 45) .. "..." end
      love.graphics.print((is_cur and "> " or "  ") .. nm, x + 4, ry)
      ry = ry + 14
    end
    if #queue > 3 then
      love.graphics.setFont(A.font(A.FONT_MONO, 9))
      col(th.text_dim, 0.7)
      love.graphics.print("  ... and " .. (#queue - 3) .. " more",
        x + 4, ry)
    end
  end
end

local function draw_library()
  local th = State.theme
  local x, y, w = 16, Frame.TOP_H + 40, W - 32
  local fw = 80
  for i, f in ipairs(FILTERS) do
    local fx = x + (i - 1) * (fw + 6)
    local active = (i == lib_filter)
    if active then
      col({ACC[1]*0.22, ACC[2]*0.22, ACC[3]*0.22}, 0.95)
      love.graphics.rectangle("fill", fx, y, fw, 20, 3, 3)
      col(ACC_HI, 0.95)
      love.graphics.rectangle("line", fx+0.5, y+0.5, fw-1, 19, 3, 3)
    else
      col({0.05, 0.03, 0.06}, 0.7)
      love.graphics.rectangle("fill", fx, y, fw, 20, 3, 3)
      col(ACC, 0.30)
      love.graphics.rectangle("line", fx+0.5, y+0.5, fw-1, 19, 3, 3)
    end
    love.graphics.setFont(A.font(A.FONT_BODY_BOLD, 10))
    col(active and {1,1,1} or {0.65, 0.60, 0.70}, 1)
    love.graphics.printf(f, fx, y + 4, fw, "center")
  end
  love.graphics.setFont(A.font(A.FONT_MONO, 9))
  col(ACC, 0.85)
  love.graphics.printf(
    scan_state == "scanning" and scan_msg or
    (lib.scanned_at > 0 and
      ("last scan: " .. os.date("%m-%d %H:%M", lib.scanned_at))
      or "never scanned"),
    x, y + 4, w, "right")
  local list = filtered_lib()
  local ly = y + 26
  local lh = H - Frame.BOTTOM_H - ly - 4
  local row_h = 26
  local vis = math.max(1, math.floor(lh / row_h))
  if #list == 0 then
    love.graphics.setFont(A.font(A.FONT_BODY, 12))
    col(th.text_dim, 0.85)
    local msg = "Library is empty.\n\nAdd scan paths in SETTINGS, then press Y to rescan."
    if scan_state == "scanning" then msg = scan_msg end
    love.graphics.printf(msg, x, ly + lh/2 - 30, w, "center")
    return
  end
  if lib_sel < lib_scroll + 1 then lib_scroll = lib_sel - 1 end
  if lib_sel > lib_scroll + vis then lib_scroll = lib_sel - vis end
  lib_scroll = math.max(0, math.min(lib_scroll, #list - vis))
  love.graphics.setScissor(x, ly, w, lh)
  for i = lib_scroll + 1, math.min(#list, lib_scroll + vis) do
    local tr = list[i]
    local ry = ly + (i - lib_scroll - 1) * row_h
    local focused = (i == lib_sel)
    if focused then
      col({ACC[1]*0.20, ACC[2]*0.20, ACC[3]*0.20}, 0.95)
      love.graphics.rectangle("fill", x, ry, w, row_h - 2, 3, 3)
      col(ACC_HI, 0.9)
      love.graphics.rectangle("line", x+0.5, ry+0.5, w-1, row_h-3, 3, 3)
    end
    local kc = (tr.kind == "video") and {0.85, 0.55, 0.45}
               or {0.55, 0.85, 0.55}
    col(kc, 0.95)
    love.graphics.rectangle("fill", x + 6, ry + 5, 42, 16, 3, 3)
    love.graphics.setFont(A.font(A.FONT_MONO, 8))
    col({0.05, 0.05, 0.05}, 1)
    love.graphics.printf((tr.kind or "?"):upper(), x + 6, ry + 8, 42, "center")
    love.graphics.setFont(A.font(A.FONT_BODY, 11))
    col(focused and {1,1,1} or th.text, 1)
    local nm = tr.name or "?"
    if #nm > 48 then nm = nm:sub(1, 47) .. "..." end
    love.graphics.print(nm, x + 56, ry + 6)
    love.graphics.setFont(A.font(A.FONT_MONO, 9))
    col(th.text_dim, 0.75)
    love.graphics.printf(human(tr.size or 0), x, ry + 7, w - 8, "right")
  end
  love.graphics.setScissor()
  love.graphics.setFont(A.font(A.FONT_MONO, 9))
  col(th.text_dim, 0.7)
  love.graphics.printf(#list .. " / " .. #lib.tracks .. " files",
    x, ly + lh - 12, w, "right")
end

local function draw_cfg_row(r, y, focused)
  local th = State.theme
  local x, w, h = 24, W - 48, 44
  if focused then
    col({ACC[1]*0.15, ACC[2]*0.15, ACC[3]*0.15}, 0.95)
    love.graphics.rectangle("fill", x, y, w, h - 2, 4, 4)
    col(ACC_HI, 0.9)
    love.graphics.rectangle("line", x+0.5, y+0.5, w-1, h-3, 4, 4)
  else
    col({0.04, 0.025, 0.05}, 0.9)
    love.graphics.rectangle("fill", x, y, w, h - 2, 4, 4)
    col(ACC, 0.20)
    love.graphics.rectangle("line", x+0.5, y+0.5, w-1, h-3, 4, 4)
  end
  love.graphics.setFont(A.font(A.FONT_BODY_BOLD, 12))
  col(focused and {1,1,1} or th.text, 1)
  love.graphics.print(r.label, x + 12, y + 6)
  love.graphics.setFont(A.font(A.FONT_BODY, 9))
  col(th.text_dim, 0.8)
  love.graphics.print(r.hint or "", x + 12, y + 24)
  if r.kind == "toggle" then
    local on = cfg[r.key]
    local bw, bh = 42, 20
    local bx, by = x + w - bw - 12, y + (h - bh)/2 - 1
    col({0.05, 0.05, 0.08}, 1)
    love.graphics.rectangle("fill", bx, by, bw, bh, bh/2, bh/2)
    local kc = on and GRN or RED
    col(kc, 0.85)
    love.graphics.rectangle("fill", bx+2, by+2,
      (bw-4)*(on and 1 or 0.55), bh-4, (bh-4)/2, (bh-4)/2)
    col({0.96, 0.96, 0.97}, 1)
    local kx = on and (bx + bw - bh/2) or (bx + bh/2)
    love.graphics.circle("fill", kx, by + bh/2, bh/2 - 2)
  elseif r.kind == "slider" then
    local v = cfg[r.key] or 0
    local pct = (v - r.minv) / (r.maxv - r.minv)
    local sw, sx = 90, x + w - 90 - 60
    local sy = y + (h - 6)/2 - 1
    col({0.06, 0.05, 0.08}, 1)
    love.graphics.rectangle("fill", sx, sy, sw, 6, 3, 3)
    col(ACC_HI, 0.9)
    love.graphics.rectangle("fill", sx+1, sy+1, (sw-2)*pct, 4, 2, 2)
    love.graphics.setFont(A.font(A.FONT_MONO, 10))
    col(ACC_HI, 1)
    love.graphics.printf(v .. "%", x + w - 54, y + 14, 42, "right")
  elseif r.kind == "action" then
    love.graphics.setFont(A.font(A.FONT_MONO, 10))
    col(ACC_HI, focused and 1 or 0.75)
    love.graphics.printf("> RUN", x + w - 70, y + 14, 60, "right")
  end
end

local function draw_settings()
  local th = State.theme
  local x, y, w = 24, Frame.TOP_H + 40, W - 48
  if cfg_paths_mode then
    love.graphics.setFont(A.font(A.FONT_TITLE, 14))
    col(ACC_HI, 1)
    love.graphics.print("SCAN PATHS", x, y)
    love.graphics.setFont(A.font(A.FONT_MONO, 9))
    col(ACC, 0.7)
    love.graphics.printf("A pick . X remove . Y add", x, y, w, "right")
    local py = y + 26
    local row_h = 24
    for i, p in ipairs(cfg.paths) do
      local ry = py + (i - 1) * row_h
      local focused = (i == path_sel)
      if focused then
        col({ACC[1]*0.20, ACC[2]*0.20, ACC[3]*0.20}, 0.95)
        love.graphics.rectangle("fill", x, ry, w, row_h - 2, 3, 3)
      end
      love.graphics.setFont(A.font(A.FONT_MONO, 11))
      col(focused and {1,1,1} or th.text, 1)
      love.graphics.print("  " .. p, x + 8, ry + 5)
    end
    local ar = py + #cfg.paths * row_h
    local focused = (path_sel == #cfg.paths + 1)
    if focused then
      col({GRN[1]*0.15, GRN[2]*0.15, GRN[3]*0.15}, 0.95)
      love.graphics.rectangle("fill", x, ar, w, row_h - 2, 3, 3)
    end
    love.graphics.setFont(A.font(A.FONT_BODY_BOLD, 11))
    col(GRN, focused and 1 or 0.75)
    love.graphics.print("  + Add a path", x + 8, ar + 5)
    if #cfg.paths == 0 then
      love.graphics.setFont(A.font(A.FONT_BODY, 11))
      col(th.text_dim, 0.75)
      love.graphics.printf(
        "No paths configured. Add one to start building your library.",
        x, py + 60, w, "center")
    end
    return
  end
  love.graphics.setFont(A.font(A.FONT_TITLE, 14))
  col(ACC_HI, 1)
  love.graphics.print("SETTINGS", x, y)
  local ry = y + 26
  for i, r in ipairs(CFG_ROWS) do
    draw_cfg_row(r, ry, i == cfg_sel)
    ry = ry + 46
  end
end

function S.draw()
  D.bg()
  col(ACC, 0.05)
  for y = Frame.TOP_H, H - Frame.BOTTOM_H, 20 do
    for x = 0, W, 20 do love.graphics.rectangle("fill", x, y, 1, 1) end
  end
  D.corner_ticks(6, Frame.TOP_H + 4, W - 12,
    H - Frame.TOP_H - Frame.BOTTOM_H - 8, 18, ACC, 0.35)
  draw_header()
  if     tab == 1 then draw_player()
  elseif tab == 2 then draw_library()
  elseif tab == 3 then draw_settings() end
  Frame.draw_top("FGD", "plugins")
  local hints
  if tab == 1 then
    hints = { {key="a", label="Play/Pause"}, {key="l1", label="Prev"},
              {key="r1", label="Next"}, {key="y", label="EQ"},
              {key="x", label="Shuffle"}, {key="b", label="Exit"} }
  elseif tab == 2 then
    hints = { {key="up", label="Move"}, {key="l/r", label="Filter"},
              {key="a", label="Play"}, {key="x", label="Queue"},
              {key="y", label="Rescan"}, {key="b", label="Exit"} }
  else
    hints = { {key="up", label="Move"}, {key="a", label="Toggle/Run"},
              {key="b", label="Back"} }
  end
  Frame.draw_bottom(hints)
  Modal.draw()
  KB.draw()
  D.scanlines(W, H, 0.05)
  D.vignette(W, H, 0.55)
end

return S
