-- ui/unlock_overlay.lua -- themed unlock overlay (Final Bout).
-- Tre varianti: view / audio / both.
-- Trigger:
--   1. Suona finalbout.ogg (sting breve) SUBITO
--   2. Dopo sting_delay secondi parte il BGM dedicato
--   3. Fine: view/audio -> stop_bgm; both -> fade_bgm su 2s
-- Tutti e tre mostrano il logo Final Bout.
local A = require("core.assets")
local D = require("ui.draw")

local M = { active = false, kind = nil, t = 0 }

local CONFIGS = {
  view = {
    skippable   = true,
    duration    = 4.5,
    sting_delay = 0.9,
    acc         = {0.98, 0.78, 0.20},
    acc2        = {0.98, 0.48, 0.10},
    subtitle    = "FINAL BOUT  //  ARENA MODE",
    title       = "VIEW UNLOCKED",
    line1       = "The stage is set.",
    line2       = "L2 / R2 now cycle the menu view.",
    sting       = "finalbout",
    bgm         = "fb/fbbgm0",
    fade_out    = false,
  },
  audio = {
    skippable   = false,
    duration    = 4.5,
    sting_delay = 0.9,
    acc         = {0.95, 0.40, 0.85},
    acc2        = {0.30, 0.85, 0.95},
    subtitle    = "FINAL BOUT  //  SOUNDTRACK",
    title       = "AUDIO MODE UNLOCKED",
    line1       = "The arena sings.",
    line2       = "All SFX now play in FB mode.",
    sting       = "finalbout",
    bgm         = "fb/fbbgm2.",
    fade_out    = false,
  },
  both = {
    skippable   = false,
    duration    = 8.5,
    sting_delay = 0.9,
    acc         = {1.00, 0.85, 0.30},
    acc2        = {0.95, 0.30, 0.90},
    subtitle    = "FINAL BOUT  //  100% COMPLETE",
    title       = "CONGRATULATIONS",
    line1       = "You mastered every code.",
    line2       = "The Final Bout is yours.",
    sting       = "finalbout",
    bgm         = "fb/fbbgm1",
    fade_out    = true,
  },
}

local function ease_out(p) return 1 - (1 - p) ^ 3 end

function M.trigger(kind)
  local cfg = CONFIGS[kind]
  if not cfg then return end
  M.active       = true
  M.kind         = kind
  M.t            = 0
  M._bgm_started = false
  M._fading      = false
  local ok, SFX = pcall(require, "core.audio")
  if ok and SFX.play and cfg.sting then
    SFX.play(cfg.sting)
  end
end

function M.skip()
  M.active       = false
  M.kind         = nil
  M.t            = 0
  M._bgm_started = false
  M._fading      = false
  local ok, SFX = pcall(require, "core.audio")
  if ok and SFX.stop_bgm then SFX.stop_bgm() end
end

function M.is_active() return M.active == true end

function M.update(dt)
  if not M.active then return end
  M.t = M.t + dt
  local cfg = CONFIGS[M.kind]
  if not cfg then return end

  local ok, SFX = pcall(require, "core.audio")

  if not M._bgm_started and M.t >= (cfg.sting_delay or 0.5) then
    M._bgm_started = true
    if ok and SFX.play_bgm and cfg.bgm then
      SFX.play_bgm(cfg.bgm, 0.85)
    end
  end

  if cfg.fade_out and not M._fading and M.t >= cfg.duration - 2.0 then
    M._fading = true
    if ok and SFX.fade_bgm then SFX.fade_bgm(2.0) end
  end

  if M.t >= cfg.duration then
    if not cfg.fade_out and ok and SFX.stop_bgm then
      SFX.stop_bgm()
    end
    M.skip()
  end
end

local function draw_fblogo(cx, y_top, max_w, alpha)
  local logo = A.image("assets/images/fblogo.png")
  if not logo then return false end
  local iw, ih = logo:getDimensions()
  local target_h = 40
  local sc = target_h / ih
  if iw * sc > max_w then sc = max_w / iw end
  local dw = iw * sc
  love.graphics.setColor(1, 1, 1, alpha)
  love.graphics.draw(logo, cx - dw / 2, y_top, 0, sc, sc)
  love.graphics.setColor(1, 1, 1, 1)
  return true
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
  if     t < 0.3       then p = t / 0.3
  elseif t > dur - 0.5 then p = (dur - t) / 0.5 end
  p = math.max(0, math.min(1, p))
  local ep = ease_out(p)

  local acc, acc2 = cfg.acc, cfg.acc2

  love.graphics.setColor(0, 0, 0, 0.78 * ep)
  love.graphics.rectangle("fill", 0, 0, W, H)

  if M.kind == "both" then
    draw_particles(W, H, t, ep * 0.9)
  end

  local cw, ch = 480, 300
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

  love.graphics.setFont(A.font(A.FONT_MONO, 10))
  love.graphics.setColor(acc2[1], acc2[2], acc2[3], 0.90 * ep)
  love.graphics.printf(cfg.subtitle, 0, cy + 18, W, "center")

  local pulse = 0.9 + 0.1 * math.sin(t * 4)
  love.graphics.setFont(A.font(A.FONT_TITLE, 26))
  love.graphics.setColor(acc[1], acc[2], acc[3], 0.5 * ep * pulse)
  love.graphics.printf(cfg.title, 2, cy + 48, W, "center")
  love.graphics.setColor(1, 1, 1, ep)
  love.graphics.printf(cfg.title, 0, cy + 46, W, "center")

  draw_fblogo(W / 2, cy + 94, cw - 80, ep)

  love.graphics.setColor(acc[1], acc[2], acc[3], 0.4 * ep)
  love.graphics.rectangle("fill", cx + 80, cy + 150, cw - 160, 1)

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

function M.can_skip()
  if not M.active then return false end
  local cfg = CONFIGS[M.kind]
  if not cfg then return false end
  return cfg.skippable ~= false
end

return M
