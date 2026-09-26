-- mainmenu_marquee.lua -- cinematic. 5 acts as horizontal bands.
local A     = require("core.assets")
local State = require("core.state")
local Input = require("core.input_map")
local Frame = require("ui.frame")
local D     = require("ui.draw")
local Modal = require("ui.modal")

local S = {}
local W, H = 640, 480
local GOLD = {0.92, 0.78, 0.42}
local RED  = {0.95, 0.30, 0.25}
local function col(c, a) love.graphics.setColor(c[1], c[2], c[3], a or 1) end

local ACTS = {
  { roman = "I",   title = "THE FILES",     sub = "browse the machine",
    colour = {0.94, 0.66, 0.35}, target = "filex_home" },
  { roman = "II",  title = "THE MACHINE",   sub = "a study in silicon",
    colour = {0.48, 0.80, 0.90}, target = "device" },
  { roman = "III", title = "THE TOOLS",     sub = "extensions of will",
    colour = {0.70, 0.55, 0.92}, target = "plugins" },
  { roman = "IV",  title = "THE CONTROLS",  sub = "master the interface",
    colour = {0.55, 0.85, 0.45}, target = "settings" },
  { roman = "FIN", title = "CURTAIN CALL",  sub = "take your leave",
    colour = {0.95, 0.30, 0.25}, target = nil },
}
local N = #ACTS

local sel = 1
local t = 0
local transitions = {}

function S.enter() sel = 1; t = 0 end
function S.leave() end
function S.update(dt)
  t = t + dt
  for i = #transitions, 1, -1 do
    transitions[i].age = transitions[i].age + dt
    if transitions[i].age > 0.4 then table.remove(transitions, i) end
  end
end

local function move(d)
  sel = sel + d
  if sel < 1 then sel = N end
  if sel > N then sel = 1 end
  transitions[#transitions+1] = { idx = sel, age = 0 }
  local ok, SFX = pcall(require, "core.audio")
  if ok and SFX.play then SFX.play("toggle_badge") end
end

local function activate()
  local a = ACTS[sel]
  if not a then return end
  local ok, SFX = pcall(require, "core.audio")
  if ok and SFX.play then SFX.play("enter") end
  if a.target then
    State.go(a.target)
  else
    Modal.show("Curtain Call",
      "The show is over.\n\nLeave the theatre?",
      { accept_label = "EXIT", cancel_label = "STAY", accept_color = RED,
        on_accept = function() love.event.quit() end })
  end
end

function S.pad(b)
  if Modal.is_open() then
    if b == Input.A then Modal.accept() elseif b == Input.B then Modal.cancel() end
    return
  end
  if b == Input.UP or b == Input.LEFT then move(-1)
  elseif b == Input.DOWN or b == Input.RIGHT then move(1)
  elseif b == Input.A then activate()
  elseif b == Input.B or b == Input.SELECT then
    Modal.show("Curtain Call",
      "The show is over.\n\nLeave the theatre?",
      { accept_label = "EXIT", cancel_label = "STAY", accept_color = RED,
        on_accept = function() love.event.quit() end })
  end
end

function S.hat(d)
  if Modal.is_open() then return end
  if d == "up" or d == "left" then move(-1)
  elseif d == "down" or d == "right" then move(1) end
end

function S.key(k)
  if Modal.is_open() then
    if k == "return" then Modal.accept() elseif k == "escape" then Modal.cancel() end
    return
  end
  if k == "up" or k == "left" then move(-1)
  elseif k == "down" or k == "right" then move(1)
  elseif k == "return" or k == "space" then activate()
  elseif k == "escape" then S.pad(Input.B) end
end

-- film grain
local function draw_grain(alpha)
  for i = 1, 40 do
    local gx = (i * 113 + t * 40) % W
    local gy = (i * 71 + t * 30) % H
    col({1,1,1}, alpha * 0.15 * math.abs(math.sin(t*8 + i)))
    love.graphics.rectangle("fill", gx, gy, 1, 1)
  end
end

-- vignette with fade-to-black at top and bottom (cinema bars)
local function draw_cinema_bars()
  col({0,0,0}, 0.85)
  love.graphics.rectangle("fill", 0, Frame.TOP_H, W, 14)
  love.graphics.rectangle("fill", 0, H - Frame.BOTTOM_H - 14, W, 14)
  col(GOLD, 0.25)
  love.graphics.rectangle("fill", 0, Frame.TOP_H + 14, W, 1)
  love.graphics.rectangle("fill", 0, H - Frame.BOTTOM_H - 15, W, 1)
end

local function draw_band(x, y, w, h, a, foc)
  local acc = a.colour
  local p = 0
  if foc then
    -- fade-in transition
    for _, tr in ipairs(transitions) do
      if tr.idx == sel then
        p = math.min(1, tr.age / 0.4)
        p = 1 - (1 - p) * (1 - p) * (1 - p)
      end
    end
    p = math.max(p, 1)
  end

  if foc then
    -- spotlight gradient
    D.glow(x + w/2, y + h/2, w * 0.9, acc, 0.4)
    col({acc[1]*0.16, acc[2]*0.16, acc[3]*0.16}, 0.98)
    love.graphics.rectangle("fill", x, y, w, h, 0, 0)
    col(acc, 0.95); love.graphics.setLineWidth(1.6)
    love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1)
    love.graphics.setLineWidth(1)
    -- Roman numeral left, glowing
    col(acc, 0.55 + 0.3 * math.sin(t * 3))
    love.graphics.rectangle("fill", x, y, 3, h)
    -- corner ticks
    D.corner_ticks(x + 8, y + 8, w - 16, h - 16, 12, acc, 0.95)
  else
    col({0.024, 0.022, 0.030}, 0.92)
    love.graphics.rectangle("fill", x, y, w, h, 0, 0)
    col(acc, 0.30)
    love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1)
  end

  -- Roman numeral
  love.graphics.setFont(A.font(A.FONT_TITLE, foc and 32 or 26))
  col(acc, foc and 1 or 0.55)
  love.graphics.print(a.roman, x + 24, y + (h - love.graphics.getFont():getHeight()) / 2)

  -- vertical separator
  col(acc, foc and 0.6 or 0.2)
  love.graphics.rectangle("fill", x + 84, y + 10, 1, h - 20)

  -- Title
  love.graphics.setFont(A.font(A.FONT_TITLE, foc and 26 or 22))
  col(foc and {1,1,1} or acc, 1)
  love.graphics.print(a.title, x + 100, y + (h - love.graphics.getFont():getHeight()) / 2 - 6)

  -- Sub
  love.graphics.setFont(A.font(A.FONT_MONO, 9))
  col(acc, foc and 0.85 or 0.55)
  love.graphics.print(a.sub, x + 100, y + (h - love.graphics.getFont():getHeight()) / 2 + 22)

  -- Index right
  love.graphics.setFont(A.font(A.FONT_MONO, 10))
  col(acc, foc and 0.9 or 0.5)
  love.graphics.printf(string.format("%02d / %02d", sel, N),
    x, y + (h - 10) / 2, w - 20, "right")

  -- if focused, subtle marquee light dots along right edge
  if foc then
    local dot_on = math.floor((t * 4) % N)
    for i = 0, N-1 do
      local dy = y + 8 + i * ((h - 16) / (N - 1))
      col(acc, i == dot_on and 1 or 0.25)
      love.graphics.circle("fill", x + w - 8, dy, i == dot_on and 2.5 or 1.5)
    end
  end
end

function S.draw()
  D.bg()
  col({0.018, 0.014, 0.020}, 1)
  love.graphics.rectangle("fill", 0, 0, W, H)

  -- Title strip
  love.graphics.setFont(A.font(A.FONT_TITLE, 22))
  col(GOLD, 0.85)
  love.graphics.printf("FILE-GD X", 0, Frame.TOP_H + 14, W, "center")
  love.graphics.setFont(A.font(A.FONT_MONO, 10))
  col(GOLD, 0.55)
  love.graphics.printf("·  A FILM IN FIVE ACTS  ·", 0, Frame.TOP_H + 42, W, "center")

  -- decorative rule
  col(GOLD, 0.35)
  love.graphics.rectangle("fill", W/2 - 120, Frame.TOP_H + 60, 240, 1)
  col(GOLD, 0.55)
  love.graphics.rectangle("fill", W/2 - 3, Frame.TOP_H + 57, 6, 6, 3, 3)

  -- Bands
  local x = 24
  local y0 = Frame.TOP_H + 78
  local w = W - 48
  local h = 56
  local gap = 4
  for i, a in ipairs(ACTS) do
    local y = y0 + (i - 1) * (h + gap)
    draw_band(x, y, w, h, a, sel == i)
  end

  -- Footer credit
  love.graphics.setFont(A.font(A.FONT_MONO, 9))
  col(GOLD, 0.4)
  love.graphics.printf("SPDW FACTORY  ·  MMXXVI",
    0, H - Frame.BOTTOM_H - 20, W, "center")

  draw_cinema_bars()
  draw_grain(1)

  Frame.draw_top("FGD", "mainmenu")
  Frame.draw_bottom({
    { key = "up",  label = "Act"   },
    { key = "a",   label = "Enter" },
    { key = "l2",  label = "View"  },
    { key = "b",   label = "Exit"  },
  })
  Modal.draw()
  D.scanlines(W, H, 0.04)
  D.vignette(W, H, 0.65)
end

return S
