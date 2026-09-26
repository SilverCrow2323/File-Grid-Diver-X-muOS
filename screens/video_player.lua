-- screens/video_player.lua -- video player shell for mpv.
local A     = require("core.assets")
local State = require("core.state")
local Input = require("core.input_map")
local Frame = require("ui.frame")
local D     = require("ui.draw")
local MP    = require("services.media_player")
local Notify= require("ui.notify")

local S = {}
local W, H = 640, 480
local path = nil
local info = nil
local t_enter = 0

function S.enter()
  path = State.selected_path
  t_enter = 0
  if not path then
    Notify.show("warning", "no video file")
    State.back()
    return
  end
  info = MP.probe(path)
end

function S.leave() MP.kill() end
function S.update(dt) t_enter = t_enter + dt end

function S.pad(b)
  if b == Input.B or b == Input.SELECT then MP.kill(); State.back() end
  if b == Input.A then
    local ok, err = MP.play(path)
    if not ok then Notify.show("error", err or "mpv failed")
    else Notify.show("success", "playing") end
  end
end
function S.hat(_) end
function S.key(k)
  if k == "escape" or k == "backspace" then MP.kill(); State.back() end
  if k == "return" or k == "space" then S.pad(Input.A) end
end

function S.draw()
  D.bg()
  local th = State.theme
  col(th.amber_hi, 1)
  love.graphics.setFont(A.font(A.FONT_TITLE, 22))
  love.graphics.printf("VIDEO PLAYER", 0, 60, W, "center")

  local name = path and (path:match("([^/]+)$") or "?") or "?"
  love.graphics.setFont(A.font(A.FONT_BODY_BOLD, 13))
  col({1,1,1}, 1)
  love.graphics.printf(name, 0, 120, W, "center")

  if info and info.video then
    love.graphics.setFont(A.font(A.FONT_MONO, 11))
    col(th.text_dim, 0.9)
    love.graphics.printf(string.format("%dx%d  ·  %s",
      info.video.w or 0, info.video.h or 0,
      info.video.codec or "?"), 0, 160, W, "center")
  end

  love.graphics.setFont(A.font(A.FONT_BODY, 12))
  col(th.amber_hi, 0.9)
  love.graphics.printf("A plays via mpv  ·  B stops and exits", 0, H - 100, W, "center")

  Frame.draw_top("FGD", "video")
  Frame.draw_bottom({
    { key = "a", label = "Play" },
    { key = "b", label = "Exit" },
  })
  D.scanlines(W, H, 0.06)
end

return S
