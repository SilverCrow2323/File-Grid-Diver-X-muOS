-- screens/about_fb_game.lua -- "On the 'Final Bout'" info screen.
local A     = require("core.assets")
local State = require("core.state")
local Input = require("core.input_map")
local Frame = require("ui.frame")
local D     = require("ui.draw")

local S = {}
local W, H = 640, 480
local t = 0

function S.enter()  t = 0 end
function S.leave() end
function S.update(dt) t = t + dt end

function S.pad(b)
  if b == Input.B or b == Input.SELECT or b == Input.A then State.back() end
end
function S.hat(_) end
function S.key(k)
  if k == "escape" or k == "backspace" or k == "return" then State.back() end
end

local function draw_bg()
  local bg = A.image("assets/images/fb/bg/bg.png")
  if bg then
    local iw, ih = bg:getDimensions()
    local sc = math.max(W / iw, H / ih)
    local dw, dh = iw * sc, ih * sc
    love.graphics.setColor(1, 1, 1, 0.85)
    love.graphics.draw(bg, (W - dw) / 2, (H - dh) / 2, 0, sc, sc)
    love.graphics.setColor(1, 1, 1, 1)
  end
  love.graphics.setColor(0, 0, 0, 0.55)
  love.graphics.rectangle("fill", 0, Frame.TOP_H, W * 0.58,
    H - Frame.TOP_H - Frame.BOTTOM_H)
  love.graphics.setColor(1, 1, 1, 1)
end

local function draw_disc(cx, cy, size)
  local disc = A.image("assets/images/fb/disc.png")
  if not disc then return end
  local iw, ih = disc:getDimensions()
  local sc = size / math.max(iw, ih)
  love.graphics.push()
  love.graphics.translate(cx, cy)
  love.graphics.rotate(t * 4)
  love.graphics.setColor(1, 1, 1, 0.92)
  love.graphics.draw(disc, -iw * sc / 2, -ih * sc / 2, 0, sc, sc)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.pop()
end

local function draw_boxart(cx, cy, target_h)
  local box = A.image("assets/images/fb/boxart.png")
  if not box then return end
  local iw, ih = box:getDimensions()
  local sc = target_h / ih
  local dw, dh = iw * sc, ih * sc
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(box, cx - dw / 2, cy - dh / 2, 0, sc, sc)
end

local BODY =
  "Often dismissed as the worst Dragon Ball game ever made \u{2014} which " ..
  "is simply not true \u{2014} Final Bout still left an indelible mark on " ..
  "every fan who actually played it.\n\n" ..
  "And many of us did. For hours. 25-30 years ago.\n\n" ..
  "What sets Final Bout apart from every other title in the " ..
  "franchise is its unique, striking visual identity: like Goku " ..
  "himself on the cover.\n\n" ..
  "Or the giant final boss, Super Baby \u{2014} a name that caused no " ..
  "small amount of confusion in everyone who hadn't seen DBGT " ..
  "yet (and there were many)."

function S.draw()
  draw_bg()

  local content_top = Frame.TOP_H
  local content_bot = H - Frame.BOTTOM_H
  local content_mid = content_top + (content_bot - content_top) / 2

  -- Right side: disc behind + boxart in front
  local box_size = 190
  local box_cx   = W - 130
  local box_cy   = content_mid
  local disc_cx  = box_cx + 25
  local disc_size = 200

  draw_disc(disc_cx, box_cy, disc_size)
  draw_boxart(box_cx, box_cy, box_size)

  -- Left side: text
  local tx = 24
  local tw = 340
  local ty = content_top + 18

  love.graphics.setFont(A.font(A.FONT_TITLE, 22))
  love.graphics.setColor(1, 0.9, 0.3, 1)
  love.graphics.printf("ON THE 'FINAL BOUT'", tx, ty, tw, "left")

  love.graphics.setFont(A.font(A.FONT_MONO, 10))
  love.graphics.setColor(1, 0.75, 0.4, 1)
  love.graphics.print("PS1  \u{00B7}  1997  \u{00B7}  Bandai", tx, ty + 30)

  love.graphics.setColor(1, 0.9, 0.3, 0.35)
  love.graphics.rectangle("fill", tx, ty + 46, tw, 1)

  love.graphics.setFont(A.font(A.FONT_BODY, 11))
  love.graphics.setColor(0.96, 0.96, 0.96, 1)
  love.graphics.printf(BODY, tx, ty + 58, tw, "left")

  love.graphics.setFont(A.font(A.FONT_MONO, 9))
  love.graphics.setColor(1, 0.75, 0.4, 0.85)
  love.graphics.printf("~ 25-30 years later, still flying ~",
    tx, content_bot - 26, tw, "left")

  Frame.draw_top("FGD", "about")
  Frame.draw_bottom({ { key = "b", label = "Back" } })
  D.scanlines(W, H, 0.06)
  D.vignette(W, H, 0.55)
end

return S
