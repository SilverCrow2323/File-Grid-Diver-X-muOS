-- screens/player.lua -- player con OSD info + track selector.
local A       = require("core.assets")
local D       = require("ui.draw")
local Input   = require("core.input_map")
local T       = require("plugins.chou_henka.ui.theme")
local W_      = require("plugins.chou_henka.ui.widgets")
local Icons   = require("plugins.chou_henka.ui.icons")
local PB      = require("plugins.chou_henka.core.playback")
local CFG     = require("plugins.chou_henka.core.config")
local MP      = require("services.media_player")
local WS      = require("plugins.chou_henka.core.watchstate")
local Notify  = require("ui.notify")

local function overlay_bottom() return 100 end

local M = {}
local W, H = 640, 480

local path, info, kind
local playing, paused = false, false
local position, duration = 0, 0
local overlay, overlay_t = false, 0
local OVERLAY_TTL = 4.0
local t, poll_t = 0, 0
local POLL_RATE = 0.35
local viz, VIZ_N = {}, 28
local video_returned = false

local track_ui = nil   -- { open=, tab="audio"|"sub", sel=, audio={}, subs={} }
local media_info = {}
local info_poll = 0
local INFO_RATE = 2.0

local function col(c,a) love.graphics.setColor(c[1],c[2],c[3],a or 1) end
local function basename(p) return (p or ""):match("([^/]+)$") or p or "?" end
local function htime(s)
  if not s or s ~= s or s < 0 then return "0:00" end
  s = math.floor(s)
  local h = math.floor(s/3600); local m = math.floor((s%3600)/60); local ss = s%60
  if h > 0 then return string.format("%d:%02d:%02d", h, m, ss) end
  return string.format("%d:%02d", m, ss)
end
local function human_bitrate(bps)
  if not bps or bps <= 0 then return nil end
  if bps >= 1000000 then return string.format("%.1f Mbps", bps/1000000) end
  if bps >= 1000    then return string.format("%d kbps", math.floor(bps/1000)) end
  return string.format("%d bps", bps)
end

local function show_overlay() overlay = true; overlay_t = OVERLAY_TTL end

local function refresh_info()
  if kind == "audio" and playing then
    media_info = PB.media_info() or {}
  end
end

function M.play(p)
  path = p
  if not path then return end
  info = PB.probe(path) or {}
  kind = MP.is_video(path) and "video" or "audio"
  position, duration, paused = 0, 0, false
  video_returned = false
  media_info = {}

  if kind == "audio" then
    local ok, err = PB.start_audio(path)
    if not ok then
      Notify.show("error", err or "playback failed")
      playing = false
    else
      playing = true
      for _ = 1, 20 do
        love.timer.sleep(0.05)
        local d = PB.get_prop("duration")
        if type(d) == "number" and d > 0 then duration = d; break end
      end
      -- resume
      local rs = WS.get_resume(path)
      if rs and rs.pos and rs.pos > 5 then
        pcall(function() PB.seek(rs.pos) end)
        position = rs.pos
        Notify.show("info", "Riprendo da " .. htime(rs.pos))
      end
      WS.touch_recent(path)
      refresh_info()
    end
  else
    Notify.show("info", "Opening in mpv fullscreen...")
    local ok, err = PB.play_fullscreen_video(path)
    if not ok then Notify.show("error", err or "mpv failed")
    else video_returned = true; playing = false end
  end
  show_overlay()
end

function M.enter()
  t, poll_t, info_poll = 0, 0, 0
  viz = {}; for i = 1, VIZ_N do viz[i] = 0.05 end
  track_ui = nil
end
function M.leave()
  if path and playing and duration > 0 then
    WS.set_resume(path, position, duration)
  end
  PB.stop()
end

local _save_t = 0
function M.update(dt)
  t = t + dt
  if kind == "audio" and playing then
    poll_t = poll_t + dt
    info_poll = info_poll + dt
    if poll_t >= POLL_RATE then
      poll_t = 0
      local p = PB.get_prop("time-pos")
      local d = PB.get_prop("duration")
      local pa = PB.get_prop("pause")
      if type(p) == "number" then position = p end
      if type(d) == "number" and d > 0 then duration = d end
      if type(pa) == "boolean" then paused = pa end
      if PB.get_prop("idle-active") then
        playing, paused, position = false, false, 0
      end
    end
    if info_poll >= INFO_RATE then
      info_poll = 0
      refresh_info()
    end
    if duration > 0 then
      _save_t = _save_t + dt
      if _save_t >= 5 then
        _save_t = 0
        WS.set_resume(path, position, duration)
      end
      if position / duration >= 0.90 then
        WS.mark_watched(path)
        WS.clear_resume(path)
      end
    end
  end
  if overlay then
    overlay_t = overlay_t - dt
    if overlay_t <= 0 then overlay = false end
  end
  if kind == "audio" then
    local active = playing and not paused
    for i = 1, VIZ_N do
      local target
      if active then
        local n1 = math.sin(t*6 + i*0.7)*0.5 + 0.5
        local n2 = math.sin(t*11 + i*1.3)*0.3 + 0.5
        local n3 = math.sin(t*2.7 + i*0.2)*0.2 + 0.5
        target = math.max(0.05, n1*0.5 + n2*0.3 + n3*0.2) * (1 - (i/VIZ_N)*0.5)
      else target = 0.05 end
      viz[i] = viz[i] + (target - viz[i]) * math.min(1, dt*8)
    end
  end
end

local function open_track_ui(tab)
  local tracks = PB.get_tracks()
  track_ui = {
    open = true,
    tab = tab or "audio",
    sel = 1,
    audio = tracks.audio or {},
    subs = tracks.subs or {},
  }
end

local function close_track_ui() track_ui = nil end

local function select_current()
  if not track_ui then return end
  if track_ui.tab == "audio" then
    local tr = track_ui.audio[track_ui.sel]
    if tr then PB.set_audio(tr.id) end
  else
    local states = { { id = "auto", label = "Auto" }, { id = "no", label = "Disable" } }
    for _, s in ipairs(track_ui.subs) do
      states[#states+1] = { id = s.id, label = s.title or s.lang or ("Track " .. s.id) }
    end
    local item = states[track_ui.sel]
    if item then
      if item.id == "no" then PB.disable_sub()
      elseif item.id == "auto" then PB.auto_sub()
      else PB.set_sub(item.id) end
    end
  end
  close_track_ui()
  show_overlay()
end

local function move_track(d)
  if not track_ui then return end
  local n
  if track_ui.tab == "audio" then n = #track_ui.audio
  else n = #track_ui.subs + 2 end  -- + auto + no
  if n == 0 then return end
  track_ui.sel = track_ui.sel + d
  if track_ui.sel < 1 then track_ui.sel = n end
  if track_ui.sel > n then track_ui.sel = 1 end
end

function M.pad(b)
  if track_ui and track_ui.open then
    if b == Input.UP then move_track(-1)
    elseif b == Input.DOWN then move_track(1)
    elseif b == Input.LEFT or b == Input.RIGHT then
      track_ui.tab = (track_ui.tab == "audio") and "sub" or "audio"
      track_ui.sel = 1
    elseif b == Input.A then select_current()
    elseif b == Input.B or b == Input.SELECT then close_track_ui() end
    return false
  end

  if not overlay then show_overlay() else overlay_t = OVERLAY_TTL end
  if     b == Input.A then
    if kind == "audio" then
      if not playing then M.play(path)
      else PB.toggle_pause(); paused = not paused end
    else M.play(path) end
    show_overlay()
  elseif b == Input.B or b == Input.SELECT then
    PB.stop(); return "back"
  elseif b == Input.START then
    overlay = not overlay; if overlay then overlay_t = OVERLAY_TTL end
  elseif b == Input.X then
    local e = PB.cycle_engine(1)
    Notify.show("info", "Engine: " .. e)
  elseif b == Input.Y then
    open_track_ui("audio")
  elseif b == Input.L2 then
    local tr = PB.cycle_audio(-1)
    if tr then Notify.show("info", "Audio: " .. (tr.title or tr.lang or tr.id)) end
  elseif b == Input.R2 then
    local s = PB.cycle_sub(1)
    if s == "no" then Notify.show("info", "Subtitles off")
    elseif s == "auto" then Notify.show("info", "Subtitles auto")
    else Notify.show("info", "Sub: " .. tostring(s)) end
  elseif b == Input.R1 then PB.seek(30); position = math.min(duration, position + 30)
  elseif b == Input.L1 then PB.seek(-30); position = math.max(0, position - 30)
  end
  return false
end

function M.hat(dir)
  if track_ui and track_ui.open then
    if dir == "up" then move_track(-1)
    elseif dir == "down" then move_track(1) end
    return
  end
  if not overlay then show_overlay() else overlay_t = OVERLAY_TTL end
  if dir == "right" then PB.seek(5); position = math.min(duration, position + 5)
  elseif dir == "left" then PB.seek(-5); position = math.max(0, position - 5)
  elseif dir == "up" then PB.set_volume((CFG.get("player","volume") or 70) + 5)
  elseif dir == "down" then PB.set_volume((CFG.get("player","volume") or 70) - 5) end
end

function M.key(k)
  if track_ui and track_ui.open then
    if k == "up" then move_track(-1)
    elseif k == "down" then move_track(1)
    elseif k == "left" or k == "right" then
      track_ui.tab = (track_ui.tab == "audio") and "sub" or "audio"
      track_ui.sel = 1
    elseif k == "return" or k == "space" then select_current()
    elseif k == "escape" then close_track_ui() end
    return false
  end
  if k == "escape" then PB.stop(); return "back" end
  if k == "return" or k == "space" then M.pad(Input.A) end
  if k == "left" then M.hat("left")
  elseif k == "right" then M.hat("right")
  elseif k == "up" then M.hat("up")
  elseif k == "down" then M.hat("down")
  elseif k == "t" then open_track_ui("audio")
  elseif k == "e" then PB.cycle_engine(1) end
  return false
end

-- ── Drawing ──────────────────────────────────────────────────
local function draw_viz(y)
  local x, w = 60, W - 120
  local vh = 70
  local bw = (w - (VIZ_N - 1) * 2) / VIZ_N
  for i = 1, VIZ_N do
    local v = viz[i] or 0.05
    local bx = x + (i - 1) * (bw + 2)
    local bh = math.max(2, v * vh)
    local by = y + (vh - bh)
    local tt = (i - 1) / (VIZ_N - 1)
    col({0.40 + 0.55*tt, 0.40 + 0.20*(1-tt), 0.95 - 0.15*tt}, 0.95)
    love.graphics.rectangle("fill", bx, by, bw, bh, 1, 1)
  end
end

local function draw_info_panel(y)
  local th = T.current()
  local m = media_info
  local bits = {}
  if m.width and m.height then
    bits[#bits+1] = string.format("%dx%d", m.width, m.height)
  end
  if m.fps then bits[#bits+1] = string.format("%.2f fps", m.fps) end
  if m.video_codec then bits[#bits+1] = m.video_codec:upper() end
  if m.audio_codec then
    local s = m.audio_codec:upper()
    if m.audio_ch then s = s .. " " .. tostring(m.audio_ch) .. "ch" end
    bits[#bits+1] = s
  end
  local br = human_bitrate(m.bitrate)
  if br then bits[#bits+1] = br end

  if #bits == 0 then return end
  love.graphics.setFont(A.font(A.FONT_MONO, 9))
  col(th.accent_hi, 0.85)
  love.graphics.printf(table.concat(bits, "  -  "), 0, y, W, "center")
end

local function draw_track_selector()
  if not track_ui or not track_ui.open then return end
  local th = T.current()
  local x, y = 40, 90
  local w, h = W - 80, H - 180

  love.graphics.setColor(0, 0, 0, 0.75)
  love.graphics.rectangle("fill", 0, 0, W, H)
  col({0.020, 0.015, 0.035}, 0.98)
  love.graphics.rectangle("fill", x, y, w, h, 5, 5)
  col(th.accent_hi, 0.9)
  love.graphics.setLineWidth(1.6)
  love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, 5, 5)
  love.graphics.setLineWidth(1)
  D.corner_ticks(x + 8, y + 8, w - 16, h - 16, 12, th.accent_hi, 0.9)

  -- tab
  local tab_y = y + 12
  local tabs = { { id="audio", label="AUDIO" }, { id="sub", label="SUBTITLES" } }
  local tx = x + 20
  for _, tb in ipairs(tabs) do
    local focused = (tb.id == track_ui.tab)
    love.graphics.setFont(A.font(A.FONT_MONO, 10))
    local tw = 120
    if focused then
      col(th.accent, 0.22)
      love.graphics.rectangle("fill", tx, tab_y, tw, 22, 3, 3)
      col(th.accent_hi, 0.95)
      love.graphics.rectangle("line", tx + 0.5, tab_y + 0.5, tw - 1, 21, 3, 3)
    else
      col(th.text_dim, 0.5)
      love.graphics.rectangle("line", tx + 0.5, tab_y + 0.5, tw - 1, 21, 3, 3)
    end
    col(focused and {1,1,1} or th.text_dim, 1)
    love.graphics.printf(tb.label, tx, tab_y + 6, tw, "center")
    tx = tx + tw + 6
  end

  -- list
  local ly = tab_y + 34
  local lh = 22
  local rows = {}
  if track_ui.tab == "audio" then
    if #track_ui.audio == 0 then
      rows[1] = { label = "(no audio tracks detected)" }
    else
      local cur = PB.get_current_audio()
      for _, tr in ipairs(track_ui.audio) do
        rows[#rows+1] = {
          label = (tr.title or tr.lang or ("Track " .. tostring(tr.id))) ..
                  (tr.codec and ("  [" .. tr.codec .. "]") or ""),
          current = (tr.id == cur),
        }
      end
    end
  else
    rows[1] = { label = "Auto (first available)", id = "auto" }
    rows[2] = { label = "Disable subtitles", id = "no" }
    for _, s in ipairs(track_ui.subs) do
      rows[#rows+1] = {
        label = (s.title or s.lang or ("Track " .. tostring(s.id))) ..
                (s.codec and ("  [" .. s.codec .. "]") or ""),
        id = s.id,
      }
    end
  end

  for i, r in ipairs(rows) do
    local ry = ly + (i - 1) * lh
    if ry + lh > y + h - 30 then break end
    local focused = (i == track_ui.sel)
    if focused then
      col(th.accent, 0.22)
      love.graphics.rectangle("fill", x + 16, ry - 1, w - 32, lh - 2, 3, 3)
      col(th.accent_hi, 0.95)
      love.graphics.rectangle("line", x + 16.5, ry - 0.5, w - 33, lh - 3, 3, 3)
    end
    love.graphics.setFont(A.font(A.FONT_BODY, 11))
    col(focused and {1,1,1} or th.text, 1)
    love.graphics.print(r.label, x + 28, ry + 3)
    if r.current then
      love.graphics.setFont(A.font(A.FONT_MONO, 9))
      col(th.ok, 1)
      love.graphics.printf("CURRENT", 0, ry + 5, x + w - 20, "right")
    end
  end

  love.graphics.setFont(A.font(A.FONT_MONO, 9))
  col(th.text_dim, 0.7)
  love.graphics.printf("UP/DN: move  -  L/R: tab  -  A: select  -  B: close",
    x, y + h - 22, w, "center")
end

local function draw_overlay_panel()
  if not overlay then return end
  local th = T.current()
  local alpha = math.min(1, overlay_t / 0.3)
  local y0 = H - overlay_bottom()
  col({0.02, 0.02, 0.04}, 0.92 * alpha)
  love.graphics.rectangle("fill", 20, y0, W - 40, 72, 5, 5)
  col(th.accent, 0.85 * alpha)
  love.graphics.setLineWidth(1.4)
  love.graphics.rectangle("line", 20.5, y0 + 0.5, W - 41, 71, 5, 5)
  love.graphics.setLineWidth(1)
  D.corner_ticks(28, y0 + 8, W - 56, 56, 10, th.accent, alpha)
  love.graphics.setFont(A.font(A.FONT_MONO, 10))
  local hints = {
    {"A","Play/Pause"}, {"B","Back"}, {"L1/R1","+/-30s"},
    {"D-Pad","+/-5s"},  {"Y","Tracks"}, {"L2/R2","Audio/Sub"},
    {"X","Engine"},     {"UP/DN","Volume"}, {"START","Toggle OSD"},
  }
  local cols = 3
  local cw = (W - 60) / cols
  for i, h in ipairs(hints) do
    local r = math.floor((i - 1) / cols)
    local c = (i - 1) % cols
    local hx = 30 + c * cw
    local hy = y0 + 12 + r * 18
    col(th.accent_hi, 0.95 * alpha)
    love.graphics.print(h[1], hx, hy)
    love.graphics.setFont(A.font(A.FONT_MONO, 8))
    col({0.75, 0.80, 0.85}, 0.9 * alpha)
    love.graphics.print(h[2], hx + 42, hy + 2)
    love.graphics.setFont(A.font(A.FONT_MONO, 10))
  end
end


function M.draw()
  local th = T.current()
  D.bg()
  col(th.accent, 0.05)
  for gy = 30, H - 20, 20 do for gx = 0, W, 20 do
    love.graphics.rectangle("fill", gx, gy, 1, 1)
  end end

  love.graphics.setFont(A.font(A.FONT_TITLE, 20))
  col(th.accent_hi, 1)
  love.graphics.printf("CHOU HENKA - PLAYER", 0, 40, W, "center")

  local fname = basename(path)
  love.graphics.setFont(A.font(A.FONT_BODY_BOLD, 14))
  col({1,1,1}, 1)
  if #fname > 46 then fname = fname:sub(1, 45) .. "..." end
  love.graphics.printf(fname, 0, 74, W, "center")

  love.graphics.setFont(A.font(A.FONT_MONO, 10))
  col(th.text_dim, 0.9)
  local meta = {}
  if info and info.format then meta[#meta+1] = info.format end
  if duration > 0 then meta[#meta+1] = htime(duration) end
  meta[#meta+1] = "engine: " .. (CFG.get("player","engine") or "normal")
  love.graphics.printf(table.concat(meta, "  -  "), 0, 94, W, "center")

  draw_info_panel(110)

  if kind == "video" then
    local cx, cy = W/2, 250
    col(th.accent, 0.25); love.graphics.circle("fill", cx, cy, 52)
    col(th.accent_hi, 0.95); love.graphics.setLineWidth(2.4)
    love.graphics.circle("line", cx, cy, 52); love.graphics.setLineWidth(1)
    love.graphics.polygon("fill", cx-16, cy-26, cx-16, cy+26, cx+26, cy)
  else draw_viz(180) end

  local bx, by, bw, bh = 60, 300, W - 120, 8
  local pct = (duration > 0) and math.min(1, position/duration) or 0
  W_.progress(bx, by, bw, bh, pct, th.accent, true)
  love.graphics.setFont(A.font(A.FONT_MONO, 10))
  col(th.accent_hi, 0.95)
  love.graphics.print(htime(position), bx, by + 14)
  love.graphics.printf(htime(duration), bx, by + 14, bw, "right")
  love.graphics.setFont(A.font(A.FONT_MONO, 9))
  col(th.text_dim, 0.85)
  love.graphics.printf("VOL " .. (CFG.get("player","volume") or 70) .. "%",
    0, by + 36, W, "center")

  draw_overlay_panel()
  draw_track_selector()
end

return M
