-- ui/plugin_intro.lua -- unified 1s skippable intro with 3 styles.
-- Signature: M.start(key, name, colour_table, style)
--   style = "hex"    -> FGD-X Plugins (concentric hexagons)
--           "grid"   -> SPDW muOS Apps (composing grid)
--           "minoru" -> Minoru's Store (icon + rings)
local A = require("core.assets")

local M = {
  active   = false,
  name     = "",
  colour   = {0.70, 0.55, 0.92},
  style    = "hex",
  t        = 0,
  duration = 1.0,
  seen     = {},
  icon     = nil,
  icon_tried = false,
}

local function safe_colour(c)
  if type(c) ~= "table" then return {0.70, 0.55, 0.92} end
  if type(c[1]) ~= "number" or type(c[2]) ~= "number" or type(c[3]) ~= "number" then
    return {0.70, 0.55, 0.92}
  end
  return c
end

function M.start(key, name, colour, style)
  if key and M.seen[key] then return end
  if key then M.seen[key] = true end
  M.active   = true
  M.name     = tostring(name or "Plugin")
  M.colour   = safe_colour(colour)
  M.style    = style or "hex"
  M.t        = 0
end

function M.skip()
  M.active = false
  M.t = 0
end

function M.is_active() return M.active == true end

function M.update(dt)
  if not M.active then return end
  M.t = M.t + dt
  if M.t >= M.duration then
    M.active = false
    M.t = 0
  end
end

local function col(c, a)
  if type(c) ~= "table" then c = {0.70, 0.55, 0.92} end
  love.graphics.setColor(c[1] or 1, c[2] or 1, c[3] or 1, a or 1)
end

local function ease_out(p) return 1 - (1 - p) ^ 3 end

-- ============================================================
--  STYLE: HEX (FGD-X Plugins)
-- ============================================================
local function draw_hex_style(cx, cy, p, acc, a)
  local r_base = 60 + ease_out(p) * 40
  -- 3 concentric hexagons rotating at different speeds
  for k = 1, 3 do
    local r = r_base + (k - 1) * 18
    local rot = (k % 2 == 0) and (M.t * 0.8) or (-M.t * 0.5)
    local alpha_k = a * (0.55 / k)
    local pts = {}
    for i = 0, 5 do
      local ang = -math.pi / 2 + i * math.pi / 3 + rot
      pts[#pts + 1] = cx + math.cos(ang) * r
      pts[#pts + 1] = cy + math.sin(ang) * r * 0.92
    end
    col(acc, alpha_k)
    love.graphics.setLineWidth(2 - k * 0.4)
    love.graphics.polygon("line", pts)
  end
  love.graphics.setLineWidth(1)

  -- Glow
  if p > 0.10 and p < 0.90 then
    local gp = math.min(1, (p - 0.10) / 0.30)
    love.graphics.setBlendMode("add")
    for i = 1, 5 do
      col(acc, a * (0.07 / i))
      love.graphics.circle("fill", cx, cy, 40 + i * 30 * gp)
    end
    love.graphics.setBlendMode("alpha")
  end
end

-- ============================================================
--  STYLE: GRID (SPDW muOS Apps)
-- ============================================================
local function draw_grid_style(cx, cy, p, acc, a)
  local n = 5
  local cell = 22
  local spacing = 26
  local total_w = (n - 1) * spacing
  local total_h = (n - 1) * spacing

  -- Compose the grid progressively
  local visible_count = math.floor(ease_out(p) * n * n)

  love.graphics.setLineWidth(2)
  local idx = 0
  for i = 0, n - 1 do
    for j = 0, n - 1 do
      idx = idx + 1
      if idx <= visible_count then
        local px = cx - total_w / 2 + i * spacing
        local py = cy - total_h / 2 + j * spacing

        -- Stagger reveal: cells closer to center appear first
        local dx = i - (n - 1) / 2
        local dy = j - (n - 1) / 2
        local dist = math.sqrt(dx * dx + dy * dy)
        local order = (n - 1) - dist
        if order <= ease_out(p) * n then
          col(acc, a * 0.9)
          love.graphics.rectangle("line",
            px - cell / 2, py - cell / 2, cell, cell, 3, 3)
          -- Inner dot
          col(acc, a * 0.5)
          love.graphics.rectangle("fill",
            px - 3, py - 3, 6, 6, 1, 1)
        end
      end
    end
  end
  love.graphics.setLineWidth(1)

  -- Central glow
  if p > 0.10 and p < 0.90 then
    local gp = math.min(1, (p - 0.10) / 0.30)
    love.graphics.setBlendMode("add")
    for i = 1, 5 do
      col(acc, a * (0.06 / i))
      love.graphics.circle("fill", cx, cy, 30 + i * 28 * gp)
    end
    love.graphics.setBlendMode("alpha")
  end
end

-- ============================================================
--  STYLE: MINORU (Minoru's Store)
-- ============================================================
local function draw_minoru_style(cx, cy, p, acc, a)
  -- Load the icon once
  if not M.icon_tried then
    M.icon_tried = true
    local ok, img = pcall(function()
      return A.image("assets/images/minoru_icon.png")
    end)
    if ok and img then M.icon = img end
  end

  local r_base = 70 + ease_out(p) * 30

  -- Concentric rings (draw-on effect)
  for k = 1, 3 do
    local r = r_base + (k - 1) * 22
    local alpha_k = a * (0.55 / k)
    col(acc, alpha_k)
    love.graphics.setLineWidth(2)
    -- Partial arc that fills up
    local arc_end = -math.pi / 2 + ease_out(p) * math.pi * 2
    love.graphics.arc("line", "open", cx, cy, r, -math.pi / 2, arc_end)
  end
  love.graphics.setLineWidth(1)

  -- Central icon or fallback
  local icon_r = 42
  if M.icon then
    local iw, ih = M.icon:getDimensions()
    local sc = (icon_r * 2) / math.max(iw, ih)
    local dw, dh = iw * sc, ih * sc
    love.graphics.setColor(1, 1, 1, a)
    love.graphics.draw(M.icon, cx - dw / 2, cy - dh / 2, 0, sc, sc)
    love.graphics.setColor(1, 1, 1, 1)
  else
    -- Fallback: stylized M in a circle
    col(acc, a * 0.9)
    love.graphics.setLineWidth(2.4)
    love.graphics.circle("line", cx, cy, icon_r)
    love.graphics.line(cx - icon_r * 0.5, cy, cx - icon_r * 0.5, cy + icon_r * 0.5)
    love.graphics.line(cx + icon_r * 0.5, cy, cx + icon_r * 0.5, cy + icon_r * 0.5)
    love.graphics.line(cx - icon_r * 0.5, cy, cx, cy - icon_r * 0.3)
    love.graphics.line(cx + icon_r * 0.5, cy, cx, cy - icon_r * 0.3)
    love.graphics.setLineWidth(1)
  end

  -- Glow
  if p > 0.10 and p < 0.90 then
    local gp = math.min(1, (p - 0.10) / 0.30)
    love.graphics.setBlendMode("add")
    for i = 1, 6 do
      col(acc, a * (0.06 / i))
      love.graphics.circle("fill", cx, cy, 50 + i * 30 * gp)
    end
    love.graphics.setBlendMode("alpha")
  end
end

-- ============================================================
--  MAIN DRAW
-- ============================================================
function M.draw()
  if not M.active then return end

  local W, H = love.graphics.getWidth(), love.graphics.getHeight()
  local p = M.t / M.duration
  local acc = safe_colour(M.colour)

  -- Opaque backdrop from frame 1
  local bg_a
  if p < 0.70 then bg_a = 1
  else bg_a = (1 - p) / 0.30 end
  bg_a = math.max(0, math.min(1, bg_a))

  love.graphics.setColor(0.02, 0.02, 0.03, 1)
  love.graphics.rectangle("fill", 0, 0, W, H)

  local a
  if p < 0.15 then a = p / 0.15
  elseif p < 0.70 then a = 1
  else a = (1 - p) / 0.30 end
  a = math.max(0, math.min(1, a)) * bg_a

  local cx, cy = W / 2, H / 2 - 10

  -- Style-specific visual
  if M.style == "minoru" then
    draw_minoru_style(cx, cy, p, acc, a)
  elseif M.style == "grid" then
    draw_grid_style(cx, cy, p, acc, a)
  else
    draw_hex_style(cx, cy, p, acc, a)
  end

  -- Name (below the visual)
  col(acc, a)
  love.graphics.setFont(A.font(A.FONT_TITLE, 24))
  love.graphics.printf(M.name:upper(), 0, cy + 90, W, "center")

  -- Subtitle
  love.graphics.setFont(A.font(A.FONT_MONO, 10))
  love.graphics.setColor(0.75, 0.80, 0.85, a * 0.85)
  love.graphics.printf("LOADING", 0, cy + 124, W, "center")

  -- Skip hint
  if p > 0.25 then
    local blink = (math.sin(M.t * 6) + 1) * 0.5
    love.graphics.setColor(0.85, 0.85, 0.85, a * (0.4 + 0.5 * blink))
    love.graphics.setFont(A.font(A.FONT_MONO, 10))
    love.graphics.printf("press any key to skip", 0, H - 60, W, "center")
  end

  -- Fade-out veil
  if bg_a < 1 then
    love.graphics.setColor(0, 0, 0, 1 - bg_a)
    love.graphics.rectangle("fill", 0, 0, W, H)
  end
end

return M
