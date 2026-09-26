-- screens/boot.lua -- boot animation.
-- Icon (fgd_icon.png) replaces the drawn folder.
-- Logo (fgd_logo.png) replaces the written title.
-- Total duration 1.8s. At the end the logo does a CRT turn-off
-- (vertical collapse -> horizontal collapse -> bright dot) and then
-- the app switches to the mainmenu, whose header now shows the logo.
local A     = require("core.assets")
local State = require("core.state")
local D     = require("ui.draw")

local S = {}
local W, H = 640, 480

local TOTAL = 1.8

local t = 0
local skipped = false
local finished = false

local function clamp01(x) return math.max(0, math.min(1, x)) end
local function smooth(x) x = clamp01(x); return x * x * (3 - 2 * x) end
local function phase(a, b)
  if t <= a then return 0 end
  if t >= b then return 1 end
  return (t - a) / (b - a)
end

local function finish()
  if finished then return end
  finished = true
  State.booted = true
  State.go("mainmenu")
end

function S.enter()
  t = 0
  skipped = false
  finished = false
  local ok, SFX = pcall(require, "core.audio")
  if ok then SFX.play("boot") end
end

function S.leave() end

function S.update(dt)
  if finished then return end
  t = t + dt
  if skipped or t >= TOTAL then
    finish()
    return
  end
end

function S.pad(_)  skipped = true end
function S.hat(_)  skipped = true end
function S.key(_)  skipped = true end
function S.textinput(_) skipped = true end

local function draw_bg()
  local th = State.theme
  love.graphics.clear(th.bg[1] or 0.02, th.bg[2] or 0.02,
                      th.bg[3] or 0.02, 1)
end

local function draw_hex(cx, cy, r, col, alpha, rot, thick)
  local pts = {}
  for i = 0, 5 do
    local a = -math.pi/2 + i * math.pi/3 + (rot or 0)
    pts[#pts + 1] = cx + math.cos(a) * r
    pts[#pts + 1] = cy + math.sin(a) * r
  end
  love.graphics.setColor(col[1], col[2], col[3], alpha)
  love.graphics.setLineWidth(thick or 1.5)
  love.graphics.polygon("line", pts)
  love.graphics.setLineWidth(1)
end

-- Classic folder glyph, restored for the boot animation.
local function draw_folder(cx, cy, s, col, alpha)
  love.graphics.setColor(col[1], col[2], col[3], alpha)
  love.graphics.rectangle("fill", cx - s, cy - s * 0.7, s * 0.7, s * 0.3)
  love.graphics.rectangle("fill", cx - s, cy - s * 0.45, s * 2, s * 1.1)
end

local function draw_icon_image(cx, cy, target_size, alpha)
  local s = target_size * 0.36
  draw_folder(cx, cy, s, {0.94, 0.66, 0.35}, alpha)
  love.graphics.setColor(0.48, 0.80, 0.90, alpha)
  love.graphics.rectangle("fill", cx - 4, cy - 4, 3, 14)
end

local function draw_logo_rings()
  local th = State.theme
  local cx, cy = W / 2, H / 2 - 40
  local p1 = smooth(phase(0.05, 0.45))
  if p1 > 0.01 then
    D.glow(cx, cy, 90 * p1, th.amber_hi, 0.9 * p1)
    draw_hex(cx, cy, 66 * p1, th.amber_hi, 0.95 * p1, 0, 2.4)
    draw_hex(cx, cy, 50 * p1, th.amber_hi, 0.60 * p1, math.pi/6, 1.2)
  end
end

-- Icon stage: appears between 0.20 and 0.60
local function draw_icon_stage()
  local cx, cy = W / 2, H / 2 - 40
  local p = smooth(phase(0.20, 0.60))
  if p <= 0.01 then return end
  draw_icon_image(cx, cy, 72, p)
end

-- Logo stage: appears between 0.60 and 1.10, then CRT turn-off
local function draw_logo_stage()
  local logo = A.image("assets/images/fgd_logo.png")
  if not logo then return end

  local iw, ih = logo:getDimensions()
  local target_w = 300
  local sc = target_w / iw
  local dw, dh = iw * sc, ih * sc
  local cx, cy = W / 2, H / 2 + 82

  local appear = smooth(phase(0.60, 1.10))
  if appear <= 0.01 then return end

  -- CRT turn-off starts at 1.50 and ends at TOTAL (0.30s)
  local CRT_START = 1.50
  local crt_t = 0
  if t >= CRT_START then
    crt_t = math.max(0, math.min(1, (t - CRT_START) / (TOTAL - CRT_START)))
  end

  if crt_t <= 0 then
    -- Normal fade-in
    love.graphics.setColor(1, 1, 1, appear)
    love.graphics.draw(logo, cx - dw / 2, cy - dh / 2, 0, sc, sc)
    love.graphics.setColor(1, 1, 1, 1)
    return
  end

  -- CRT turn-off
  -- Phase A (0.00-0.50): vertical collapse (Y from 1 to a sliver)
  -- Phase B (0.50-0.85): horizontal collapse (X from 1 to a sliver)
  -- Phase C (0.85-1.00): bright dot flash and fade
  local sy, sx
  if crt_t < 0.50 then
    sy = math.max(0.02, 1 - crt_t * 2)
    sx = 1
  elseif crt_t < 0.85 then
    sy = 0.02
    sx = math.max(0.02, 1 - (crt_t - 0.50) / 0.35)
  else
    sy = 0.02
    sx = 0.02
  end

  love.graphics.push()
  love.graphics.translate(cx, cy)
  love.graphics.scale(sx, sy)
  love.graphics.setColor(1, 1, 1, appear)
  love.graphics.draw(logo, -dw / 2, -dh / 2, 0, sc, sc)
  love.graphics.pop()
  love.graphics.setColor(1, 1, 1, 1)

  -- Scanline flash during phase A
  if crt_t < 0.50 then
    love.graphics.setColor(1, 1, 1, (1 - crt_t * 2) * 0.35 * appear)
    love.graphics.rectangle("fill", cx - dw / 2, cy - 2, dw, 4)
  end

  -- Bright dot flash at the end
  if crt_t > 0.78 then
    local da = (crt_t - 0.78) / 0.22
    local dot_a = math.sin(da * math.pi)
    love.graphics.setColor(1, 0.9, 0.7, dot_a * 0.95)
    love.graphics.circle("fill", cx, cy, 14 * (1 - da) + 2)
    love.graphics.setColor(1, 1, 1, dot_a * 0.7)
    love.graphics.circle("fill", cx, cy, 6 * (1 - da) + 1)
    -- Wide amber glow behind the dot
    love.graphics.setColor(0.94, 0.66, 0.35, dot_a * 0.25)
    love.graphics.circle("fill", cx, cy, 40 * (1 - da * 0.6))
  end
end

local function draw_progress()
  local th = State.theme
  local p = smooth(phase(0.15, 1.60))
  if p <= 0 then return end
  local bw, bh = 240, 4
  local bx = (W - bw) / 2
  local by = H - 62
  love.graphics.setColor(0.10, 0.08, 0.06, 1)
  love.graphics.rectangle("fill", bx, by, bw, bh)
  love.graphics.setColor(th.amber_hi[1], th.amber_hi[2], th.amber_hi[3], 1)
  love.graphics.rectangle("fill", bx, by, bw * p, bh)
  love.graphics.setColor(th.text_dim[1], th.text_dim[2], th.text_dim[3], 0.9)
  love.graphics.setFont(A.font(A.FONT_MONO, 14))
  love.graphics.printf(string.format("LOADING  %3d%%", math.floor(p * 100)),
    0, by - 20, W, "center")
  love.graphics.setColor(th.text_dark[1], th.text_dark[2], th.text_dark[3],
    0.5 + 0.35 * math.sin(t * 2))
  love.graphics.setFont(A.font(A.FONT_BODY, 13))
  love.graphics.printf("press any key to skip", 0, H - 28, W, "center")
end

function S.draw()
  draw_bg()

  local th = State.theme
  -- Dot grid background
  love.graphics.setColor(th.grid_faint[1], th.grid_faint[2], th.grid_faint[3], 0.20)
  for y = 0, H, 12 do
    for x = 0, W, 12 do
      love.graphics.rectangle("fill", x, y, 1, 1)
    end
  end

  draw_logo_rings()
  draw_icon_stage()
  draw_logo_stage()
  draw_progress()

  D.scanlines(W, H, 0.10)
  D.vignette(W, H, 0.65)
end

return S
