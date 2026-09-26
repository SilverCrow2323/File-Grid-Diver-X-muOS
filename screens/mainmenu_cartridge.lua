-- mainmenu_cartridge.lua -- 8-bit arcade cabinet.
-- Big blinking PRESS START, score table, chunky cartridge cards.
local A     = require("core.assets")
local State = require("core.state")
local Input = require("core.input_map")
local Frame = require("ui.frame")
local D     = require("ui.draw")
local Modal = require("ui.modal")

local S = {}
local W, H = 640, 480

local YEL = {0.98, 0.80, 0.15}
local RED = {0.95, 0.25, 0.20}
local GRN = {0.40, 0.90, 0.35}
local CYA = {0.30, 0.85, 0.95}
local MAG = {0.95, 0.35, 0.75}
local function col(c, a) love.graphics.setColor(c[1], c[2], c[3], a or 1) end

local CARTS = {
  { label = "PLAY",       sub = "INSERT CARTRIDGE", colour = YEL, target = "filex_home",
    score = "1UP" },
  { label = "LEADERBOARD",sub = "HIGH SCORES",      colour = GRN, target = "log",
    score = "LOG" },
  { label = "SETTINGS",   sub = "OPTIONS MENU",     colour = CYA, target = "settings",
    score = "CFG" },
  { label = "MULTIPLAYER",sub = "LINK MODE",        colour = MAG, target = "plugins",
    score = "P2" },
}
local N = #CARTS
local POWER_IDX = N + 1  -- virtual slot

local sel = 1
local t = 0
local last_dt = 0.016

function S.enter() sel = 1; t = 0 end
function S.leave() end
function S.update(dt) t = t + dt; last_dt = dt end

local function move(d)
  sel = sel + d
  if sel < 1 then sel = N + 1 end
  if sel > N + 1 then sel = 1 end
  local ok, SFX = pcall(require, "core.audio")
  if ok and SFX.play then SFX.play("nav3") end
end

local function activate()
  local ok, SFX = pcall(require, "core.audio")
  if ok and SFX.play then SFX.play("enter") end
  if sel == POWER_IDX then
    Modal.show("POWER OFF", "Shut down File-GD X?",
      { accept_label = "POWER OFF", cancel_label = "CANCEL", accept_color = RED,
        on_accept = function() love.event.quit() end })
  else
    State.go(CARTS[sel].target)
  end
end

function S.pad(b)
  if Modal.is_open() then
    if b == Input.A then Modal.accept() elseif b == Input.B then Modal.cancel() end
    return
  end
  if b == Input.RIGHT or b == Input.DOWN then move(1)
  elseif b == Input.LEFT or b == Input.UP then move(-1)
  elseif b == Input.A then activate()
  elseif b == Input.B or b == Input.SELECT then
    Modal.show("POWER OFF", "Shut down File-GD X?",
      { accept_label = "POWER OFF", cancel_label = "CANCEL", accept_color = RED,
        on_accept = function() love.event.quit() end })
  end
end

function S.hat(d)
  if Modal.is_open() then return end
  if d == "right" or d == "down" then move(1)
  elseif d == "left" or d == "up" then move(-1) end
end

function S.key(k)
  if Modal.is_open() then
    if k == "return" then Modal.accept() elseif k == "escape" then Modal.cancel() end
    return
  end
  if k == "right" or k == "down" then move(1)
  elseif k == "left" or k == "up" then move(-1)
  elseif k == "return" or k == "space" then activate()
  elseif k == "escape" then S.pad(Input.B) end
end

-- chunky pixel corner
local function chunky_box(x, y, w, h, acc, foc)
  -- double outer black border
  col({0,0,0}, 1)
  love.graphics.rectangle("fill", x - 3, y - 3, w + 6, h + 6)
  col(acc, foc and 1 or 0.7)
  love.graphics.rectangle("fill", x - 2, y - 2, w + 4, h + 4)
  col({0.04, 0.03, 0.02}, 1)
  love.graphics.rectangle("fill", x, y, w, h)
  col(acc, foc and 0.95 or 0.35)
  love.graphics.setLineWidth(2)
  love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1)
  love.graphics.setLineWidth(1)
  -- corner pips
  col(acc, foc and 1 or 0.5)
  for _, p in ipairs({{x,y},{x+w-6,y},{x,y+h-6},{x+w-6,y+h-6}}) do
    love.graphics.rectangle("fill", p[1], p[2], 6, 6)
  end
end

local function draw_cart(x, y, w, h, cart, foc, idx)
  local acc = cart.colour
  chunky_box(x, y, w, h, acc, foc)

  -- top stripe with index
  col(acc, foc and 1 or 0.55)
  love.graphics.rectangle("fill", x + 4, y + 4, w - 8, 3)

  love.graphics.setFont(A.font(A.FONT_MONO, 9))
  col(acc, 0.75)
  love.graphics.print(string.format("#%02d", idx), x + 8, y + 10)
  love.graphics.printf(cart.score, x, y + 10, w - 8, "right")

  -- big label
  love.graphics.setFont(A.font(A.FONT_TITLE, foc and 17 or 15))
  col(foc and {1,1,1} or acc, 1)
  love.graphics.printf(cart.label, x + 4, y + 30, w - 8, "center")

  -- sub
  love.graphics.setFont(A.font(A.FONT_MONO, 8))
  col(acc, foc and 0.85 or 0.55)
  love.graphics.printf(cart.sub, x + 4, y + h - 18, w - 8, "center")

  -- blinking cursor if focused
  if foc and math.floor(t * 3) % 2 == 0 then
    col(acc, 1)
    love.graphics.rectangle("fill", x + w - 14, y + h - 26, 6, 10)
  end
end

local function draw_power(x, y, w, h, foc)
  chunky_box(x, y, w, h, RED, foc)
  col(RED, foc and 1 or 0.55)
  love.graphics.setLineWidth(3)
  local cx, cy = x + w/2, y + h/2 - 4
  love.graphics.circle("line", cx, cy, 14)
  love.graphics.line(cx, cy - 20, cx, cy - 6)
  love.graphics.setLineWidth(1)
  love.graphics.setFont(A.font(A.FONT_TITLE, 11))
  col(foc and {1,1,1} or RED, 1)
  love.graphics.printf("POWER OFF", x, y + h - 18, w, "center")
end

-- scanlines overlay (heavier for retro feel)
local function retro_scanlines()
  col({0,0,0}, 0.22)
  for y = 0, H, 3 do
    love.graphics.rectangle("fill", 0, y, W, 1)
  end
end

function S.draw()
  D.bg()
  col({0.02, 0.015, 0.025}, 1)
  love.graphics.rectangle("fill", 0, 0, W, H)

  -- starfield bg (simple)
  for i = 1, 60 do
    local sx = (i * 97) % W
    local sy = (i * 53) % (H - 120)
    local a = 0.15 + 0.5 * math.abs(math.sin(t * 1.5 + i * 0.4))
    col({0.9, 0.6, 0.3}, a)
    love.graphics.rectangle("fill", sx, sy, 1, 1)
  end

  -- TOP SCORE TABLE
  local ty = Frame.TOP_H + 6
  col({0,0,0}, 1)
  love.graphics.rectangle("fill", 12, ty, W - 24, 40)
  col(YEL, 0.9)
  love.graphics.rectangle("line", 12.5, ty + 0.5, W - 25, 39)
  love.graphics.setFont(A.font(A.FONT_MONO, 9))
  col(YEL, 0.95)
  love.graphics.print("HIGH SCORES", 20, ty + 6)
  love.graphics.setFont(A.font(A.FONT_TITLE, 12))
  col(CYA, 1)
  love.graphics.print("01  FGDX", 20, ty + 20)
  col(GRN, 1)
  love.graphics.print("02  USER", 150, ty + 20)
  col(RED, 1)
  love.graphics.print("03  GUEST", 280, ty + 20)
  col({1,1,1}, 0.5 + 0.5 * math.abs(math.sin(t * 2)))
  love.graphics.printf("INSERT COIN", 0, ty + 20, W - 20, "right")

  -- MAIN TITLE
  local title_y = ty + 52
  love.graphics.setFont(A.font(A.FONT_TITLE, 32))
  -- shadowed 3D title
  for dx = -2, 2, 2 do
    for dy = -2, 2, 2 do
      col({0,0,0}, 1)
      love.graphics.printf("FILE-GD X", dx, title_y + dy, W, "center")
    end
  end
  col(YEL, 1)
  love.graphics.printf("FILE-GD X", 0, title_y, W, "center")
  love.graphics.setFont(A.font(A.FONT_MONO, 9))
  col(MAG, 0.9)
  love.graphics.printf("◄  SYSTEM ARCADE EDITION  ►", 0, title_y + 38, W, "center")

  -- CARTRIDGE GRID (2x2 + power)
  local gx, gy = 24, title_y + 70
  local gap = 8
  local cols = 2
  local cw = (W - gx*2 - gap) / cols
  local ch = 84
  for i = 1, N do
    local row = math.floor((i-1) / cols)
    local col_ = (i-1) % cols
    local x = gx + col_ * (cw + gap)
    local y = gy + row * (ch + gap)
    draw_cart(x, y, cw, ch, CARTS[i], sel == i, i)
  end
  -- power button below
  local py = gy + 2 * (ch + gap)
  draw_power(gx, py, W - gx*2, 48, sel == POWER_IDX)

  -- BLINKING PRESS START (bottom)
  if math.floor(t * 2) % 2 == 0 then
    love.graphics.setFont(A.font(A.FONT_TITLE, 11))
    col({1,1,1}, 0.9)
    love.graphics.printf("PRESS  A  TO  START", 0, H - Frame.BOTTOM_H - 26, W, "center")
  end

  Frame.draw_top("FGD", "mainmenu")
  Frame.draw_bottom({
    { key = "dpad", label = "Select" },
    { key = "a",    label = "Start"  },
    { key = "l2",   label = "View"   },
    { key = "b",    label = "Quit"   },
  })
  Modal.draw()
  retro_scanlines()
  D.vignette(W, H, 0.7)
end

return S
