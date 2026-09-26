-- ui/unlock_overlay.lua -- themed unlock message overlay (Final Bout).
-- Tre varianti: view / audio / both
local A = require("core.assets")
local D = require("ui.draw")

local M = { active = false, kind = nil, t = 0 }

local CONFIGS = {
  view = {
    duration = 3.6,
    acc  = {0.98, 0.78, 0.20},
    acc2 = {0.98, 0.48, 0.10},
    subtitle = "FINAL BOUT  //  ARENA MODE",
    title    = "VIEW UNLOCKED",
    line1    = "The stage is set.",
    line2    = "L2 / R2 now cycle the menu view.",
    sfx      = "finalbout",
  },
  audio = {
    duration = 3.6,
    acc  = {0.95, 0.40, 0.85},
    acc2 = {0.30, 0.85, 0.95},
    subtitle = "FINAL BOUT  //  SOUNDTRACK",
    title    = "AUDIO MODE UNLOCKED",
    line1    = "The arena sings.",
    line2    = "All SFX now play in FB mode.",
    sfx      = "finalbout",
  },
  both = {
    duration = 6.5,
    acc  = {1.00, 0.85, 0.30},
    acc2 = {0.95, 0.30, 0.90},
    subtitle = "FINAL BOUT  //  100% COMPLETE",
    title    = "CONGRATULATIONS",
    line1    = "You mastered every code.",
    line2    = "The Final Bout is yours.",
    sfx      = "finalbout_griddev2",
  },
}

local function ease_out(p) return 1 - (1 - p) ^ 3 end

function M.trigger(kind)
  local cfg = CONFIGS[kind]
  if not cfg then return end
  M.active = true
  M.kind   = kind
  M.t      = 0
  local ok, SFX = pcall(require, "core.audio")
  if ok and SFX.play then SFX.play(cfg.sfx) end
end

function M.skip()
  M.active = false
  M.kind   = nil
  M.t      = 0
end

function M.is_active() return M.active == true end

function M.update(dt)
  if not M.active then return end
  M.t = M.t + dt
  local cfg = CONFIGS[M.kind]
  if cfg and M.t >= cfg.duration then M.skip() end
end

local function draw_emblem(kind, cx, cy, r, acc, acc2, alpha)
  love.graphics.setLineWidth(2)
  if kind == "view" then
    local gap  = 3
    local size = (r * 2 - gap) / 2
    for i = 0, 1 do
      for j = 0, 1 do
        local x = cx - r + i * (size + gap)
        local y = cy - r + j * (size + gap)
        if i == 0 and j == 0 then
          love.graphics.setColor(acc2[1], acc2[2], acc2[3], alpha)
        else
          love.graphics.setColor(acc[1], acc[2], acc[3], alpha * 0.55)
        end
        love.graphics.rectangle("line", x, y, size, size, 2, 2)
      end
    end
  elseif kind == "audio" then
    local n       = 9
    local spacing = (r * 2) / (n + 1)
    for i = 1, n do
      local h = (0.35 + 0.65 * math.abs(math.sin(i * 1.7))) * r * 1.6
      local x = cx - r + i * spacing
      love.graphics.setColor(acc[1], acc[2], acc[3], alpha * 0.9)
      love.graphics.rectangle("fill", x - 2, cy - h / 2, 4, h, 1, 1)
    end
  elseif kind == "both" then
    local spikes = 8
    local pts = {}
    for i = 0, spikes * 2 - 1 do
      local a  = (i / (spikes * 2)) * math.pi * 2 - math.pi / 2
      local rr = (i % 2 == 0) and r * 1.2 or r * 0.5
      pts[#pts + 1] = cx + math.cos(a) * rr
      pts[#pts + 1] = cy + math.sin(a) * rr
    end
    love.graphics.setColor(acc[1], acc[2], acc[3], alpha)
    love.graphics.polygon("line", pts)
    love.graphics.setColor(acc2[1], acc2[2], acc2[3], alpha)
    love.graphics.circle("line", cx, cy, r * 0.4)
    love.graphics.circle("fill", cx, cy, r * 0.12)
  end
  love.graphics.setLineWidth(1)
end

local function draw_particles(W, H, t, alpha)
  for i = 1, 50 do
    local sx = (math.sin(i * 12.9898) * 43758.5453) % 1
    local sy = (math.sin(i * 78.233)  * 43758.5453) % 1
    local sv = (math.sin(i * 45.164)  * 43758.5453) % 1
    local x  = (sx * W + math.sin(t * 1.5 + i) * 30) % W
    local y  = (sy * H + t * 40 * (0.4 + sv)) % H
    local sz = 1 + sv * 2
    local a  = alpha * (0.35 + 0.65 * math.abs(math.sin(t * 2 + i)))
    love.graphics.setColor(1, 0.75 + sv * 0.25, 0.25, a)
    love.graphics.rectangle("fill", x, y, sz, sz)
  end
end

function M.draw()
  if not M.active then return end
  local cfg = CONFIGS[M.kind]
  if not cfg then return end

  local W, H = love.graphics.getWidth(), love.graphics.getHeight()
  local dur = cfg.duration
  local t   = M.t

  local p = 1
  if     t < 0.3          then p = t / 0.3
  elseif t > dur - 0.5    then p = (dur - t) / 0.5
  end
  p = math.max(0, math.min(1, p))
  local ep = ease_out(p)

  local acc, acc2 = cfg.acc, cfg.acc2

  love.graphics.setColor(0, 0, 0, 0.78 * ep)
  love.graphics.rectangle("fill", 0, 0, W, H)

  if M.kind == "both" then
    draw_particles(W, H, t, ep * 0.9)
  end

  local cw, ch = 480, 250
  local cx = (W - cw) / 2
  local cy = (H - ch) / 2 + (1 - ep) * 30
  local scale = 0.88 + 0.12 * ep

  love.graphics.push()
  love.graphics.translate(W / 2, H / 2)
  love.graphics.scale(scale, scale)
  love.graphics.translate(-W / 2, -H / 2)

  D.glow(W / 2, H / 2, cw * 0.85, acc, 0.6 * ep)

  love.graphics.setColor(0.018, 0.014, 0.028, 0.98 * ep)
  love.graphics.rectangle("fill", cx, cy, cw, ch, 6, 6)

  love.graphics.setColor(acc[1], acc[2], acc[3], 0.95 * ep)
  love.graphics.setLineWidth(2)
  love.graphics.rectangle("line", cx + 0.5, cy + 0.5, cw - 1, ch - 1, 6, 6)
  love.graphics.setLineWidth(1)
  love.graphics.setColor(acc[1], acc[2], acc[3], 0.30 * ep)
  love.graphics.rectangle("line", cx + 8.5, cy + 8.5, cw - 17, ch - 17, 4, 4)

  D.corner_ticks(cx + 12, cy + 12, cw - 24, ch - 24, 16, acc, ep)

  draw_emblem(M.kind, W / 2, cy + 50, 24, acc, acc2, ep)

  love.graphics.setFont(A.font(A.FONT_MONO, 10))
  love.graphics.setColor(acc2[1], acc2[2], acc2[3], 0.90 * ep)
  love.graphics.printf(cfg.subtitle, 0, cy + 92, W, "center")

  local pulse = 0.9 + 0.1 * math.sin(t * 4)
  love.graphics.setFont(A.font(A.FONT_TITLE, 28))
  love.graphics.setColor(acc[1], acc[2], acc[3], 0.5 * ep * pulse)
  love.graphics.printf(cfg.title, 2, cy + 114, W, "center")
  love.graphics.setColor(1, 1, 1, ep)
  love.graphics.printf(cfg.title, 0, cy + 112, W, "center")

  love.graphics.setColor(acc[1], acc[2], acc[3], 0.4 * ep)
  love.graphics.rectangle("fill", cx + 80, cy + 152, cw - 160, 1)

  love.graphics.setFont(A.font(A.FONT_BODY_BOLD, 13))
  love.graphics.setColor(1, 1, 1, 0.95 * ep)
  love.graphics.printf(cfg.line1, 0, cy + 164, W, "center")

  love.graphics.setFont(A.font(A.FONT_BODY, 11))
  love.graphics.setColor(0.75, 0.78, 0.80, 0.9 * ep)
  love.graphics.printf(cfg.line2, 0, cy + 188, W, "center")

  if t > 0.6 then
    local blink = 0.5 + 0.5 * math.sin(t * 6)
    love.graphics.setFont(A.font(A.FONT_MONO, 9))
    love.graphics.setColor(acc[1], acc[2], acc[3], blink * ep)
    love.graphics.printf("PRESS ANY BUTTON TO CONTINUE",
      0, cy + ch - 20, W, "center")
  end

  love.graphics.pop()
end

return M
