-- mainmenu_hud.lua -- tactical operations HUD.
-- List of ops with codes, crosshair, telemetry, blinking REC.
local A     = require("core.assets")
local State = require("core.state")
local Input = require("core.input_map")
local Frame = require("ui.frame")
local D     = require("ui.draw")
local Modal = require("ui.modal")

local S = {}
local W, H = 640, 480
local GRN = {0.55, 0.95, 0.55}
local AMB = {0.98, 0.72, 0.30}
local RED = {1.00, 0.30, 0.25}
local CYA = {0.40, 0.90, 0.95}
local function col(c, a) love.graphics.setColor(c[1], c[2], c[3], a or 1) end

local OPS = {
  { code = "OP://SCAN-FS",   label = "FILE EXPLORER", sub = "mount · traverse · retrieve",
    colour = AMB, target = "filex_home" },
  { code = "OP://TELEMETRY", label = "SYSTEM CORE",   sub = "cpu · mem · thermal · net",
    colour = CYA, target = "device" },
  { code = "OP://STORAGE",   label = "VOLUME CTRL",   sub = "analysis · cleanup · dupes",
    colour = GRN, target = "storage" },
  { code = "OP://PAYLOAD",   label = "MODULES",       sub = "install · launch · manage",
    colour = {0.70, 0.55, 0.92}, target = "plugins" },
  { code = "OP://CALIBRATE", label = "PROTOCOLS",     sub = "interface · input · display",
    colour = {0.55, 0.85, 0.45}, target = "settings" },
  { code = "OP://ABORT",     label = "TERMINATE",     sub = "end session",
    colour = RED, target = nil },
}
local N = #OPS

local sel = 1
local t = 0

function S.enter() sel = 1; t = 0 end
function S.leave() end
function S.update(dt) t = t + dt end

local function move(d)
  sel = sel + d
  if sel < 1 then sel = N end
  if sel > N then sel = 1 end
  local ok, SFX = pcall(require, "core.audio")
  if ok and SFX.play then SFX.play("nav2") end
end

local function activate()
  local op = OPS[sel]
  local ok, SFX = pcall(require, "core.audio")
  if ok and SFX.play then SFX.play("enter") end
  if op.target then
    State.go(op.target)
  else
    Modal.show("TERMINATE SESSION",
      "End the current operation?",
      { accept_label = "TERMINATE", cancel_label = "ABORT",
        accept_color = RED,
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
    Modal.show("TERMINATE SESSION", "End the current operation?",
      { accept_label = "TERMINATE", cancel_label = "ABORT", accept_color = RED,
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

-- crosshair drawing
local function draw_crosshair(cx, cy, r, c, alpha)
  col(c, alpha)
  love.graphics.setLineWidth(1.2)
  love.graphics.line(cx - r, cy, cx - r*0.3, cy)
  love.graphics.line(cx + r*0.3, cy, cx + r, cy)
  love.graphics.line(cx, cy - r, cx, cy - r*0.3)
  love.graphics.line(cx, cy + r*0.3, cx, cy + r)
  love.graphics.circle("line", cx, cy, r * 0.5)
  love.graphics.circle("line", cx, cy, 2)
  love.graphics.setLineWidth(1)
end

-- coordinate tick marks along edges
local function draw_ruler()
  col(GRN, 0.35)
  local m = 6
  local step = 40
  for x = m + step, W - m, step do
    love.graphics.line(x, Frame.TOP_H + 40, x, Frame.TOP_H + 46)
    love.graphics.line(x, H - Frame.BOTTOM_H - 46, x, H - Frame.BOTTOM_H - 40)
  end
  for y = Frame.TOP_H + 40 + step, H - Frame.BOTTOM_H - 46, step do
    love.graphics.line(m + 40, y, m + 46, y)
    love.graphics.line(W - m - 46, y, W - m - 40, y)
  end
end

local function draw_op_row(x, y, w, h, op, idx, foc)
  local acc = op.colour
  if foc then
    -- solid highlight bar
    col({acc[1]*0.22, acc[2]*0.22, acc[3]*0.22}, 0.95)
    love.graphics.rectangle("fill", x, y, w, h)
    col(acc, 0.95); love.graphics.setLineWidth(1.6)
    love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1)
    love.graphics.setLineWidth(1)
    col(acc, 1)
    love.graphics.rectangle("fill", x, y, 4, h)
    -- corner ticks
    D.corner_ticks(x + 6, y + 6, w - 12, h - 12, 8, acc, 0.95)
    -- target reticle on left
    draw_crosshair(x + 26, y + h/2, 12, acc, 0.9)
  else
    col({0.014, 0.022, 0.014}, 0.85)
    love.graphics.rectangle("fill", x, y, w, h)
    col(acc, 0.30)
    love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1)
    -- small dot in center-left
    col(acc, 0.6)
    love.graphics.circle("fill", x + 26, y + h/2, 3)
  end

  -- Code (mono, uppercase)
  love.graphics.setFont(A.font(A.FONT_MONO, foc and 11 or 10))
  col(acc, foc and 1 or 0.75)
  love.graphics.print(op.code, x + 50, y + 8)

  -- Label (bold)
  love.graphics.setFont(A.font(A.FONT_BODY_BOLD, foc and 14 or 13))
  col(foc and {1,1,1} or State.theme.text, 1)
  love.graphics.print(op.label, x + 50, y + 26)

  -- Sub
  love.graphics.setFont(A.font(A.FONT_MONO, 9))
  col(acc, foc and 0.85 or 0.55)
  love.graphics.print(op.sub, x + 50, y + 44)

  -- Right: index + arrow
  love.graphics.setFont(A.font(A.FONT_MONO, 9))
  col(acc, foc and 0.9 or 0.5)
  love.graphics.printf(string.format("[%02d]", idx), x, y + 8, w - 12, "right")
  if foc then
    local off = math.sin(t * 6) * 2
    love.graphics.setLineWidth(2.2)
    col(acc, 1)
    local ax = x + w - 16
    local ay = y + h/2
    love.graphics.line(ax - 6 + off, ay - 6, ax + off, ay, ax - 6 + off, ay + 6)
    love.graphics.setLineWidth(1)
  end
end

function S.draw()
  D.bg()
  col({0.010, 0.018, 0.012}, 1)
  love.graphics.rectangle("fill", 0, 0, W, H)

  -- fine grid
  col(GRN, 0.06)
  for gy = Frame.TOP_H, H - Frame.BOTTOM_H, 12 do
    for gx = 0, W, 12 do
      love.graphics.rectangle("fill", gx, gy, 1, 1)
    end
  end

  -- outer frame
  D.corner_ticks(6, Frame.TOP_H + 4, W - 12,
    H - Frame.TOP_H - Frame.BOTTOM_H - 8, 20, GRN, 0.5)
  draw_ruler()

  -- ─── HEADER BLOCK ───
  local hy = Frame.TOP_H + 6
  col({0,0,0}, 0.55)
  love.graphics.rectangle("fill", 16, hy, W - 32, 42)
  col(GRN, 0.75)
  love.graphics.setLineWidth(1.4)
  love.graphics.rectangle("line", 16.5, hy + 0.5, W - 33, 41)
  love.graphics.setLineWidth(1)

  -- REC dot
  if math.floor(t * 2) % 2 == 0 then
    col(RED, 1)
  else
    col(RED, 0.25)
  end
  love.graphics.circle("fill", 30, hy + 14, 5)
  love.graphics.setFont(A.font(A.FONT_MONO, 9))
  col(RED, 0.95)
  love.graphics.print("REC", 40, hy + 9)

  -- Title
  love.graphics.setFont(A.font(A.FONT_TITLE, 18))
  col(GRN, 1)
  love.graphics.print("FGD://OPERATIONS", 76, hy + 4)
  love.graphics.setFont(A.font(A.FONT_MONO, 9))
  col(GRN, 0.65)
  love.graphics.print("SECURITY CLEARANCE  /  LEVEL 4  /  AUTHORIZED", 76, hy + 26)

  -- clock right
  love.graphics.setFont(A.font(A.FONT_MONO, 12))
  col(AMB, 1)
  love.graphics.printf(os.date("%H:%M:%S"), 0, hy + 8, W - 26, "right")
  love.graphics.setFont(A.font(A.FONT_MONO, 8))
  col(GRN, 0.65)
  love.graphics.printf(os.date("%Y-%m-%d"), 0, hy + 26, W - 26, "right")

  -- ─── CROSSHAIR in top-right corner ───
  draw_crosshair(W - 70, Frame.TOP_H + 110, 24, CYA, 0.55)
  love.graphics.setFont(A.font(A.FONT_MONO, 8))
  col(CYA, 0.75)
  love.graphics.printf("LOCKED", 0, Frame.TOP_H + 100, W - 16, "right")
  love.graphics.printf("BEARING 042°", 0, Frame.TOP_H + 112, W - 16, "right")
  love.graphics.printf("ALT 0100", 0, Frame.TOP_H + 124, W - 16, "right")

  -- ─── OPERATIONS LIST ───
  local lx = 16
  local ly0 = Frame.TOP_H + 58
  local lw = W - 32
  local lh = 62
  local lgap = 4
  for i, op in ipairs(OPS) do
    local y = ly0 + (i - 1) * (lh + lgap)
    draw_op_row(lx, y, lw, lh, op, i, sel == i)
  end

  -- footer strip (scanning line)
  local sy = ly0 + N * (lh + lgap) + 4
  if sy < H - Frame.BOTTOM_H - 30 then
    col(GRN, 0.15)
    love.graphics.rectangle("fill", lx, sy, lw, 1)
    local sx = lx + ((t * 200) % lw)
    col(GRN, 0.55)
    love.graphics.rectangle("fill", sx - 20, sy, 40, 1)
    love.graphics.setFont(A.font(A.FONT_MONO, 8))
    col(GRN, 0.55)
    love.graphics.print("SCANNING...", lx, sy + 6)
  end

  Frame.draw_top("FGD", "mainmenu")
  Frame.draw_bottom({
    { key = "up",  label = "OP"    },
    { key = "a",   label = "EXEC"  },
    { key = "l2",  label = "View"  },
    { key = "b",   label = "TERM"  },
  })
  Modal.draw()
  D.scanlines(W, H, 0.09)
  D.vignette(W, H, 0.72)
end

return S
