-- screens/mainmenu_list.lua -- small centered cards, minimal.
local A     = require("core.assets")
local State = require("core.state")
local Input = require("core.input_map")
local Frame = require("ui.frame")
local D     = require("ui.draw")
local TitleLd = require("ui.title_loader")

local S = {}
local W, H = 640, 480

local ITEMS = {
  { label = "FILE XPLORER", screen = "filex_home",     shape = "folder", colour = {0.94, 0.66, 0.35} },
  { label = "SYSTEM",       screen = "device",   shape = "waves",  colour = {0.48, 0.80, 0.90} },
  { label = "PLUGINS",      screen = "plugins",  shape = "plug",   colour = {0.70, 0.55, 0.92} },
  { label = "SETTINGS",     screen = "settings", shape = "gear",   colour = {0.55, 0.72, 0.50} },
  { label = "EXIT",         screen = nil,        shape = "cross",  colour = {0.90, 0.22, 0.20} },
}
local N = #ITEMS

local CARD_W, CARD_H = 320, 42
local GAP            = 8
local X0             = (W - CARD_W) / 2
local Y0             = 130

local sel, t = 1, 0

local function draw_icon(shape, cx, cy, r, c, a)
  -- Try image asset first (from assets/images/titles/)
  local img_map = {}
  local img = A.image(img_map[shape or ""])
  if img then
    local iw, ih = img:getDimensions()
    local target_h = (r or 20) * 2.2
    local sc = target_h / ih
    local dw = iw * sc
    love.graphics.setColor(1, 1, 1, a or 1)
    love.graphics.draw(img, cx - dw/2, cy - target_h/2, 0, sc, sc)
    love.graphics.setColor(1, 1, 1, 1)
    return
  end

  love.graphics.setColor(c[1], c[2], c[3], a or 1)
  love.graphics.setLineWidth(1.6)
  if shape == "folder" then
    love.graphics.rectangle("fill", cx-r*0.9, cy-r*0.6, r*0.7, r*0.4)
    love.graphics.rectangle("line", cx-r*0.9, cy-r*0.3, r*1.8, r*1.3)
  elseif shape == "waves" then
    for k=1,3 do
      local p = 0.5 + 0.5*math.sin(t*4 - k*0.6)
      love.graphics.setColor(c[1], c[2], c[3], (a or 1)*(0.35+0.65*p))
      love.graphics.arc("line","open", cx, cy+r*0.5, r*(0.35+k*0.22), -math.pi*0.85, -math.pi*0.15)
    end
  elseif shape == "gear" then
    for i=0,7 do
      local ang = i*math.pi/4 + t*0.6
      love.graphics.line(cx+math.cos(ang)*r*0.5, cy+math.sin(ang)*r*0.5,
                         cx+math.cos(ang)*r*0.9, cy+math.sin(ang)*r*0.9)
    end
    love.graphics.circle("line", cx, cy, r*0.55)
  elseif shape == "plug" then
    love.graphics.rectangle("line", cx-r*0.7, cy-r*0.2, r*1.4, r*0.9)
    love.graphics.line(cx-r*0.35, cy-r*0.2, cx-r*0.35, cy-r*0.85)
    love.graphics.line(cx+r*0.35, cy-r*0.2, cx+r*0.35, cy-r*0.85)
  elseif shape == "cross" then
    love.graphics.setLineWidth(2.2)
    love.graphics.line(cx-r*0.7, cy-r*0.7, cx+r*0.7, cy+r*0.7)
    love.graphics.line(cx-r*0.7, cy+r*0.7, cx+r*0.7, cy-r*0.7)
  end
  love.graphics.setLineWidth(1)
end

function S.enter() sel = 1; t = 0 end
function S.leave() end
function S.update(dt) t = t + dt end

local function move(d)
  sel = sel + d
  if sel < 1 then sel = N end
  if sel > N then sel = 1 end
end

local function activate()
  local it = ITEMS[sel]
  if it.screen then
    local ok, SFX = pcall(require, "core.audio")
    if ok then SFX.play("enter") end
    State.go(it.screen)
  else
    love.event.quit()
  end
end

function S.pad(b)
  if     b == Input.UP    or b == Input.LEFT  then move(-1)
  elseif b == Input.DOWN  or b == Input.RIGHT then move( 1)
  elseif b == Input.A     then activate()
  elseif b == Input.B or b == Input.SELECT then love.event.quit() end
end
function S.hat(d)
  if d == "up" or d == "left" then move(-1)
  elseif d == "down" or d == "right" then move(1) end
end
function S.key(k)
  if     k == "up" or k == "left"  then move(-1)
  elseif k == "down" or k == "right" then move(1)
  elseif k == "return" or k == "space" then activate()
  elseif k == "escape" then love.event.quit() end
end

function S.draw()
  local th = State.theme
  D.bg()
  love.graphics.setColor(th.grid_faint[1], th.grid_faint[2], th.grid_faint[3], 0.08)
  for y=0,H,16 do for x=0,W,16 do
    if ((x+y)/16)%2==0 then love.graphics.rectangle("fill", x, y, 1, 1) end
  end end

  for i, it in ipairs(ITEMS) do
    local x = X0
    local y = Y0 + (i - 1) * (CARD_H + GAP)
    local focused = (i == sel)

    love.graphics.setColor(focused and 0.09 or 0.03,
                           focused and 0.08 or 0.026,
                           focused and 0.06 or 0.02, 0.95)
    love.graphics.rectangle("fill", x, y, CARD_W, CARD_H, 4, 4)

    if focused then
      local pulse = 0.6 + 0.4*math.sin(t*5)
      love.graphics.setColor(it.colour[1], it.colour[2], it.colour[3], 0.7 + pulse*0.3)
      love.graphics.setLineWidth(2)
      love.graphics.rectangle("line", x+0.5, y+0.5, CARD_W-1, CARD_H-1, 4, 4)
      love.graphics.setLineWidth(1)
      love.graphics.setColor(it.colour[1], it.colour[2], it.colour[3], 0.9)
      love.graphics.rectangle("fill", x, y + 6, 3, CARD_H - 12)
    else
      love.graphics.setColor(it.colour[1], it.colour[2], it.colour[3], 0.35)
      love.graphics.rectangle("line", x+0.5, y+0.5, CARD_W-1, CARD_H-1, 4, 4)
    end

    local cx = x + 26
    local cy = y + CARD_H / 2
    draw_icon(it.shape, cx, cy, 9, it.colour, focused and 1 or 0.75)

    love.graphics.setFont(A.font(A.FONT_BODY_BOLD, focused and 14 or 12))
    love.graphics.setColor(focused and 1 or 0.78, focused and 1 or 0.78, focused and 1 or 0.78, 1)
    love.graphics.print(it.label, x + 52, y + CARD_H / 2 - 8)
  end

  Frame.draw_top("FGD", "mainmenu")
  Frame.draw_bottom({
    { key="up",   label="Prev"  },
    { key="down", label="Next"  },
    { key="a",    label="Enter" },
    { key="b",    label="Quit"  },
  })
  D.scanlines(W, H, 0.06)
  D.vignette(W, H, 0.55)
end

return S
