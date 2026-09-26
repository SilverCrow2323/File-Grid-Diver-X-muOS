-- screens/mainmenu_expanded.lua -- cyberpunk tags.
local A     = require("core.assets")
local State = require("core.state")
local Input = require("core.input_map")
local Frame = require("ui.frame")
local D     = require("ui.draw")
local TitleLd = require("ui.title_loader")

local S = {}
local W, H = 640, 480

local ITEMS = {
  { label = "FILE XPLORER", screen = "filex_home",
    cat = "BROWSE", shape = "folder", colour = {0.94, 0.66, 0.35},
    sub = "browse, move, copy, delete files on any mounted volume" },
  { label = "SYSTEM",       screen = "device",
    cat = "DIAG",   shape = "waves",  colour = {0.48, 0.80, 0.90},
    sub = "cpu, ram, thermal, network, process monitor" },
  { label = "PLUGINS",      screen = "plugins",
    cat = "EXTEND", shape = "plug",   colour = {0.70, 0.55, 0.92},
    sub = "appearance, layout, browser, indicators, dev console" },
  { label = "SETTINGS",     screen = "settings",
    cat = "CONFIG", shape = "gear",   colour = {0.55, 0.72, 0.50},
    sub = "input holmes, minoru catalogue, storage peeper" },
  { label = "EXIT",         screen = nil,
    cat = "SESSION", shape = "cross",  colour = {0.90, 0.22, 0.20},
    sub = "terminate this session" },
}
local N = #ITEMS

local CARD_H = 58
local CARD_W = W - 48
local GAP    = 6
local X0     = 24
local Y0     = 100

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
  love.graphics.setLineWidth(1.8)
  if shape == "folder" then
    love.graphics.rectangle("fill", cx-r*0.9, cy-r*0.6, r*0.7, r*0.4)
    love.graphics.rectangle("line", cx-r*0.9, cy-r*0.3, r*1.8, r*1.3)
    for i=0,2 do love.graphics.line(cx-r*0.5+i*2, cy-r*0.1, cx-r*0.5+i*2, cy+r*0.7) end
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
    love.graphics.setLineWidth(2.4)
    love.graphics.line(cx-r*0.7, cy-r*0.7, cx+r*0.7, cy+r*0.7)
    love.graphics.line(cx-r*0.7, cy+r*0.7, cx+r*0.7, cy-r*0.7)
  end
  love.graphics.setLineWidth(1)
end

-- ============================================================
--  Corner cut tag (cyberpunk)
-- ============================================================
local function tag_poly(x, y, w, h, cut)
  return {
    x + cut,       y,
    x + w,         y,
    x + w,         y + h - cut,
    x + w - cut,   y + h,
    x,             y + h,
    x,             y + cut,
  }
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
  -- grid hint
  love.graphics.setColor(th.grid_faint[1], th.grid_faint[2], th.grid_faint[3], 0.06)
  for y=0,H,16 do for x=0,W,16 do
    if ((x+y)/16)%2==0 then love.graphics.rectangle("fill", x, y, 1, 1) end
  end end

  for i, it in ipairs(ITEMS) do
    local x = X0
    local y = Y0 + (i - 1) * (CARD_H + GAP)
    local focused = (i == sel)
    local col = it.colour

    -- Tag body (cut corner bottom-right)
    local poly = tag_poly(x, y, CARD_W, CARD_H, 10)

    -- fill
    love.graphics.setColor(focused and 0.075 or 0.028,
                           focused and 0.065 or 0.024,
                           focused and 0.05 or 0.02, 0.96)
    love.graphics.polygon("fill", poly)

    -- accent left bar
    love.graphics.setColor(col[1], col[2], col[3], focused and 1 or 0.7)
    love.graphics.rectangle("fill", x, y + 6, focused and 4 or 3, CARD_H - 12)

    -- border
    if focused then
      local pulse = 0.6 + 0.4*math.sin(t*5)
      love.graphics.setColor(col[1], col[2], col[3], 0.75 + pulse*0.25)
      love.graphics.setLineWidth(2)
    else
      love.graphics.setColor(col[1], col[2], col[3], 0.4)
      love.graphics.setLineWidth(1)
    end
    love.graphics.polygon("line", poly)
    love.graphics.setLineWidth(1)

    -- cat tag (top-left)
    love.graphics.setFont(A.font(A.FONT_MONO, 8))
    local catw = love.graphics.getFont():getWidth(it.cat) + 10
    love.graphics.setColor(col[1], col[2], col[3], focused and 0.22 or 0.12)
    love.graphics.rectangle("fill", x + 12, y + 5, catw, 12)
    love.graphics.setColor(col[1], col[2], col[3], focused and 1 or 0.7)
    love.graphics.rectangle("line", x + 12.5, y + 5.5, catw - 1, 11)
    love.graphics.print(it.cat, x + 16, y + 6)

    -- index number (top-right)
    love.graphics.setFont(A.font(A.FONT_MONO, 9))
    love.graphics.setColor(col[1], col[2], col[3], focused and 0.9 or 0.5)
    love.graphics.printf(string.format("%02d", i), 0, y + 6, X0 + CARD_W - 20, "right")

    -- icon
    draw_icon(it.shape, x + 34, y + CARD_H - 20, 11, col, focused and 1 or 0.8)

    -- title
    love.graphics.setFont(A.font(A.FONT_BODY_BOLD, focused and 15 or 13))
    love.graphics.setColor(focused and 1 or 0.85, focused and 1 or 0.85, focused and 1 or 0.85, 1)
    love.graphics.print(it.label, x + 54, y + 20)

    -- subtitle
    love.graphics.setFont(A.font(A.FONT_BODY, 9))
    love.graphics.setColor(th.text_dim[1], th.text_dim[2], th.text_dim[3], focused and 1 or 0.7)
    love.graphics.print(it.sub, x + 54, y + 40)

    -- bracket corner detail (bottom-left)
    love.graphics.setColor(col[1], col[2], col[3], focused and 0.85 or 0.4)
    love.graphics.setLineWidth(1.4)
    love.graphics.line(x + 6, y + CARD_H - 12, x + 6, y + CARD_H - 6)
    love.graphics.line(x + 6, y + CARD_H - 6, x + 12, y + CARD_H - 6)
    love.graphics.setLineWidth(1)
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
