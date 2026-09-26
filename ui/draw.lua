-- ui/draw.lua — Blame! drawing primitives.
-- All shapes angular. Nothing rounded except circles.
-- Every primitive is deterministic, cheap, and screen-size agnostic.
local D = {}

local _noise_canvas = nil

local function theme()
  local ok, S = pcall(require, "core.state")
  if ok and S.theme then return S.theme end
  return {
    bg = {0.024, 0.020, 0.016},
    structure = {0.098, 0.085, 0.070},
    grid_faint = {0.140, 0.122, 0.100},
    text = {0.85, 0.82, 0.76},
  }
end

-- ── Deterministic noise ─────────────────────────────────────
local function nrand(seed, i)
  local v = math.sin((seed * 12.9898 + i * 78.233)) * 43758.5453
  return v - math.floor(v)
end

-- ── Background ──────────────────────────────────────────────
function D.bg()
  local th = theme()
  love.graphics.setColor(th.bg)
  love.graphics.rectangle("fill", 0, 0,
    love.graphics.getWidth(), love.graphics.getHeight())
end

function D.fog(w, h, strength)
  strength = strength or 0.6
  for i = 1, 6 do
    local a = strength * (i / 6) * 0.09
    love.graphics.setColor(0, 0, 0, a)
    love.graphics.rectangle("line",
      -i * 6, -i * 6, w + i * 12, h + i * 12)
  end
end

-- ── Static noise canvas (lazy, one-time) ────────────────────
local function ensure_noise()
  if _noise_canvas then return _noise_canvas end
  local N = 256
  _noise_canvas = love.graphics.newCanvas(N, N)
  local prev = love.graphics.getCanvas()
  love.graphics.setCanvas(_noise_canvas)
  love.graphics.clear(0, 0, 0, 0)
  for i = 1, 3000 do
    local x = nrand(i, 1) * N
    local y = nrand(i, 2) * N
    local a = nrand(i, 3) * 0.6
    love.graphics.setColor(1, 1, 1, a)
    love.graphics.rectangle("fill", x, y, 1, 1)
  end
  love.graphics.setCanvas(prev)
  return _noise_canvas
end

function D.static(w, h, alpha, seed)
  local c = ensure_noise()
  love.graphics.setColor(1, 1, 1, alpha or 0.05)
  local sx = (seed or 0) * 0.13
  love.graphics.draw(c, 0, 0, 0, w / 256, h / 256, sx * 100, seed or 0)
end

function D.scanlines(w, h, alpha)
  love.graphics.setColor(0, 0, 0, alpha or 0.10)
  for y = 0, h, 3 do
    love.graphics.rectangle("fill", 0, y, w, 1)
  end
end

function D.vignette(w, h, strength)
  strength = strength or 0.6
  for i = 1, 5 do
    local a = strength * (i / 5) * 0.16
    love.graphics.setColor(0, 0, 0, a)
    love.graphics.rectangle("line",
      -i * 6, -i * 6, w + i * 12, h + i * 12)
  end
end

function D.crt(w, h, alpha)
  D.scanlines(w, h, alpha)
  D.vignette(w, h, 0.65)
end

-- ── Technical grid ──────────────────────────────────────────
function D.grid(x, y, w, h, step, col, alpha)
  step  = step or 16
  col   = col or {0.14, 0.12, 0.10}
  alpha = alpha or 0.35
  love.graphics.setColor(col[1], col[2], col[3], alpha)
  love.graphics.setLineWidth(1)
  for gx = x, x + w, step do
    love.graphics.line(gx, y, gx, y + h)
  end
  for gy = y, y + h, step do
    love.graphics.line(x, gy, x + w, gy)
  end
end

-- ── Chamfered box (angular, no curves) ──────────────────────
-- Returns nothing. Fill and line are optional.
function D.chamfer_box(x, y, w, h, cut, fill, line)
  cut = cut or 6
  local pts = {
    x + cut,     y,
    x + w - cut, y,
    x + w,       y + cut,
    x + w,       y + h - cut,
    x + w - cut, y + h,
    x + cut,     y + h,
    x,           y + h - cut,
    x,           y + cut,
  }
  if fill then
    love.graphics.setColor(fill[1], fill[2], fill[3], fill[4] or 1)
    love.graphics.polygon("fill", pts)
  end
  if line then
    love.graphics.setColor(line[1], line[2], line[3], line[4] or 1)
    love.graphics.setLineWidth(1.4)
    love.graphics.polygon("line", pts)
    love.graphics.setLineWidth(1)
  end
end

-- ── Hairline separator ──────────────────────────────────────
function D.hline(x, y, w, col, alpha)
  col = col or {0.5, 0.5, 0.5}
  love.graphics.setColor(col[1], col[2], col[3], alpha or 0.4)
  love.graphics.setLineWidth(1)
  love.graphics.line(x, y, x + w, y)
end

function D.vline(x, y, h, col, alpha)
  col = col or {0.5, 0.5, 0.5}
  love.graphics.setColor(col[1], col[2], col[3], alpha or 0.4)
  love.graphics.setLineWidth(1)
  love.graphics.line(x, y, x, y + h)
end

-- ── Corner ticks (L-shaped, one per corner) ─────────────────
function D.corner_ticks(x, y, w, h, size, col, alpha)
  size  = size or 10
  alpha = alpha or 0.9
  love.graphics.setColor(col[1], col[2], col[3], alpha)
  love.graphics.setLineWidth(1.6)
  -- TL
  love.graphics.line(x, y + size, x, y)
  love.graphics.line(x, y, x + size, y)
  -- TR
  love.graphics.line(x + w - size, y, x + w, y)
  love.graphics.line(x + w, y, x + w, y + size)
  -- BR
  love.graphics.line(x + w, y + h - size, x + w, y + h)
  love.graphics.line(x + w, y + h, x + w - size, y + h)
  -- BL
  love.graphics.line(x + size, y + h, x, y + h)
  love.graphics.line(x, y + h, x, y + h - size)
  love.graphics.setLineWidth(1)
end

-- ── Crosshair marker at a point ─────────────────────────────
function D.crosshair(cx, cy, size, col, alpha)
  size  = size or 6
  alpha = alpha or 0.9
  love.graphics.setColor(col[1], col[2], col[3], alpha)
  love.graphics.setLineWidth(1.2)
  love.graphics.line(cx - size, cy, cx - 2, cy)
  love.graphics.line(cx + 2, cy, cx + size, cy)
  love.graphics.line(cx, cy - size, cx, cy - 2)
  love.graphics.line(cx, cy + 2, cx, cy + size)
  love.graphics.setLineWidth(1)
end

-- ── Halftone dither (subtle texture) ────────────────────────
function D.dither(x, y, w, h, col, alpha)
  alpha = alpha or 0.08
  love.graphics.setColor(col[1], col[2], col[3], alpha)
  for yy = y, y + h, 4 do
    for xx = x + ((math.floor((yy - y) / 4) % 2) * 2), x + w, 4 do
      love.graphics.rectangle("fill", xx, yy, 1, 1)
    end
  end
end

-- ── Radial glow (layered arcs, cheap) ───────────────────────
function D.glow(cx, cy, r, col, intensity)
  intensity = intensity or 1
  for i = 6, 1, -1 do
    local t = i / 6
    love.graphics.setColor(col[1], col[2], col[3],
      0.09 * intensity * (1 - t))
    love.graphics.circle("fill", cx, cy, r * t)
  end
end

-- ── Hard outline rectangle (Blame! style) ───────────────────
function D.outline(x, y, w, h, col, thickness, alpha)
  thickness = thickness or 1
  alpha     = alpha or 1
  love.graphics.setColor(col[1], col[2], col[3], alpha)
  love.graphics.setLineWidth(thickness)
  love.graphics.rectangle("line", x, y, w, h)
  love.graphics.setLineWidth(1)
end

-- ── Cross-hatch fill (dense industrial pattern) ─────────────
function D.hatch(x, y, w, h, step, col, alpha)
  step  = step or 6
  col   = col or {0.4, 0.4, 0.4}
  alpha = alpha or 0.15
  love.graphics.setColor(col[1], col[2], col[3], alpha)
  love.graphics.setLineWidth(1)
  local x1, y1 = x - h, y + h
  local x2, y2 = x + w, y
  for i = 0, math.ceil((w + h) / step) do
    local sx = x + i * step
    local ex = x + i * step - h
    local cx1 = math.max(x, math.min(x + w, sx))
    local cy1 = math.max(y, math.min(y + h, y + (sx - x)))
    local cx2 = math.max(x, math.min(x + w, ex))
    local cy2 = math.max(y, math.min(y + h, y + h + (ex - x)))
    love.graphics.line(cx1, cy1, cx2, cy2)
  end
end

-- ── Corner bracket (single corner tick, heavy) ──────────────
function D.bracket(x, y, size, col, corner)
  love.graphics.setColor(col)
  love.graphics.setLineWidth(2.2)
  if corner == "tl" or not corner then
    love.graphics.line(x, y + size, x, y)
    love.graphics.line(x, y, x + size, y)
  elseif corner == "tr" then
    love.graphics.line(x - size, y, x, y)
    love.graphics.line(x, y, x, y + size)
  elseif corner == "br" then
    love.graphics.line(x, y - size, x, y)
    love.graphics.line(x - size, y, x, y)
  elseif corner == "bl" then
    love.graphics.line(x, y - size, x, y)
    love.graphics.line(x, y, x + size, y)
  end
  love.graphics.setLineWidth(1)
end

-- ── Loading bar (thin industrial) ───────────────────────────
function D.bar(x, y, w, h, p, col_bg, col_fg)
  col_bg = col_bg or {0.10, 0.10, 0.10}
  col_fg = col_fg or {0.94, 0.66, 0.35}
  love.graphics.setColor(col_bg[1], col_bg[2], col_bg[3], 1)
  love.graphics.rectangle("fill", x, y, w, h)
  love.graphics.setColor(col_fg[1], col_fg[2], col_fg[3], 1)
  love.graphics.rectangle("fill", x, y, w * math.max(0, math.min(1, p)), h)
  love.graphics.setColor(col_fg[1], col_fg[2], col_fg[3], 0.35)
  love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1)
end

return D
