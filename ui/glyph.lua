local M = {}

local function set(col, a)
  love.graphics.setColor(col[1], col[2], col[3], a or 1)
end

function M.dot(cx, cy, r, col, a)
  set(col, a)
  love.graphics.circle("fill", cx, cy, r)
end

function M.ring(cx, cy, r, col, a, t)
  set(col, a)
  love.graphics.setLineWidth(t or 1.4)
  love.graphics.circle("line", cx, cy, r)
  love.graphics.setLineWidth(1)
end

function M.square(cx, cy, r, col, a)
  set(col, a)
  love.graphics.rectangle("fill", cx - r, cy - r, r * 2, r * 2)
end

function M.diamond(cx, cy, r, col, a)
  set(col, a)
  love.graphics.polygon("fill",
    cx, cy - r, cx + r, cy, cx, cy + r, cx - r, cy)
end

function M.triangle_right(cx, cy, r, col, a)
  set(col, a)
  love.graphics.polygon("fill",
    cx - r * 0.55, cy - r,
    cx + r * 0.75, cy,
    cx - r * 0.55, cy + r)
end

function M.triangle_left(cx, cy, r, col, a)
  set(col, a)
  love.graphics.polygon("fill",
    cx + r * 0.55, cy - r,
    cx - r * 0.75, cy,
    cx + r * 0.55, cy + r)
end

function M.triangle_up(cx, cy, r, col, a)
  set(col, a)
  love.graphics.polygon("fill",
    cx - r, cy + r * 0.55,
    cx + r, cy + r * 0.55,
    cx,     cy - r * 0.75)
end

function M.triangle_down(cx, cy, r, col, a)
  set(col, a)
  love.graphics.polygon("fill",
    cx - r, cy - r * 0.55,
    cx + r, cy - r * 0.55,
    cx,     cy + r * 0.75)
end

function M.check(cx, cy, r, col, a)
  set(col, a)
  love.graphics.setLineWidth(math.max(1.4, r * 0.5))
  love.graphics.line(cx - r*0.7, cy + r*0.05,
                     cx - r*0.15, cy + r*0.6,
                     cx + r*0.8, cy - r*0.7)
  love.graphics.setLineWidth(1)
end

function M.cross(cx, cy, r, col, a)
  set(col, a)
  love.graphics.setLineWidth(math.max(1.4, r * 0.5))
  love.graphics.line(cx - r*0.7, cy - r*0.7, cx + r*0.7, cy + r*0.7)
  love.graphics.line(cx + r*0.7, cy - r*0.7, cx - r*0.7, cy + r*0.7)
  love.graphics.setLineWidth(1)
end

function M.arrow_right(cx, cy, r, col, a)
  set(col, a)
  love.graphics.setLineWidth(math.max(1.2, r * 0.28))
  love.graphics.line(cx - r, cy, cx + r * 0.55, cy)
  love.graphics.line(cx + r * 0.55, cy, cx + r * 0.05, cy - r * 0.6)
  love.graphics.line(cx + r * 0.55, cy, cx + r * 0.05, cy + r * 0.6)
  love.graphics.setLineWidth(1)
end

function M.circle_dashed(cx, cy, r, col, a, segments)
  segments = segments or 16
  set(col, a)
  love.graphics.setLineWidth(1.4)
  for i = 0, segments - 1 do
    if i % 2 == 0 then
      local a1 = (i / segments) * math.pi * 2
      local a2 = ((i + 1) / segments) * math.pi * 2
      love.graphics.arc("line", "open", cx, cy, r, a1, a2)
    end
  end
  love.graphics.setLineWidth(1)
end

return M
