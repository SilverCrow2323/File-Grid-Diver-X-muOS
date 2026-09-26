-- screens/about_fb.lua -- Easter egg tribute.
local A     = require("core.assets")
local State = require("core.state")
local Input = require("core.input_map")
local Frame = require("ui.frame")
local D     = require("ui.draw")

local S = {}
local W, H = 640, 480
local t = 0

function S.enter() t = 0 end
function S.leave() end
function S.update(dt) t = t + dt end

function S.pad(b)
  if b == Input.B or b == Input.SELECT or b == Input.A then State.back() end
end
function S.hat(_) end
function S.key(k)
  if k == "escape" or k == "backspace" or k == "return" then State.back() end
end

function S.draw()
  do
    local ok, FBBG = pcall(require, "ui.fb_background")
    if ok then FBBG.draw("congrats", 0.55) end
  end
  love.graphics.setColor(0, 0, 0, 0.55)
  love.graphics.rectangle("fill", 0, 0, W, H)
  love.graphics.setColor(1, 1, 1, 1)

  local disc = A.image("assets/images/fb/disc.png")
  if disc then
    local iw, ih = disc:getDimensions()
    local sc = 200 / ih
    love.graphics.push()
    love.graphics.translate(190, 250)
    love.graphics.rotate(t * 0.6)
    love.graphics.draw(disc, -iw*sc/2, -ih*sc/2, 0, sc, sc)
    love.graphics.pop()
  end

  local boxart = A.image("assets/images/fb/boxart.png")
  if boxart then
    local iw, ih = boxart:getDimensions()
    local sc = 170 / ih
    love.graphics.draw(boxart, W - iw*sc - 30, 90, 0, sc, sc)
  end

  local goku = A.image("assets/images/fb/goku.png")
  if goku then
    local iw, ih = goku:getDimensions()
    local sc = 130 / ih
    love.graphics.draw(goku, 20, H - ih*sc - 55, 0, sc, sc)
  end

  love.graphics.setFont(A.font(A.FONT_TITLE, 22))
  love.graphics.setColor(1, 0.9, 0.3, 1)
  love.graphics.printf("FINAL BOUT", 0, 28, W, "center")

  love.graphics.setFont(A.font(A.FONT_MONO, 11))
  love.graphics.setColor(1, 1, 1, 0.9)
  love.graphics.printf(
    "DRAGON BALL GT: FINAL BOUT\n" ..
    "PlayStation 1 - 1997 - Bandai\n\n" ..
    "An easter egg tribute to the source of the\n" ..
    "FGDX Final Bout theme. No copyrighted\n" ..
    "content is bundled with this app.",
    0, 320, W, "center")

  Frame.draw_top("FGD", "about_fb")
  Frame.draw_bottom({ { key = "b", label = "Back" } })
  D.scanlines(W, H, 0.06)
  D.vignette(W, H, 0.55)
end

return S
