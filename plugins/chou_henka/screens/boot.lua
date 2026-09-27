-- screens/boot.lua -- boot animato dedicato Chou Henka.
local A = require("core.assets")
local D = require("ui.draw")
local T = require("plugins.chou_henka.ui.theme")
local Icons = require("plugins.chou_henka.ui.icons")

local M = {}
local W, H = 640, 480
local t, done_flag = 0, false
local TOTAL = 1.8
local particles = nil

local function col(c, a) love.graphics.setColor(c[1], c[2], c[3], a or 1) end

local function init_particles()
  particles = {}
  local seed = os.time()
  for i = 1, 90 do
    local r1 = (math.sin(i * 12.9898 + seed) * 43758.5453) % 1
    local r2 = (math.sin(i * 78.233  + seed) * 43758.5453) % 1
    local r3 = (math.sin(i * 45.164  + seed) * 43758.5453) % 1
    particles[i] = {
      a = r1 * math.pi * 2,
      r = 40 + r2 * 200,
      s = 0.3 + r3 * 1.2,
      sz = 1 + r2 * 2,
    }
  end
end

function M.enter() t = 0; done_flag = false; init_particles() end
function M.update(dt) t = t + dt; if t >= TOTAL then done_flag = true end end
function M.is_done() return done_flag end
function M.skip() done_flag = true end
function M.pad(_) M.skip() end
function M.hat(_) M.skip() end
function M.key(_) M.skip() end

function M.draw()
  love.graphics.clear(0.015, 0.010, 0.025, 1)
  local th = T.current()
  local cx, cy = W/2, H/2 - 20
  local p  = math.min(1, t / TOTAL)
  local ep = 1 - (1 - p) ^ 3

  for k = 1, 4 do
    local rr  = 40 + k * 34 + ep * 20
    local rot = t * (0.6 + k * 0.3)
    col(th.accent, (0.55 / k) * (0.4 + 0.6 * math.abs(math.sin(t * 2 + k))))
    love.graphics.setLineWidth(2 - k * 0.3)
    local pts = {}
    for i = 0, 5 do
      local a = -math.pi/2 + i * math.pi/3 + rot
      pts[#pts+1] = cx + math.cos(a) * rr
      pts[#pts+1] = cy + math.sin(a) * rr
    end
    love.graphics.polygon("line", pts)
  end
  love.graphics.setLineWidth(1)

  if particles then
    for _, pp in ipairs(particles) do
      local a = pp.a + t * pp.s
      local x = cx + math.cos(a) * pp.r * (0.5 + ep * 0.5)
      local y = cy + math.sin(a) * pp.r * (0.5 + ep * 0.5)
      col(th.accent_hi, 0.5 * (1 - p))
      love.graphics.rectangle("fill", x, y, pp.sz, pp.sz)
    end
  end

  Icons.draw("music", cx, cy, 22, th.accent_hi, ep)

  love.graphics.setFont(A.font(A.FONT_TITLE, 34))
  col(th.accent_hi, ep)
  love.graphics.printf("CHOU HENKA", 0, cy + 62, W, "center")

  love.graphics.setFont(A.font(A.FONT_MONO, 11))
  col(th.accent, ep * 0.9)
  love.graphics.printf("MEDIA CENTER", 0, cy + 108, W, "center")

  local bw, bh = 260, 4
  local bx = (W - bw) / 2
  local by = H - 80
  col({0.10, 0.05, 0.15}, 1)
  love.graphics.rectangle("fill", bx, by, bw, bh)
  col(th.accent_hi, 0.95)
  love.graphics.rectangle("fill", bx, by, bw * ep, bh)

  if t > 0.4 then
    local blink = 0.5 + 0.5 * math.sin(t * 6)
    col(th.text_dim, 0.5 + 0.4 * blink)
    love.graphics.setFont(A.font(A.FONT_MONO, 9))
    love.graphics.printf("press any key to skip", 0, H - 50, W, "center")
  end

  D.scanlines(W, H, 0.08)
  D.vignette(W, H, 0.6)
end

return M
