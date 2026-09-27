-- screens/grid_player.lua -- GRi▶ Player
-- Lightweight media player for File Explorer.
-- Audio: LÖVE UI + mpv daemon (IPC, non-blocking).
-- Video: launches fullscreen mpv (blocking), returns to UI after exit.
-- Chou Henka remains the advanced/separate player via Plugins.
local A     = require("core.assets")
local State = require("core.state")
local Input = require("core.input_map")
local Frame = require("ui.frame")
local D     = require("ui.draw")
local Notify= require("ui.notify")
local MP    = require("services.media_player")

local S = {}
local W, H = 640, 480
S.reserve_select = true
S.escape_passthrough = true

local ACC    = {0.35, 0.95, 1.00}
local ACC_HI = {0.60, 1.00, 1.00}
local GRN    = {0.55, 0.85, 0.45}
local RED    = {0.95, 0.30, 0.25}
local AMB    = {0.94, 0.66, 0.35}
local GRY    = {0.45, 0.45, 0.50}

local function col(c, a) love.graphics.setColor(c[1], c[2], c[3], a or 1) end
local function basename(p) return (p or ""):match("([^/]+)$") or p or "?" end

local path = nil
local info = nil
local kind = "audio"
local playing = false
local paused = false
local position = 0
local duration = 0
local volume = 70
local overlay = false
local overlay_t = 0
local OVERLAY_TTL = 4.0
local t = 0
local poll_t = 0
local POLL_RATE = 0.35
local viz_bars = {}
local VIZ_N = 28
local video_returned = false

local function reset()
  playing, paused = false, false
  position, duration = 0, 0
  overlay, overlay_t = false, 0
  viz_bars = {}
  for i = 1, VIZ_N do viz_bars[i] = 0.05 end
  video_returned = false
end

local function show_overlay()
  overlay = true
  overlay_t = OVERLAY_TTL
end

local function human_time(sec)
  if not sec or sec ~= sec or sec < 0 then return "0:00" end
  sec = math.floor(sec)
  local h = math.floor(sec / 3600)
  local m = math.floor((sec % 3600) / 60)
  local s = sec % 60
  if h > 0 then return string.format("%d:%02d:%02d", h, m, s) end
  return string.format("%d:%02d", m, s)
end

local function start_audio(p)
  MP.stop_daemon()
  local ok, err = MP.start_daemon()
  if not ok then
    Notify.show("error", err or "mpv failed")
    return false
  end
  MP.send("loadfile", p, "replace")
  MP.set_volume(volume)
  -- Attesa breve per il caricamento
  for _ = 1, 20 do
    love.timer.sleep(0.05)
    local d = MP.get_property("duration")
    if type(d) == "number" and d > 0 then duration = d; break end
  end
  playing, paused = true, false
  return true
end

local function start_video(p)
  Notify.show("info", "Video in mpv fullscreen...")
  local ok, err = MP.play_fullscreen(p)
  if not ok then
    Notify.show("error", err or "mpv failed")
    return false
  end
  playing, paused = false, false
  video_returned = true
  return true
end

function S.enter()
  reset()
  t = 0
  path = State.grid_player_path
  State.grid_player_path = nil
  if not path or path == "" then
    Notify.show("warning", "no media file")
    State.back(); return
  end
  info = MP.probe(path) or {}
  kind = MP.is_video(path) and "video" or "audio"
  if kind == "audio" then
    start_audio(path)
  else
    start_video(path)
  end
  show_overlay()
end

function S.leave()
  MP.stop_daemon()
end

function S.update(dt)
  t = t + dt
  if kind == "audio" and playing then
    poll_t = poll_t + dt
    if poll_t >= POLL_RATE then
      poll_t = 0
      local p = MP.get_property("time-pos")
      local d = MP.get_property("duration")
      local pa = MP.get_property("pause")
      if type(p) == "number" then position = p end
      if type(d) == "number" and d > 0 then duration = d end
      if type(pa) == "boolean" then paused = pa end
      if MP.get_property("idle-active") then
        playing, paused, position = false, false, 0
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
end

local function toggle_pause()
  if kind == "audio" then
    if not playing then
      start_audio(path)
    else
      MP.toggle_pause()
      paused = not paused
    end
  elseif kind == "video" then
    start_video(path)
  end
  show_overlay()
end

local function seek_relative(sec)
  if kind == "audio" and playing then
    MP.seek_relative(sec)
    position = math.max(0, math.min(duration, position + sec))
  end
  show_overlay()
end

local function toggle_overlay()
  overlay = not overlay
  if overlay then overlay_t = OVERLAY_TTL end
end

function S.pad(b)
  if not overlay then
    show_overlay()
  elseif b ~= Input.START then
    overlay_t = OVERLAY_TTL
  end
  if     b == Input.A then toggle_pause()
  elseif b == Input.B or b == Input.SELECT then
    MP.stop_daemon()
    State.back()
  elseif b == Input.START then toggle_overlay()
  elseif b == Input.R1 then seek_relative(30)
  elseif b == Input.L1 then seek_relative(-30)
  end
end

function S.hat(d)
  if not overlay then show_overlay() else overlay_t = OVERLAY_TTL end
  if     d == "right" then seek_relative(5)
  elseif d == "left"  then seek_relative(-5)
  elseif d == "up"    then
    volume = math.min(100, volume + 5); MP.set_volume(volume)
  elseif d == "down"  then
    volume = math.max(0, volume - 5); MP.set_volume(volume)
  end
end

function S.key(k)
  if k == "escape" or k == "backspace" then S.pad(Input.B)
  elseif k == "return" or k == "space" then S.pad(Input.A)
  elseif k == "right" then S.hat("right")
  elseif k == "left" then S.hat("left")
  elseif k == "up" then S.hat("up")
  elseif k == "down" then S.hat("down")
  elseif k == "e" then S.pad(Input.R1)
  elseif k == "q" then S.pad(Input.L1) end
end

-- ── Drawing ──
local function draw_progress_bar(x, y, w, h)
  local pct = (duration > 0) and math.min(1, position / duration) or 0
  col({0.06, 0.06, 0.10}, 1)
  love.graphics.rectangle("fill", x, y, w, h, h/2, h/2)
  if pct > 0 then
    col(ACC, 0.95)
    love.graphics.rectangle("fill", x, y, w * pct, h, h/2, h/2)
  end
  local kx = x + w * pct
  local ky = y + h/2
  col({0, 0, 0}, 0.5)
  love.graphics.circle("fill", kx + 1, ky + 1, h * 0.9)
  col(ACC_HI, 1)
  love.graphics.circle("fill", kx, ky, h * 0.9)
end

local function draw_viz(y)
  local x, w = 60, W - 120
  local vh = 70
  local bw = (w - (VIZ_N - 1) * 2) / VIZ_N
  for i = 1, VIZ_N do
    local v = viz_bars[i] or 0.05
    local bx = x + (i - 1) * (bw + 2)
    local bh = math.max(2, v * vh)
    local by = y + (vh - bh)
    local tt = (i - 1) / (VIZ_N - 1)
    col({0.40 + 0.55 * tt, 0.40 + 0.20 * (1 - tt), 0.95 - 0.15 * tt}, 0.95)
    love.graphics.rectangle("fill", bx, by, bw, bh, 1, 1)
  end
end

local function draw_status_badge(cx, cy)
  local label, c
  if kind == "video" and video_returned then label, c = "VIDEO ENDED", AMB
  elseif kind == "video" then label, c = "VIDEO", ACC
  elseif not playing then label, c = "STOPPED", GRY
  elseif paused then label, c = "PAUSED", AMB
  else label, c = "PLAYING", GRN end
  local f = A.font(A.FONT_MONO, 10)
  love.graphics.setFont(f)
  local tw = f:getWidth(label) + 22
  col({c[1]*0.22, c[2]*0.22, c[3]*0.22}, 1)
  love.graphics.rectangle("fill", cx - tw/2, cy - 10, tw, 20, 10, 10)
  col(c, 0.95)
  love.graphics.rectangle("line", cx - tw/2 + 0.5, cy - 9.5, tw - 1, 19, 10, 10)
  col({1,1,1}, 1)
  love.graphics.printf(label, cx - tw/2, cy - 6, tw, "center")
end

local function draw_overlay_panel()
  if not overlay then return end
  local alpha = math.min(1, overlay_t / 0.3)
  local y0 = H - Frame.BOTTOM_H - 78
  col({0.02, 0.02, 0.04}, 0.92 * alpha)
  love.graphics.rectangle("fill", 20, y0, W - 40, 72, 5, 5)
  col(ACC, 0.85 * alpha)
  love.graphics.setLineWidth(1.4)
  love.graphics.rectangle("line", 20.5, y0 + 0.5, W - 41, 71, 5, 5)
  love.graphics.setLineWidth(1)
  D.corner_ticks(28, y0 + 8, W - 56, 56, 10, ACC, alpha)
  love.graphics.setFont(A.font(A.FONT_MONO, 10))
  local hints = {
    { "A", "Play/Pause" }, { "B", "Stop/Back" },
    { "L1/R1", "Seek -30/+30s" }, { "D-Pad", "Seek -5/+5s" },
    { "UP/DN", "Volume" }, { "START", "Overlay" },
  }
  local cols = 3
  local cw = (W - 60) / cols
  for i, h in ipairs(hints) do
    local r = math.floor((i - 1) / cols)
    local c = (i - 1) % cols
    local hx = 30 + c * cw
    local hy = y0 + 12 + r * 26
    col(ACC_HI, 0.95 * alpha)
    love.graphics.print(h[1], hx, hy)
    love.graphics.setFont(A.font(A.FONT_MONO, 8))
    col({0.75, 0.80, 0.85}, 0.9 * alpha)
    love.graphics.print(h[2], hx + 42, hy + 2)
    love.graphics.setFont(A.font(A.FONT_MONO, 10))
  end
end

function S.draw()
  D.bg()
  col(ACC, 0.05)
  for gy = Frame.TOP_H, H - Frame.BOTTOM_H, 20 do
    for gx = 0, W, 20 do
      love.graphics.rectangle("fill", gx, gy, 1, 1)
    end
  end
  D.corner_ticks(6, Frame.TOP_H + 4, W - 12,
    H - Frame.TOP_H - Frame.BOTTOM_H - 8, 16, ACC, 0.30)

  -- Titolo
  love.graphics.setFont(A.font(A.FONT_TITLE, 20))
  col(ACC_HI, 1)
  love.graphics.printf("GRi▶ Player", 0, Frame.TOP_H + 12, W, "center")

  -- File name
  local fname = basename(path)
  love.graphics.setFont(A.font(A.FONT_BODY_BOLD, 14))
  col({1,1,1}, 1)
  if #fname > 46 then fname = fname:sub(1, 45) .. "…" end
  love.graphics.printf(fname, 0, Frame.TOP_H + 44, W, "center")

  -- Metadata
  love.graphics.setFont(A.font(A.FONT_MONO, 10))
  col({0.75, 0.80, 0.85}, 0.9)
  local meta = {}
  if info and info.format then meta[#meta+1] = info.format end
  if info and info.duration and info.duration > 0 then
    meta[#meta+1] = human_time(info.duration)
  end
  if info and info.audio and info.audio.codec then
    meta[#meta+1] = info.audio.codec
  end
  love.graphics.printf(table.concat(meta, "  ·  "),
    0, Frame.TOP_H + 64, W, "center")

  -- Status badge
  draw_status_badge(W/2, Frame.TOP_H + 92)

  -- Video icon / Visualizer
  if kind == "video" then
    local cx, cy = W/2, 250
    col(ACC, 0.25)
    love.graphics.circle("fill", cx, cy, 52)
    col(ACC_HI, 0.95)
    love.graphics.setLineWidth(2.4)
    love.graphics.circle("line", cx, cy, 52)
    love.graphics.setLineWidth(1)
    love.graphics.polygon("fill",
      cx - 16, cy - 26, cx - 16, cy + 26, cx + 26, cy)
    love.graphics.setFont(A.font(A.FONT_MONO, 10))
    col({0.75, 0.80, 0.85}, 0.9)
    love.graphics.printf(
      video_returned and "Press A to replay in mpv fullscreen"
                       or "Playing in mpv fullscreen",
      0, cy + 70, W, "center")
  else
    draw_viz(190)
  end

  -- Progress bar
  local bx, by = 60, 300
  local bw, bh = W - 120, 8
  draw_progress_bar(bx, by, bw, bh)
  love.graphics.setFont(A.font(A.FONT_MONO, 10))
  col(ACC_HI, 0.95)
  love.graphics.print(human_time(position), bx, by + 14)
  love.graphics.printf(human_time(duration), bx, by + 14, bw, "right")

  -- Volume
  love.graphics.setFont(A.font(A.FONT_MONO, 9))
  col(GRY, 0.85)
  love.graphics.printf("VOL " .. volume .. "%", 0, by + 36, W, "center")

  -- Overlay
  draw_overlay_panel()

  Frame.draw_top("FGD", "grid_player")
  Frame.draw_bottom({
    { key = "a",   label = "Play/Pause" },
    { key = "b",   label = "Stop/Back" },
    { key = "l1",  label = "-30s" },
    { key = "r1",  label = "+30s" },
    { key = "l/r", label = "±5s" },
  })
  D.scanlines(W, H, 0.05)
  D.vignette(W, H, 0.55)
end

return S
