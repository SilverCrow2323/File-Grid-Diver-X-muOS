-- ui/button_icons.lua -- centralized button icon renderer.
-- Every button in the app uses these glyphs. Never plain letters.
--
-- Spec:
--   A  red circle + "A"
--   B  yellow circle + "B"
--   X  blue circle + "X"
--   Y  green circle + "Y"
--   D-pad   grey directional cross (or single-arrow, per context)
--   L1/R1   dark grey rounded rectangle + "L1"/"R1"
--   L2/R2   dark grey rounded rectangle + "L2"/"R2"
--   Start/Select  small dark grey circle + label BELOW
--   M       transparent circle outline + "M"
--   Any     small asterisk circle

local A = require("core.assets")
local M = {}

-- Palette -------------------------------------------------------
local C_A = {0.90, 0.25, 0.22}   -- red
local C_B = {0.95, 0.80, 0.20}   -- yellow
local C_X = {0.30, 0.55, 0.95}   -- blue
local C_Y = {0.30, 0.80, 0.35}   -- green
local C_DPAD   = {0.55, 0.55, 0.60}
local C_SHOULDER = {0.35, 0.35, 0.42}
local C_SMALL = {0.28, 0.28, 0.34}
local C_FACE_OUTLINE = {0.05, 0.05, 0.05}

local function col(c, a) love.graphics.setColor(c[1], c[2], c[3], a or 1) end

-- Circle face button (A/B/X/Y) ---------------------------------
local function draw_face(cx, cy, r, label, colour, textColour)
  -- shadow
  love.graphics.setColor(0, 0, 0, 0.55)
  love.graphics.circle("fill", cx, cy + 1.5, r)
  -- rim
  col(C_FACE_OUTLINE, 1)
  love.graphics.circle("fill", cx, cy, r + 1)
  -- body
  col(colour, 1)
  love.graphics.circle("fill", cx, cy, r)
  -- highlight arc
  love.graphics.setColor(1, 1, 1, 0.22)
  love.graphics.arc("fill", "pie", cx, cy, r - 2, math.pi, math.pi * 2)
  -- label
  local f = A.font_raw(A.FONT_BODY_BOLD, math.floor(r * 0.95))
  love.graphics.setFont(f)
  col(textColour or {1, 1, 1}, 1)
  local w = f:getWidth(label)
  love.graphics.print(label, cx - w / 2, cy - f:getHeight() / 2)
end

-- D-pad ---------------------------------------------------------
local function draw_dpad(cx, cy, r)
  -- cross of four arms, grey
  local arm = r * 0.55
  local th  = r * 0.42
  col(C_DPAD, 1)
  love.graphics.rectangle("fill", cx - th/2, cy - arm - th/2, th, arm * 2 + th, 2, 2)
  love.graphics.rectangle("fill", cx - arm - th/2, cy - th/2, arm * 2 + th, th, 2, 2)
  -- subtle centre dot
  col({0.30, 0.30, 0.34}, 1)
  love.graphics.circle("fill", cx, cy, th * 0.35)
end

-- D-pad direction (single arrow on grey cap) --------------------
local function draw_dpad_dir(cx, cy, r, dir)
  col(C_DPAD, 1)
  love.graphics.rectangle("fill", cx - r, cy - r * 0.8, r * 2, r * 1.6, 3, 3)
  col({0.15, 0.15, 0.18}, 1)
  local s = r * 0.55
  if dir == "up" then
    love.graphics.polygon("fill", cx, cy - s, cx + s*0.7, cy + s*0.3, cx - s*0.7, cy + s*0.3)
  elseif dir == "down" then
    love.graphics.polygon("fill", cx, cy + s, cx + s*0.7, cy - s*0.3, cx - s*0.7, cy - s*0.3)
  elseif dir == "left" then
    love.graphics.polygon("fill", cx - s, cy, cx + s*0.3, cy - s*0.7, cx + s*0.3, cy + s*0.7)
  elseif dir == "right" then
    love.graphics.polygon("fill", cx + s, cy, cx - s*0.3, cy - s*0.7, cx - s*0.3, cy + s*0.7)
  end
end

-- Shoulder (L1/R1/L2/R2) ---------------------------------------
local function draw_shoulder(cx, cy, w, h, label, darker)
  local c = darker and {0.25, 0.25, 0.32} or C_SHOULDER
  -- shadow
  love.graphics.setColor(0, 0, 0, 0.55)
  love.graphics.rectangle("fill", cx - w/2, cy - h/2 + 1.5, w, h, 5, 5)
  -- body
  col(c, 1)
  love.graphics.rectangle("fill", cx - w/2, cy - h/2, w, h, 5, 5)
  -- top highlight
  love.graphics.setColor(1, 1, 1, 0.14)
  love.graphics.rectangle("fill", cx - w/2 + 1, cy - h/2 + 1, w - 2, h * 0.4, 4, 4)
  -- label
  local f = A.font_raw(A.FONT_BODY_BOLD, math.floor(h * 0.66))
  love.graphics.setFont(f)
  col({0.95, 0.95, 0.95}, 1)
  local lw = f:getWidth(label)
  love.graphics.print(label, cx - lw/2, cy - f:getHeight()/2)
end

-- Small circle (start/select) ----------------------------------
local function draw_small_circle(cx, cy, r, label_below)
  love.graphics.setColor(0, 0, 0, 0.55)
  love.graphics.circle("fill", cx, cy + 1.5, r)
  col(C_SMALL, 1)
  love.graphics.circle("fill", cx, cy, r)
  love.graphics.setColor(1, 1, 1, 0.14)
  love.graphics.arc("fill", "pie", cx, cy, r - 2, math.pi, math.pi * 2)
  if label_below then
    local f = A.font_raw(A.FONT_BODY, 8)
    love.graphics.setFont(f)
    col({0.85, 0.85, 0.85}, 0.95)
    local lw = f:getWidth(label_below)
    love.graphics.print(label_below, cx - lw/2, cy + r + 2)
  end
end

-- M (transparent outline) --------------------------------------
local function draw_m(cx, cy, r)
  col({0.95, 0.95, 0.95}, 0.9)
  love.graphics.setLineWidth(1.6)
  love.graphics.circle("line", cx, cy, r)
  love.graphics.setLineWidth(1)
  local f = A.font_raw(A.FONT_BODY_BOLD, math.floor(r * 0.95))
  love.graphics.setFont(f)
  col({1, 1, 1}, 1)
  local w = f:getWidth("M")
  love.graphics.print("M", cx - w/2, cy - f:getHeight()/2)
end

-- Any-key asterisk ---------------------------------------------
local function draw_any(cx, cy, r)
  col({0.60, 0.55, 0.40}, 1)
  love.graphics.circle("fill", cx, cy, r)
  love.graphics.setFont(A.font_raw(A.FONT_BODY_BOLD, math.floor(r * 1.2)))
  col({1, 1, 1}, 1)
  love.graphics.print("*", cx - 3, cy - r * 0.6)
end

-- =============================================================
--  Public API
-- =============================================================
-- draw(cx, cy, size, key) -- size is the "unit radius"
function M.draw(cx, cy, size, key)
  key = (key or ""):lower()
  if     key == "a" then draw_face(cx, cy, size, "A", C_A, {1, 1, 1})
  elseif key == "b" then draw_face(cx, cy, size, "B", C_B, {0.10, 0.08, 0.02})
  elseif key == "x" then draw_face(cx, cy, size, "X", C_X, {1, 1, 1})
  elseif key == "y" then draw_face(cx, cy, size, "Y", C_Y, {0.05, 0.15, 0.05})
  elseif key == "up"    then draw_dpad_dir(cx, cy, size, "up")
  elseif key == "down"  then draw_dpad_dir(cx, cy, size, "down")
  elseif key == "left"  then draw_dpad_dir(cx, cy, size, "left")
  elseif key == "right" then draw_dpad_dir(cx, cy, size, "right")
  elseif key == "dpad"  then draw_dpad(cx, cy, size)
  elseif key == "l1" then draw_shoulder(cx, cy, size * 2.4, size * 1.35, "L1", false)
  elseif key == "r1" then draw_shoulder(cx, cy, size * 2.4, size * 1.35, "R1", false)
  elseif key == "l2" then draw_shoulder(cx, cy, size * 2.4, size * 1.35, "L2", true)
  elseif key == "r2" then draw_shoulder(cx, cy, size * 2.4, size * 1.35, "R2", true)
  elseif key == "start"  then draw_small_circle(cx, cy - 4, size * 0.85, "start")
  elseif key == "select" then draw_small_circle(cx, cy - 4, size * 0.85, "select")
  elseif key == "st"     then draw_small_circle(cx, cy - 4, size * 0.85, "start")
  elseif key == "se"     then draw_small_circle(cx, cy - 4, size * 0.85, "select")
  elseif key == "m"      then draw_m(cx, cy, size)
  elseif key == "any"    then draw_any(cx, cy, size)
  else
    draw_any(cx, cy, size)
  end
end

-- Width in pixels of a button glyph (for hint layout)
function M.width(size, key)
  key = (key or ""):lower()
  if key == "l1" or key == "r1" or key == "l2" or key == "r2" then
    return size * 2.4 + 4
  elseif key == "start" or key == "select" or key == "st" or key == "se" then
    return size * 2.4 + 4  -- account for label below in vertical space, but width is small
  else
    return size * 2 + 4
  end
end

-- Vertical height of a button glyph
function M.height(size, key)
  key = (key or ""):lower()
  if key == "start" or key == "select" or key == "st" or key == "se" then
    return size * 3.2   -- circle + label below
  elseif key == "l1" or key == "r1" or key == "l2" or key == "r2" then
    return size * 1.5
  end
  return size * 2
end

return M
