-- screens/video_clipper.lua -- Video Clipper plugin.
-- Mark in/out points on a video, export clip or GIF with ffmpeg.
local A     = require("core.assets")
local State = require("core.state")
local Input = require("core.input_map")
local Frame = require("ui.frame")
local D     = require("ui.draw")
local Notify= require("ui.notify")
local Modal = require("ui.modal")
local sh    = require("core.sh")
local MP    = require("services.media_player")

local S = {}
local W, H = 640, 480
local acc = {0.95, 0.40, 0.85}

local video_path = nil
local info = nil
local duration = 0
local in_t = 0
local out_t = 0
local cursor = 0
local fmt_i = 1
local t_enter = 0

local FORMATS = {
  { id = "mp4",   label = "MP4 (H.264)", ext = ".mp4",  args = "-c:v libx264 -c:a aac" },
  { id = "mkv",   label = "MKV (copy)",  ext = ".mkv",  args = "-c copy" },
  { id = "webm",  label = "WebM (VP9)",  ext = ".webm", args = "-c:v libvpx-vp9 -c:a libopus" },
  { id = "gif",   label = "Animated GIF",ext = ".gif",  args = "-vf 'fps=15,scale=480:-1' -an" },
}

local function col(c, a) love.graphics.setColor(c[1], c[2], c[3], a or 1) end
local function basename(p) return (p or ""):match("([^/]+)$") or p or "?" end

local function have_ffmpeg()
  return sh.exec("command -v ffmpeg >/dev/null 2>&1") == 0
end

local function fmt_time(sec)
  if not sec or sec ~= sec then return "0:00" end
  sec = math.max(0, sec)
  local m = math.floor(sec / 60)
  local s = math.floor(sec % 60)
  return string.format("%d:%02d", m, s)
end

local export_job = nil  -- { script=, done=, out=, t=0, target= }

local export_job = nil  -- { script=, done=, out=, t=0, target= }

local function export_clip()
  if not have_ffmpeg() then
    Notify.show("error", "ffmpeg not installed")
    return
  end
  if out_t <= in_t then
    Notify.show("warning", "out point must be after in point")
    return
  end
  if export_job then
    Notify.show("info", "an export is already running")
    return
  end
  local fmt = FORMATS[fmt_i]
  local base = basename(video_path):gsub("%.[^.]+$", "")
  local ts = os.date("%Y%m%d_%H%M%S")
  local out_dir = "data/clips"
  sh.exec("mkdir -p " .. sh.shq(out_dir))
  local out = out_dir .. "/" .. base .. "_" .. ts .. fmt.ext
  local done_file = out .. ".done"
  local script = "/tmp/fgd_clip_" .. ts .. ".sh"

  local dur = out_t - in_t
  local cmd = "ffmpeg -y -loglevel error -ss " .. string.format("%.3f", in_t) ..
    " -i " .. sh.shq(video_path) .. " -t " .. string.format("%.3f", dur) ..
    " " .. fmt.args .. " " .. sh.shq(out) .. " 2>&1"

  local f = io.open(script, "w")
  if not f then Notify.show("error", "cannot write script"); return end
  f:write("#!/bin/sh\n")
  f:write("set +e\n")
  f:write(cmd .. "\n")
  f:write("touch " .. sh.shq(done_file) .. "\n")
  f:close()
  sh.exec("chmod +x " .. sh.shq(script))
  os.execute("(setsid sh " .. sh.shq(script) .. " </dev/null >/dev/null 2>&1 &) " ..
    "|| (nohup sh " .. sh.shq(script) .. " >/dev/null 2>&1 &) " ..
    "|| (sh " .. sh.shq(script) .. " >/dev/null 2>&1 &)")

  export_job = {
    script = script, done = done_file, out = out,
    t = 0, target = out, duration = dur,
  }
  Notify.show("info", "exporting " .. fmt.label .. "...")
end

function S.enter()
  t_enter = 0
  in_t = 0
  out_t = 0
  cursor = 0
  fmt_i = 1

  video_path = State.video_clip_path
  State.video_clip_path = nil
  if not video_path then
    Notify.show("warning", "no video file")
    State.back(); return
  end
  info = MP.probe(video_path)
  duration = (info and info.duration) or 0
  if duration > 0 then
    in_t = 0
    out_t = math.min(duration, 30)
  end
end
function S.leave() end
function S.update(dt)
  t_enter = t_enter + dt

  if export_job then
    export_job.t = export_job.t + dt
    if sh.exists(export_job.done) then
      sh.exec("rm -f " .. sh.shq(export_job.script) .. " " .. sh.shq(export_job.done))
      local ok = sh.exists(export_job.out)
      if ok then
        Notify.show("success", "saved: " .. export_job.out)
      else
        Notify.show("error", "export failed")
      end
      export_job = nil
    elseif export_job.t > 300 then
      Notify.show("error", "export timeout")
      sh.exec("rm -f " .. sh.shq(export_job.script) .. " " .. sh.shq(export_job.done))
      export_job = nil
    end
  end
end

local function skip(delta)
  if duration <= 0 then return end
  cursor = math.max(0, math.min(duration, cursor + delta))
end

function S.pad(b)
  if Modal.is_open() then
    if b == Input.A then Modal.accept()
    elseif b == Input.B then Modal.cancel() end
    return
  end
  if export_job then return end
  if export_job then return end
  if     b == Input.B or b == Input.SELECT then State.back()
  elseif b == Input.LEFT  then skip(-1)
  elseif b == Input.RIGHT then skip(1)
  elseif b == Input.L1    then skip(-10)
  elseif b == Input.R1    then skip(10)
  elseif b == Input.UP    then in_t = cursor; Notify.show("info", "IN set: " .. fmt_time(in_t))
  elseif b == Input.DOWN  then out_t = cursor; Notify.show("info", "OUT set: " .. fmt_time(out_t))
  elseif b == Input.X     then fmt_i = fmt_i % #FORMATS + 1
  elseif b == Input.Y     then
    in_t = 0
    out_t = math.min(duration, 30)
    cursor = 0
  elseif b == Input.A then
    export_clip()
  end
end

function S.hat(dir)
  if Modal.is_open() then return end
  if     dir == "left"  then skip(-1)
  elseif dir == "right" then skip(1) end
end

function S.key(k)
  if     k == "escape" or k == "backspace" then S.pad(Input.B)
  elseif k == "left"  then S.pad(Input.LEFT)
  elseif k == "right" then S.pad(Input.RIGHT)
  elseif k == "up"    then S.pad(Input.UP)
  elseif k == "down"  then S.pad(Input.DOWN)
  elseif k == "x"     then S.pad(Input.X)
  elseif k == "y"     then S.pad(Input.Y)
  elseif k == "return" or k == "space" then S.pad(Input.A) end
end

function S.draw()
  local th = State.theme
  D.bg()
  col(acc, 0.06)
  for gy = Frame.TOP_H, H - Frame.BOTTOM_H, 18 do
    for gx = 0, W, 18 do love.graphics.rectangle("fill", gx, gy, 1, 1) end
  end

  love.graphics.setFont(A.font(A.FONT_TITLE, 20))
  col(acc, 1)
  love.graphics.printf("VIDEO CLIPPER", 0, Frame.TOP_H + 8, W, "center")

  love.graphics.setFont(A.font(A.FONT_MONO, 10))
  col(acc, 0.75)
  love.graphics.printf(basename(video_path or "?"), 0, Frame.TOP_H + 34, W, "center")

  if not video_path then return end

  -- Video info
  local y = Frame.TOP_H + 60
  love.graphics.setFont(A.font(A.FONT_MONO, 10))
  col(th.text_dim, 0.85)
  if info then
    love.graphics.printf(string.format("%s · %s  ·  duration %s",
      info.format or "?", info.video and info.video.codec or "?",
      fmt_time(duration)), 0, y, W, "center")
  end

  -- Timeline
  y = y + 30
  local tl_x = 40
  local tl_w = W - 80
  local tl_h = 26

  col({0.06, 0.06, 0.10}, 1)
  love.graphics.rectangle("fill", tl_x, y, tl_w, tl_h, 3, 3)

  if duration > 0 then
    -- In/out markers
    local in_x = tl_x + (in_t / duration) * tl_w
    local out_x = tl_x + (out_t / duration) * tl_w
    col({0.35, 0.90, 0.50}, 0.35)
    love.graphics.rectangle("fill", in_x, y, math.max(2, out_x - in_x), tl_h)
    col({0.35, 0.90, 0.50}, 0.95)
    love.graphics.rectangle("fill", in_x - 1, y - 4, 2, tl_h + 8)
    col({0.95, 0.40, 0.40}, 0.95)
    love.graphics.rectangle("fill", out_x - 1, y - 4, 2, tl_h + 8)

    -- Cursor
    local cur_x = tl_x + (cursor / duration) * tl_w
    col({1, 1, 1}, 0.95)
    love.graphics.rectangle("fill", cur_x - 1, y - 6, 2, tl_h + 12)
  end

  -- Time labels
  love.graphics.setFont(A.font(A.FONT_MONO, 9))
  col(acc, 0.85)
  love.graphics.print("IN  " .. fmt_time(in_t), tl_x, y + tl_h + 6)
  col({0.95, 0.40, 0.40}, 1)
  love.graphics.printf("OUT " .. fmt_time(out_t), 0, y + tl_h + 6, tl_x + tl_w, "right")

  -- Big current time
  y = y + tl_h + 40
  love.graphics.setFont(A.font(A.FONT_TITLE, 32))
  col(acc, 1)
  love.graphics.printf(fmt_time(cursor), 0, y, W, "center")

  -- Format selector
  y = y + 50
  love.graphics.setFont(A.font(A.FONT_MONO, 12))
  col(acc, 0.95)
  love.graphics.printf("< " .. FORMATS[fmt_i].label .. " >", 0, y, W, "center")

  -- Output note
  love.graphics.setFont(A.font(A.FONT_MONO, 9))
  col(th.text_dim, 0.8)
  love.graphics.printf("output: data/clips/", 0, y + 30, W, "center")

  -- Export progress indicator
  if export_job then
    local pct_t = math.min(1, export_job.t / math.max(1, export_job.duration / 2))
    local bw = W - 100
    col({0.06, 0.06, 0.10}, 1)
    love.graphics.rectangle("fill", 50, H - Frame.BOTTOM_H - 40, bw, 10, 5, 5)
    col(acc, 0.9)
    love.graphics.rectangle("fill", 51, H - Frame.BOTTOM_H - 39, (bw - 2) * pct_t, 8, 4, 4)
    love.graphics.setFont(A.font(A.FONT_MONO, 10))
    col(acc, 1)
    love.graphics.printf(string.format("EXPORTING  %.0f%%  (ffmpeg)",
      pct_t * 100), 0, H - Frame.BOTTOM_H - 60, W, "center")
  end

  -- Export progress indicator
  if export_job then
    local pct_t = math.min(1, export_job.t / math.max(1, export_job.duration / 2))
    local bw = W - 100
    col({0.06, 0.06, 0.10}, 1)
    love.graphics.rectangle("fill", 50, H - Frame.BOTTOM_H - 40, bw, 10, 5, 5)
    col(acc, 0.9)
    love.graphics.rectangle("fill", 51, H - Frame.BOTTOM_H - 39, (bw - 2) * pct_t, 8, 4, 4)
    love.graphics.setFont(A.font(A.FONT_MONO, 10))
    col(acc, 1)
    love.graphics.printf(string.format("EXPORTING  %.0f%%  (ffmpeg)",
      pct_t * 100), 0, H - Frame.BOTTOM_H - 60, W, "center")
  end

  Frame.draw_top("FGD", "plugins")
  Frame.draw_bottom({
    { key = "l/r",  label = "Seek" },
    { key = "up",   label = "Set IN" },
    { key = "down", label = "Set OUT" },
    { key = "x",    label = "Format" },
    { key = "a",    label = "Export" },
    { key = "b",    label = "Back" },
  })
  Modal.draw()
  D.scanlines(W, H, 0.06)
end

return S
