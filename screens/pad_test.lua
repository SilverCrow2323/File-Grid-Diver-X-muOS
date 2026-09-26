-- screens/pad_test.lua — live gamepad visualizer.
--
-- Shows the physical layout of a standard Anbernic/muOS pad.
-- Buttons highlight when pressed, sticks show live position,
-- triggers show raw value. Answers the "is my d-pad broken or is
-- it software" question without leaving the app.
local A     = require("core.assets")
local State = require("core.state")
local Input = require("core.input_map")
local Frame = require("ui.frame")
local D     = require("ui.draw")

local S = {}
S.reserve_select = true
local W, H = 640, 480

-- Button layout (grid units inside the pad rectangle)
-- x,y are normalized 0..1 inside the pad body area.
local BUTTONS = {
  { key = "Y",        id = "y",      x = 0.30, y = 0.22, r = 13, col = {0.95,0.80,0.20} },
  { key = "X",        id = "x",      x = 0.50, y = 0.22, r = 13, col = {0.30,0.75,0.40} },
  { key = "B",        id = "b",      x = 0.70, y = 0.22, r = 13, col = {0.30,0.55,0.95} },
  { key = "A",        id = "a",      x = 0.50, y = 0.38, r = 13, col = {0.90,0.30,0.30} },

  { key = "L1",       id = "l1",     x = 0.10, y = 0.10, r = 16, col = {0.55,0.55,0.60} },
  { key = "R1",       id = "r1",     x = 0.90, y = 0.10, r = 16, col = {0.55,0.55,0.60} },
  { key = "L2",       id = "l2",     x = 0.10, y = 0.24, r = 16, col = {0.45,0.45,0.55} },
  { key = "R2",       id = "r2",     x = 0.90, y = 0.24, r = 16, col = {0.45,0.45,0.55} },

  { key = "SELECT",   id = "select", x = 0.35, y = 0.55, r = 11, col = {0.35,0.40,0.55} },
  { key = "START",    id = "start",  x = 0.65, y = 0.55, r = 11, col = {0.35,0.40,0.55} },

  { key = "UP",       id = "up",     x = 0.20, y = 0.68, r = 11, col = {0.60,0.60,0.70} },
  { key = "DOWN",     id = "down",   x = 0.20, y = 0.88, r = 11, col = {0.60,0.60,0.70} },
  { key = "LEFT",     id = "left",   x = 0.08, y = 0.78, r = 11, col = {0.60,0.60,0.70} },
  { key = "RIGHT",    id = "right",  x = 0.32, y = 0.78, r = 11, col = {0.60,0.60,0.70} },
}

-- track pressed
local pressed = {}
local last_event = nil
local event_log = {}
local stick = { x = 0, y = 0 }
local stick_visible = false

local function log_event(kind, name)
  last_event = string.format("%s  %s", kind:upper(), name)
  event_log[#event_log + 1] = os.date("%H:%M:%S ") .. last_event
  if #event_log > 12 then table.remove(event_log, 1) end
end

local function mark(id, state)
  if state then pressed[id] = os.time()
  else pressed[id] = nil end
end

-- ── Lifecycle ───────────────────────────────────────────────
function S.enter()
  pressed = {}
  event_log = {}
  stick = { x = 0, y = 0 }
  stick_visible = false
end
function S.leave() end
function S.update(dt)
  -- Prune stale presses (safety net in case releases are missed)
  local now = os.time()
  for id, t in pairs(pressed) do
    if now - t > 3 then pressed[id] = nil end
  end
  -- Try to read analog stick directly, if a joystick is connected
  if love.joystick then
    local js = love.joystick.getJoysticks()[1]
    if js then
      stick_visible = true
      local okx, x = pcall(js.getAxis, js, 1)
      local oky, y = pcall(js.getAxis, js, 2)
      if okx and oky then stick.x = x or 0; stick.y = y or 0 end
    end
  end
end

function S.pad(b)
  -- b is the SEMANTIC name (e.g. "a", "b", "dpup"...)
  if     b == Input.A then mark("a", true)
  elseif b == Input.B then mark("b", true)
  elseif b == Input.X then mark("x", true)
  elseif b == Input.Y then mark("y", true)
  elseif b == Input.L1 then mark("l1", true)
  elseif b == Input.R1 then mark("r1", true)
  elseif b == Input.L2 then mark("l2", true)
  elseif b == Input.R2 then mark("r2", true)
  elseif b == Input.START then mark("start", true)
  elseif b == Input.SELECT then mark("select", true)
  elseif b == Input.UP then mark("up", true)
  elseif b == Input.DOWN then mark("down", true)
  elseif b == Input.LEFT then mark("left", true)
  elseif b == Input.RIGHT then mark("right", true)
  end
  if b then log_event("btn", tostring(b)) end
  -- Exit on B (single tap) but only after a short delay so the user
  -- sees it register; use SELECT long as alternative.
  if b == Input.SELECT then State.back() end
end

function S.hat(dir)
  local m = { up="up", down="down", left="left", right="right" }
  local id = m[dir]
  if id then mark(id, true); log_event("hat", dir) end
end

-- raw button press/release overrides, called directly from main.lua
-- (main.lua only forwards presses; we treat them as taps of ~0.4 s)
function S.raw_button(idx)
  log_event("raw", "b" .. tostring(idx))
end

function S.key(k)
  local map = {
    up = "up", down = "down", left = "left", right = "right",
    a = "a", b = "b", x = "x", y = "y",
    space = "a", lshift = "l1", rshift = "r1",
    lctrl = "l2", rctrl = "r2",
  }
  local id = map[k] or map[k:lower()]
  if id then mark(id, true); log_event("key", k) end
  if k == "escape" or k == "backspace" then State.back() end
end

-- ── Draw ────────────────────────────────────────────────────
local function draw_btn(cx, cy, r, col, on, label)
  -- shadow
  love.graphics.setColor(0, 0, 0, 0.6)
  love.graphics.circle("fill", cx, cy + 2, r)
  -- body
  local cc = on and {1,1,1} or col
  love.graphics.setColor(cc[1]*0.35, cc[2]*0.35, cc[3]*0.35, 1)
  love.graphics.circle("fill", cx, cy, r)
  love.graphics.setColor(cc[1], cc[2], cc[3], 1)
  love.graphics.circle("fill", cx, cy, r - 1.5)
  -- ring
  love.graphics.setColor(0,0,0,0.85)
  love.graphics.setLineWidth(1.5)
  love.graphics.circle("line", cx, cy, r - 0.5)
  love.graphics.setLineWidth(1)
  -- label
  love.graphics.setColor(1,1,1)
  local f = A.font(A.FONT_BODY_BOLD, math.floor(r * 0.9))
  love.graphics.setFont(f)
  local w = f:getWidth(label)
  love.graphics.print(label, cx - w/2, cy - f:getHeight()/2)
end

function S.draw()
  local th = State.theme
  D.bg()

  -- pad body
  local px = 60
  local py = Frame.TOP_H + 30
  local pw = W - 120
  local ph = H - py - Frame.BOTTOM_H - 12

  love.graphics.setColor(0.05, 0.045, 0.04, 1)
  love.graphics.rectangle("fill", px, py, pw, ph, 12, 12)
  love.graphics.setColor(th.amber_lo[1], th.amber_lo[2], th.amber_lo[3], 0.7)
  love.graphics.setLineWidth(2)
  love.graphics.rectangle("line", px + 0.5, py + 0.5, pw - 1, ph - 1, 12, 12)
  love.graphics.setLineWidth(1)

  -- Buttons
  for _, b in ipairs(BUTTONS) do
    local bx = px + pw * b.x
    local by = py + ph * b.y
    draw_btn(bx, by, b.r, b.col, pressed[b.id] ~= nil, b.key)
  end

  -- Analog stick (left side)
  local scx = px + pw * 0.78
  local scy = py + ph * 0.75
  local sr  = 30
  love.graphics.setColor(0.02, 0.02, 0.02, 1)
  love.graphics.circle("fill", scx, scy, sr)
  love.graphics.setColor(th.amber_lo[1], th.amber_lo[2], th.amber_lo[3], 0.8)
  love.graphics.circle("line", scx, scy, sr)
  love.graphics.circle("line", scx, scy, sr * 0.5)
  -- dot
  local dx = scx + stick.x * (sr - 6)
  local dy = scy + stick.y * (sr - 6)
  love.graphics.setColor(th.amber_hi)
  love.graphics.circle("fill", dx, dy, 8)
  love.graphics.setColor(th.cyan_hi)
  love.graphics.circle("line", dx, dy, 8)

  -- Right column: status + event log
  local rcx = W - 195
  local rcy = Frame.TOP_H + 30
  local rcw = 185
  local rch = H - rcy - Frame.BOTTOM_H - 12

  love.graphics.setColor(0.03, 0.026, 0.022, 1)
  love.graphics.rectangle("fill", rcx, rcy, rcw, rch, 4, 4)
  love.graphics.setColor(th.amber_lo[1], th.amber_lo[2], th.amber_lo[3], 0.6)
  love.graphics.rectangle("line", rcx + 0.5, rcy + 0.5, rcw - 1, rch - 1, 4, 4)

  love.graphics.setColor(th.amber_hi)
  love.graphics.setFont(A.font(A.FONT_BODY_BOLD, 13))
  love.graphics.print("EVENT LOG", rcx + 8, rcy + 6)

  love.graphics.setFont(A.font(A.FONT_MONO, 12))
  local y = rcy + 24
  for i = math.max(1, #event_log - 14), #event_log do
    local line = event_log[i]
    if line then
      love.graphics.setColor(th.text)
      love.graphics.print(line, rcx + 8, y)
      y = y + 12
    end
  end

  -- Raw info
  if love.joystick then
    local js = love.joystick.getJoysticks()[1]
    love.graphics.setFont(A.font(A.FONT_MONO, 12))
    love.graphics.setColor(th.text_dim)
    love.graphics.print(js and ("joystick: " .. tostring(js:getName()))
      or "no joystick connected",
      rcx + 8, rcy + rch - 18)
  end

  -- Banner
  love.graphics.setColor(th.text_dim)
  love.graphics.setFont(A.font(A.FONT_BODY, 12))
  love.graphics.printf(
    "Press any button. If nothing lights up here, the pad may be broken.",
    0, H - Frame.BOTTOM_H - 20, W, "center")

  Frame.draw_top("FGD", "pad_test")
  Frame.draw_bottom({
    { key = "ANY",   label = "Test buttons" },
    { key = "SELECT",label = "Back" },
    { key = "ESC",   label = "Quit" },
  })
  D.scanlines(W, H, 0.06)
end

return S
