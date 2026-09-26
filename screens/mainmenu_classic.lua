-- screens/mainmenu.lua -- File-GD X main menu.
-- No intro sequence (that's handled by boot.lua).
-- Vertical list of 5 cards. Immediate input handling.

local A     = require("core.assets")
local State = require("core.state")
local Input = require("core.input_map")
local D     = require("ui.draw")
local Frame = require("ui.frame")

local S = {}
local W, H = 640, 480

-- Layout
local MENU_TOP   = 110
local MENU_LEFT  = 30
local MENU_RIGHT = 30
local CARD_H     = 62
local CARD_GAP   = 8
local ICON_R     = 22

local ITEMS = {
  { label = "FILE XPLORER", screen = "filex_home",
    colour = {0.94, 0.66, 0.35}, shape = "folder",
    sub    = "browse and manage files" },
  { label = "SYSTEM",       screen = "device",
    colour = {0.48, 0.80, 0.90}, shape = "waves",
    sub    = "device stats and network" },
  { label = "PLUGINS", screen = "plugins",
    colour = {0.70, 0.55, 0.92}, shape = "plug",
    sub    = "preferences and about" },
  { label = "SETTINGS",     screen = "settings",
    colour = {0.55, 0.72, 0.50}, shape = "gear",
    sub    = "extend File-GD X" },
  { label = "EXIT",         screen = nil,
    colour = {0.90, 0.22, 0.20}, shape = "power",
    sub    = "terminate session" },
}
local N = #ITEMS

S.sel     = 1
S.hold    = 0
S.exiting = nil
S.t       = 0

function S.enter()
  S.sel     = 1
  S.hold    = 0
  S.exiting = nil
  S.t       = 0
end
function S.leave() end

function S.update(dt)
  S.t = S.t + dt
  if S.hold > 0 then
    S.hold = math.max(0, S.hold - dt)
  end
  if S.exiting then
    S.exiting.t = S.exiting.t + dt
    if S.exiting.t > 0.42 then
      local target = S.exiting.target
      local is_exit = S.exiting.item and (S.exiting.item.screen == nil)
      S.exiting = nil
      if is_exit then
        love.event.quit()
      else
        State.go(target)
      end
    end
  end
end

local function move(dir)
  if S.exiting then return end
  if S.hold > 0 then return end
  S.hold = 0.06
  local i = S.sel + dir
  if i < 1 then i = N end
  if i > N then i = 1 end
  S.sel = i
  local ok, SFX = pcall(require, "core.audio")
  if ok then SFX.play("nav") end
end

local function activate()
  if S.exiting then return end
  local it = ITEMS[S.sel]
  if not it then return end
  S.exiting = { t = 0, target = it.screen, item = it }
  local ok, SFX = pcall(require, "core.audio")
  if ok then SFX.play("enter") end
end

function S.pad(b)
  if S.exiting then return end
  if     b == Input.UP    then move(-1)
  elseif b == Input.DOWN  then move( 1)
  elseif b == Input.LEFT  then move(-1)
  elseif b == Input.RIGHT then move( 1)
  elseif b == Input.A     then activate()
  elseif b == Input.B or b == Input.SELECT then
    -- back from main menu = quit
    S.exiting = { t = 0, target = nil, item = { screen = nil } }
  end
end

function S.hat(dir)
  if S.exiting then return end
  if     dir == "up"    or dir == "left"  then move(-1)
  elseif dir == "down"  or dir == "right" then move( 1) end
end

function S.key(k)
  if S.exiting then return end
  if     k == "up"    or k == "left"  then move(-1)
  elseif k == "down"  or k == "right" then move( 1)
  elseif k == "return" or k == "space" then activate()
  elseif k == "escape" then
    S.exiting = { t = 0, target = nil, item = { screen = nil } }
  end
end

-- Icons ------------------------------------------------------
local function draw_item_icon(shape, cx, cy, r, colour, alpha, t)
  -- Try to use the image asset for this shape
  local img_map = {}
  local img = A.image(img_map[shape])
  if img then
    local iw, ih = img:getDimensions()
    local target_h = r * 2.2
    local sc = target_h / ih
    local dw = iw * sc
    love.graphics.setColor(1, 1, 1, alpha or 1)
    love.graphics.draw(img, cx - dw/2, cy - target_h/2, 0, sc, sc)
    love.graphics.setColor(1, 1, 1, 1)
    return
  end
  -- Fallback: disegno originale
  love.graphics.setColor(colour[1], colour[2], colour[3], alpha or 1)
  love.graphics.setLineWidth(2)
  if shape == "folder" then
    love.graphics.rectangle("fill", cx - r*0.9, cy - r*0.6, r*0.7, r*0.4)
    love.graphics.rectangle("line", cx - r*0.9, cy - r*0.3, r*1.8, r*1.3)
  elseif shape == "waves" then
    for k = 1, 3 do
      love.graphics.arc("line", "open", cx, cy + r*0.6,
        r * (0.35 + k * 0.22), -math.pi * 0.85, -math.pi * 0.15)
    end
  elseif shape == "gear" then
    for i = 0, 7 do
      local ang = i * math.pi / 4 + t * 0.6
      love.graphics.line(cx + math.cos(ang)*r*0.6, cy + math.sin(ang)*r*0.6,
                         cx + math.cos(ang)*r*0.95, cy + math.sin(ang)*r*0.95)
    end
    love.graphics.circle("line", cx, cy, r * 0.62)
  elseif shape == "plug" then
    love.graphics.rectangle("line", cx - r*0.7, cy - r*0.2, r*1.4, r*0.9)
    love.graphics.line(cx - r*0.35, cy - r*0.2, cx - r*0.35, cy - r*0.85)
    love.graphics.line(cx + r*0.35, cy - r*0.2, cx + r*0.35, cy - r*0.85)
  elseif shape == "power" then
    love.graphics.circle("line", cx, cy, r * 0.75)
    love.graphics.line(cx, cy - r * 0.85, cx, cy - r * 0.2)
  end
  love.graphics.setLineWidth(1)
end

-- Background -------------------------------------------------
local function draw_bg_dots()
  local th = State.theme
  love.graphics.setColor(th.grid_faint[1], th.grid_faint[2], th.grid_faint[3], 0.10)
  for y = 0, H, 20 do
    for x = 0, W, 20 do
      love.graphics.rectangle("fill", x, y, 1, 1)
    end
  end
end

-- Title ------------------------------------------------------
local function draw_title()
  local th = State.theme
  local title_img = A.image("assets/images/titles/title2.png")
  if title_img then
    local iw, ih = title_img:getDimensions()
    local target_h = 70
    local sc = target_h / ih
    local dw = iw * sc
    local cx = W / 2
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(title_img, cx - dw/2, 25, 0, sc, sc)
    love.graphics.setColor(1, 1, 1, 1)
  else
    -- fallback testo
    local file_font = A.font(A.FONT_TITLE, 30)
    local grid_font = A.font(A.FONT_TITLE_ALT, 30)
    local w1 = file_font:getWidth("FILE ")
    local w2 = grid_font:getWidth("GRID-DIVER")
    local total = w1 + w2
    local x0 = W/2 - total/2 - 10
    love.graphics.setFont(file_font)
    love.graphics.setColor(1,1,1,1)
    love.graphics.print("FILE ", x0, 50)
    love.graphics.setFont(grid_font)
    love.graphics.print("GRID-DIVER", x0 + w1, 50)
  end
end

-- Cards ------------------------------------------------------
local function draw_card(i, it)
  local th = State.theme
  local focused = (i == S.sel) and (S.exiting == nil)

  local x = MENU_LEFT
  local y = MENU_TOP + (i - 1) * (CARD_H + CARD_GAP)
  local w = W - MENU_LEFT - MENU_RIGHT
  local h = CARD_H

  -- Focus scale
  local sc = focused and 1.03 or 1.0
  local w_scaled = w * sc
  local x_adj = x - (w_scaled - w) / 2

  -- Shadow
  love.graphics.setColor(0, 0, 0, 0.35)
  love.graphics.rectangle("fill", x_adj + 2, y + 3, w_scaled, h, 5, 5)

  -- Card body
  if focused then
    love.graphics.setColor(0.10, 0.09, 0.07, 0.98)
  else
    love.graphics.setColor(0.035, 0.030, 0.024, 0.92)
  end
  love.graphics.rectangle("fill", x_adj, y, w_scaled, h, 5, 5)

  -- Left colour stripe
  local stripe_w = focused and 8 or 4
  love.graphics.setColor(it.colour[1], it.colour[2], it.colour[3],
    focused and 1 or 0.7)
  love.graphics.rectangle("fill", x_adj, y, stripe_w, h, 5, 5)
  love.graphics.rectangle("fill", x_adj + stripe_w - 4, y, 4, h)

  -- Border
  if focused then
    local pulse = 0.6 + 0.4 * math.sin(S.t * 4)
    love.graphics.setColor(it.colour[1], it.colour[2], it.colour[3],
      0.7 + pulse * 0.3)
    love.graphics.setLineWidth(2)
  else
    love.graphics.setColor(it.colour[1] * 0.5, it.colour[2] * 0.5,
      it.colour[3] * 0.5, 0.6)
    love.graphics.setLineWidth(1)
  end
  love.graphics.rectangle("line", x_adj + 0.5, y + 0.5,
    w_scaled - 1, h - 1, 5, 5)
  love.graphics.setLineWidth(1)

  -- Icon (image asset preferred, no circle background needed)
  local icx = x_adj + stripe_w + 32
  local icy = y + h / 2
  draw_item_icon(it.shape, icx, icy, ICON_R,
    it.colour, focused and 1 or 0.85, S.t)

  -- Label
  local lx = icx + ICON_R + 16
  local ly = y + 12
  local lf = A.font(A.FONT_BODY_BOLD, focused and 17 or 15)
  love.graphics.setFont(lf)
  if focused then
    love.graphics.setColor(1, 1, 1, 1)
  else
    love.graphics.setColor(th.text, 0.9)
  end
  love.graphics.print(it.label, lx, ly)

  -- Sub
  local sf = A.font(A.FONT_BODY, 11)
  love.graphics.setFont(sf)
  love.graphics.setColor(th.text_dim, 0.85)
  love.graphics.print(it.sub, lx, ly + 24)

  -- Right: tag + chevron
  local rx = x_adj + w_scaled - 22
  local ry = y + h / 2

  love.graphics.setFont(A.font(A.FONT_MONO, 10))
  love.graphics.setColor(it.colour[1], it.colour[2], it.colour[3],
    focused and 1 or 0.6)
  love.graphics.printf(string.format("%02d", i),
    x_adj + w_scaled - 60, y + 6, 40, "right")

  if focused then
    local pulse = 0.5 + 0.5 * math.sin(S.t * 5)
    love.graphics.setColor(it.colour[1], it.colour[2], it.colour[3],
      0.6 + pulse * 0.4)
    love.graphics.setLineWidth(2)
  else
    love.graphics.setColor(it.colour[1], it.colour[2], it.colour[3], 0.35)
    love.graphics.setLineWidth(1.4)
  end
  local arrow_off = focused and (2 + math.sin(S.t * 5) * 2) or 0
  love.graphics.line(rx - 6 + arrow_off, ry - 6,
                     rx + arrow_off,     ry,
                     rx - 6 + arrow_off, ry + 6)
  love.graphics.setLineWidth(1)

  -- Focus corner ticks
  if focused then
    D.corner_ticks(x_adj + 4, y + 4, w_scaled - 8, h - 8,
      8, it.colour, 0.85)
  end
end

-- Exit overlay -----------------------------------------------
local function draw_exit()
  if not S.exiting then return end
  local p  = math.min(1, S.exiting.t / 0.42)
  local it = S.exiting.item

  love.graphics.setColor(0, 0, 0, p * 0.85)
  love.graphics.rectangle("fill", 0, 0, W, H)

  local cx, cy = W / 2, H / 2
  local r = 48 * (0.6 + 0.4 * p)

  if it and it.colour then
    D.glow(cx, cy, 120 * p, it.colour, 0.9 * p)
    love.graphics.setColor(0.10, 0.09, 0.07, p)
    love.graphics.circle("fill", cx, cy, r)
    if it.shape then
      draw_item_icon(it.shape, cx, cy, r * 0.55, it.colour, p, S.t)
    end
    love.graphics.setFont(A.font(A.FONT_TITLE, 26))
    love.graphics.setColor(1, 1, 1, p)
    local label = it.label or ""
    local lw = love.graphics.getFont():getWidth(label)
    love.graphics.print(label, cx - lw / 2, cy + r + 22)
  end
end

-- Main draw --------------------------------------------------
function S.draw()
  local th = State.theme
  D.bg()
  draw_bg_dots()
  draw_title()

  for i, it in ipairs(ITEMS) do
    draw_card(i, it)
  end

  -- status line bottom-left
  love.graphics.setFont(A.font(A.FONT_MONO, 10))
  love.graphics.setColor(th.text_dark, 0.9)
  love.graphics.print("SPDW FACTORY", 20, H - Frame.BOTTOM_H - 20)

  Frame.draw_top("FGD", "mainmenu")
  Frame.draw_bottom({
    { key = "up/dn", label = "Navigate" },
    { key = "a",     label = "Enter"    },
    { key = "b",     label = "Quit"     },
  })

  D.scanlines(W, H, 0.06)
  D.vignette(W, H, 0.55)

  draw_exit()
end

return S
