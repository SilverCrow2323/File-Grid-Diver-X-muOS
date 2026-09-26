-- ui/finalbout.lua -- Limit Break unlock overlay.
local M = { active = false, t = 0, TOTAL = 4.3, cb = nil }

function M.trigger(cb)
  M.active = true
  M.t      = 0
  M.cb     = cb
  local ok, SFX = pcall(require, "core.audio")
  if ok then
    SFX.play("finalbout")               -- short sting, fires together
    if SFX.play_bgm then
      SFX.play_bgm("finalbout_griddev", 0.85)
    end
  end
end

local BGM_FADE = 2.0   -- seconds of fade-out after the graphic ends

function M.update(dt)
  if not M.active then return end
  M.t = M.t + dt

  -- End of graphic: fire callback, start BGM fade-out
  if M.t >= M.TOTAL then
    M.active = false
    local ok, SFX = pcall(require, "core.audio")
    if ok and SFX.fade_bgm then
      SFX.fade_bgm(BGM_FADE)
    end
    if M.cb then M.cb() end
  end
end

function M.draw()
  if not M.active then return end
  local W, H = 640, 480
  local t = M.t
  local A = require("core.assets")
  local D = require("ui.draw")

  -- interference intensity (0..1) with a bit of tremolo
  local base = math.min(1, t / 0.6)
  local tremolo = 0.7 + 0.3 * math.abs(math.sin(t * 14))
  local inter = base * tremolo
  local fade = (t > 3.8) and (1 - (t - 3.8) / 0.5) or 1

  -- Solid black backdrop
  love.graphics.setColor(0, 0, 0, 0.95 * fade)
  love.graphics.rectangle("fill", 0, 0, W, H)

  -- Horizontal tear bars
  for i = 1, 24 do
    local y = ((t * 240 + i * 31) % H)
    local th = 1 + (i % 4)
    local a = 0.25 * inter * fade
    love.graphics.setColor(1, 0.15, 0.15, a)
    love.graphics.rectangle("fill", -10, y, W, th)
    love.graphics.setColor(0.15, 0.6, 1, a)
    love.graphics.rectangle("fill", 10, y + th, W, th)
  end

  -- Static noise
  for i = 1, 260 do
    local x = (math.sin(t * 137 + i * 23) * 1000) % W
    local y = (math.cos(t * 89 + i * 17) * 1000) % H
    local a = 0.22 * inter * fade
    love.graphics.setColor(1, 1, 1, a)
    love.graphics.rectangle("fill", x, y, 1, 1)
  end

  -- Occasional bright scan line
  local scan_y = ((t * 380) % H)
  love.graphics.setColor(1, 1, 1, 0.35 * inter * fade)
  love.graphics.rectangle("fill", 0, scan_y, W, 2)

  -- The card: appears at 1.5s
  local card_p = math.max(0, math.min(1, (t - 1.5) / 0.7))
  if card_p <= 0 then return end
  local ease = 1 - (1 - card_p) ^ 3
  local cw, ch = 480, 190
  local scale = 0.7 + 0.3 * ease
  local rot = (1 - ease) * 0.15
  local ca = ease * fade

  love.graphics.push()
  love.graphics.translate(W/2, H/2)
  love.graphics.rotate(rot)
  love.graphics.scale(scale, scale)
  love.graphics.translate(-W/2, -H/2)

  local cx = (W - cw) / 2
  local cy = (H - ch) / 2

  -- Outer glow
  love.graphics.setColor(1, 0.4, 0.15, 0.35 * ca)
  love.graphics.rectangle("fill", cx - 8, cy - 8, cw + 16, ch + 16, 6, 6)

  -- Body: image background if available, else solid fill
  local box_img = A.image("assets/images/finalboutbox.png")
  if box_img then
    local iw, ih = box_img:getDimensions()
    local bsc = math.min(cw / iw, ch / ih)
    local dw, dh = iw * bsc, ih * bsc
    local bx = cx + (cw - dw) / 2
    local by = cy + (ch - dh) / 2
    love.graphics.setColor(1, 1, 1, 0.98 * ca)
    love.graphics.draw(box_img, bx, by, 0, bsc, bsc)
    love.graphics.setColor(1, 1, 1, 1)
  else
    love.graphics.setColor(0.02, 0.01, 0.01, 0.98 * ca)
    love.graphics.rectangle("fill", cx, cy, cw, ch, 4, 4)
  end

  -- Neon border
  love.graphics.setColor(1.0, 0.45, 0.15, 0.98 * ca)
  love.graphics.setLineWidth(3)
  love.graphics.rectangle("line", cx + 0.5, cy + 0.5, cw - 1, ch - 1, 4, 4)
  love.graphics.setLineWidth(1)
  love.graphics.setColor(1.0, 0.65, 0.3, 0.5 * ca)
  love.graphics.rectangle("line", cx + 6, cy + 6, cw - 12, ch - 12, 3, 3)

  D.corner_ticks(cx + 12, cy + 12, cw - 24, ch - 24, 16, {1, 0.5, 0.2}, ca)

  -- Flash bar at the top of the card
  love.graphics.setColor(1.0, 0.5, 0.2, 0.55 * ca)
  love.graphics.rectangle("fill", cx, cy, cw, 3)

  love.graphics.setColor(1.0, 0.6, 0.2, ca)
  love.graphics.setFont(A.font(A.FONT_MONO, 11))
  love.graphics.printf("// LIMIT BREAK PROTOCOL", 0, cy + 20, W, "center")

  love.graphics.setColor(1.0, 0.95, 0.85, ca)
  love.graphics.setFont(A.font(A.FONT_TITLE, 18))
  love.graphics.printf("You're now entering the", 0, cy + 46, W, "center")

  local fb_logo = A.image("assets/images/fblogo.png")
  if fb_logo then
    local lw_, lh_ = fb_logo:getDimensions()
    local target_h = 44
    local lsc = target_h / lh_
    local max_w = 420
    if lw_ * lsc > max_w then lsc = max_w / lw_ end
    local ldw = lw_ * lsc
    local ldx = (W - ldw) / 2
    local ldy = cy + 74 + (32 - target_h) / 2
    love.graphics.setColor(1, 1, 1, ca)
    love.graphics.draw(fb_logo, ldx, ldy, 0, lsc, lsc)
    love.graphics.setColor(1, 1, 1, 1)
  else
    love.graphics.setColor(1.0, 0.35, 0.15, ca)
    love.graphics.setFont(A.font(A.FONT_TITLE, 32))
    love.graphics.printf("FINAL BOUT", 0, cy + 74, W, "center")
  end

  love.graphics.setColor(1.0, 0.9, 0.55, ca)
  love.graphics.setFont(A.font(A.FONT_TITLE, 20))
  love.graphics.printf("Limit Break Dev Mode!!", 0, cy + 114, W, "center")

  love.graphics.setColor(0.92, 0.92, 0.88, ca * 0.9)
  love.graphics.setFont(A.font(A.FONT_BODY_BOLD, 11))
  love.graphics.printf("Extended Settings available", 0, cy + 150, W, "center")

  love.graphics.pop()

  -- Full-screen flash on card entry
  if card_p < 0.4 then
    local fa = (0.4 - card_p) / 0.4
    love.graphics.setColor(1, 0.5, 0.2, 0.45 * fa * fade)
    love.graphics.rectangle("fill", 0, 0, W, H)
  end
end

return M
