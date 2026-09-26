-- screens/mainmenu_grid.lua -- grid of cards.
local A     = require("core.assets")
local State = require("core.state")
local Input = require("core.input_map")
local Frame = require("ui.frame")
local D     = require("ui.draw")
local TitleLd = require("ui.title_loader")

local S = {}
local W, H = 640, 480

local ITEMS = {
  { label = "FILE XPLORER", screen = "filex_home",     shape = "folder", colour = {0.94, 0.66, 0.35}, sub = "browse files" },
  { label = "SYSTEM",       screen = "device",   shape = "waves",  colour = {0.48, 0.80, 0.90}, sub = "diagnostics" },
  { label = "PLUGINS",      screen = "plugins",  shape = "plug",   colour = {0.70, 0.55, 0.92}, sub = "extend FGD" },
  { label = "SETTINGS",     screen = "settings", shape = "gear",   colour = {0.55, 0.72, 0.50}, sub = "preferences" },
  { label = "EXIT",         screen = nil,        shape = "cross",  colour = {0.90, 0.22, 0.20}, sub = "quit" },
}
local N = #ITEMS

local COLS = 3
local CARD_W, CARD_H = 180, 130
local GAP_X, GAP_Y   = 12, 12
local GRID_W = COLS * CARD_W + (COLS - 1) * GAP_X
local X0 = (W - GRID_W) / 2
local Y0 = 110

local sel, t = 1, 0

local function setcol(r, g, b, a)
  love.graphics.setColor(r, g, b, a or 1)
end

local function grid_pos(i)
  local c = ((i - 1) % COLS) + 1
  local r = math.floor((i - 1) / COLS) + 1
  return X0 + (c - 1) * (CARD_W + GAP_X), Y0 + (r - 1) * (CARD_H + GAP_Y)
end

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
  love.graphics.setLineWidth(2)
  if shape == "folder" then
    love.graphics.rectangle("fill", cx-r*0.9, cy-r*0.6, r*0.7, r*0.4)
    love.graphics.rectangle("line", cx-r*0.9, cy-r*0.3, r*1.8, r*1.3)
    for i=0,2 do love.graphics.line(cx-r*0.5+i*2, cy-r*0.1, cx-r*0.5+i*2, cy+r*0.7) end
  elseif shape == "waves" then
    for k=1,3 do
      local p = 0.5 + 0.5 * math.sin(t*4 - k*0.6)
      love.graphics.setColor(c[1], c[2], c[3], (a or 1)*(0.35+0.65*p))
      love.graphics.arc("line","open", cx, cy+r*0.6, r*(0.35+k*0.22), -math.pi*0.85, -math.pi*0.15)
    end
    love.graphics.setColor(c[1], c[2], c[3], a or 1)
    love.graphics.circle("fill", cx, cy+r*0.6, 2)
  elseif shape == "gear" then
    for i=0,7 do
      local ang = i*math.pi/4 + t*0.6
      love.graphics.line(cx+math.cos(ang)*r*0.6, cy+math.sin(ang)*r*0.6,
                         cx+math.cos(ang)*r*0.95, cy+math.sin(ang)*r*0.95)
    end
    love.graphics.circle("line", cx, cy, r*0.62)
    love.graphics.circle("line", cx, cy, r*0.28)
  elseif shape == "plug" then
    love.graphics.rectangle("line", cx-r*0.7, cy-r*0.2, r*1.4, r*0.9)
    love.graphics.line(cx-r*0.35, cy-r*0.2, cx-r*0.35, cy-r*0.85)
    love.graphics.line(cx+r*0.35, cy-r*0.2, cx+r*0.35, cy-r*0.85)
    love.graphics.line(cx, cy+r*0.7, cx+r*0.6, cy+r*0.95)
  elseif shape == "cross" then
    love.graphics.setLineWidth(2.6)
    love.graphics.line(cx-r*0.8, cy-r*0.8, cx+r*0.8, cy+r*0.8)
    love.graphics.line(cx-r*0.8, cy+r*0.8, cx+r*0.8, cy-r*0.8)
  end
  love.graphics.setLineWidth(1)
end

function S.enter() sel = 1; t = 0 end
function S.leave() end
function S.update(dt) t = t + dt end

local function move(dx, dy)
  local c = ((sel - 1) % COLS) + 1
  local r = math.floor((sel - 1) / COLS) + 1
  if dx == 1 then
    c = c + 1
    if c > COLS or (r - 1) * COLS + c > N then c = COLS end
  elseif dx == -1 then
    if c > 1 then c = c - 1 end
  end
  if dy == 1 then
    if r * COLS + c <= N then r = r + 1 end
  elseif dy == -1 then
    if r > 1 then r = r - 1 end
  end
  local new = (r - 1) * COLS + c
  if new >= 1 and new <= N then sel = new end
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
  if     b == Input.LEFT  then move(-1,  0)
  elseif b == Input.RIGHT then move( 1,  0)
  elseif b == Input.UP    then move( 0, -1)
  elseif b == Input.DOWN  then move( 0,  1)
  elseif b == Input.A     then activate()
  elseif b == Input.B or b == Input.SELECT then love.event.quit() end
end
function S.hat(d)
  if     d == "left"  then move(-1, 0)
  elseif d == "right" then move( 1, 0)
  elseif d == "up"    then move( 0,-1)
  elseif d == "down"  then move( 0, 1) end
end
function S.key(k)
  if     k == "left"  then move(-1, 0)
  elseif k == "right" then move( 1, 0)
  elseif k == "up"    then move( 0,-1)
  elseif k == "down"  then move( 0, 1)
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
    local x, y = grid_pos(i)
    local focused = (i == sel)

    setcol(focused and 0.09 or 0.03,
           focused and 0.08 or 0.026,
           focused and 0.06 or 0.02, 0.95)
    love.graphics.rectangle("fill", x, y, CARD_W, CARD_H, 4, 4)

    if focused then
      local pulse = 0.6 + 0.4 * math.sin(t * 5)
      love.graphics.setColor(it.colour[1], it.colour[2], it.colour[3], 0.7 + pulse * 0.3)
      love.graphics.setLineWidth(2.5)
      love.graphics.rectangle("line", x+0.5, y+0.5, CARD_W-1, CARD_H-1, 4, 4)
      love.graphics.setLineWidth(1)
      D.glow(x + CARD_W/2, y + CARD_H/2, CARD_W * 1.05, it.colour, 0.35)
    else
      love.graphics.setColor(it.colour[1], it.colour[2], it.colour[3], 0.4)
      love.graphics.rectangle("line", x+0.5, y+0.5, CARD_W-1, CARD_H-1, 4, 4)
    end

    draw_icon(it.shape, x + CARD_W/2, y + 42, 22, it.colour, focused and 1 or 0.75)

    love.graphics.setFont(A.font(A.FONT_BODY_BOLD, focused and 14 or 12))
    love.graphics.setColor(focused and 1 or 0.85, focused and 1 or 0.85, focused and 1 or 0.85, 1)
    love.graphics.printf(it.label, x, y + 78, CARD_W, "center")

    love.graphics.setFont(A.font(A.FONT_BODY, 10))
    love.graphics.setColor(th.text_dim[1], th.text_dim[2], th.text_dim[3], 0.9)
    love.graphics.printf(it.sub, x, y + 98, CARD_W, "center")
  end

  Frame.draw_top("FGD", "mainmenu")
  Frame.draw_bottom({
    { key="left",  label="Prev"  },
    { key="right", label="Next"  },
    { key="a",     label="Enter" },
    { key="b",     label="Quit"  },
  })
  D.scanlines(W, H, 0.06)
  D.vignette(W, H, 0.55)
end

return S
