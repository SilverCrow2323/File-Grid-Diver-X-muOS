-- screens/mainmenu_finalbout.lua -- fedele al menu di DB GT: Final Bout (PS1).
-- Layout: sfondo FB, logo in alto, 4 riquadri in basso.
-- Voci: BATTLE / TOURNAMENT / BUILD UP / OPTIONS
local A     = require("core.assets")
local State = require("core.state")
local Input = require("core.input_map")
local Frame = require("ui.frame")
local D     = require("ui.draw")
local Modal = require("ui.modal")

local S = {}
local W, H = 640, 480

-- Palette Final Bout
local ORO  = {0.98, 0.78, 0.20}
local ARA  = {0.98, 0.48, 0.10}
local RED  = {0.95, 0.25, 0.20}
local CYA  = {0.30, 0.85, 0.95}
local VERDE= {0.35, 0.90, 0.45}

local function col(c, a) love.graphics.setColor(c[1], c[2], c[3], a or 1) end

local ITEMS = {
  { key = "BATTLE",     sub = "file explorer",     target = "filex_home", colour = ORO,  icon = "battle" },
  { key = "TOURNAMENT", sub = "system cockpit",    target = "device",     colour = CYA,  icon = "tournament" },
  { key = "BUILD UP",   sub = "storage & cleanup", target = "storage",    colour = VERDE,icon = "buildup" },
  { key = "OPTIONS",    sub = "settings",          target = "settings",   colour = RED,  icon = "options" },
}
local N = #ITEMS

local sel = 1
local t = 0
local quad_anim = { t = 0, started = {} }

local function play_sfx(name)
  local ok, SFX = pcall(require, "core.audio")
  if ok and SFX.play then SFX.play(name) end
end

function S.enter() sel = 1; t = 0; play_sfx("fb/select2fb") end
function S.leave() end
function S.update(dt)
  t = t + dt
  quad_anim.t = quad_anim.t + dt
  for i = 1, N do
    local start_t = (i - 1) * 0.12
    if not quad_anim.started[i] and quad_anim.t >= start_t then
      quad_anim.started[i] = true
      local ok, SFX = pcall(require, "core.audio")
      if ok and SFX.play then SFX.play("fb/nav2fb") end
    end
  end
end

local function move(d)
  sel = sel + d
  if sel < 1 then sel = N end
  if sel > N then sel = 1 end
  play_sfx("fb/navfb")
end

local function quit_dialog()
  Modal.show("FINAL BOUT", "Leave the arena?",
    { accept_label = "EXIT", cancel_label = "STAY", accept_color = RED,
      on_accept = function() love.event.quit() end })
end

local function activate()
  local it = ITEMS[sel]
  if not it then return end
  play_sfx("finalbout")
  if it.target then
    State.go(it.target)
  else
    quit_dialog()
  end
end

function S.pad(b)
  if Modal.is_open() then
    if b == Input.A then Modal.accept()
    elseif b == Input.B then Modal.cancel() end
    return
  end
  if b == Input.LEFT  then move(-1)
  elseif b == Input.RIGHT then move(1)
  elseif b == Input.A then activate()
  elseif b == Input.B or b == Input.SELECT then quit_dialog() end
end

function S.hat(d)
  if Modal.is_open() then return end
  if d == "left" then move(-1)
  elseif d == "right" then move(1) end
end

function S.key(k)
  if Modal.is_open() then
    if k == "return" then Modal.accept()
    elseif k == "escape" then Modal.cancel() end
    return
  end
  if k == "left" then move(-1)
  elseif k == "right" then move(1)
  elseif k == "return" or k == "space" then activate()
  elseif k == "escape" then quit_dialog() end
end

-- Sfondo: FB bg/menuN.png a rotazione, o colore solido di fallback
local function draw_bg()
  local tnow = love.timer.getTime()
  local frames = { "menu1", "menu2", "menu4" }
  local idx = (math.floor(tnow / 8) % #frames) + 1
  local path = "assets/images/fb/bg/" .. frames[idx] .. ".png"
  local img = A.image(path)
  if img then
    local iw, ih = img:getDimensions()
    local sc = math.max(W / iw, H / ih)
    local dw, dh = iw * sc, ih * sc
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(img, (W - dw) / 2, (H - dh) / 2, 0, sc, sc)
    -- overlay scuro per leggibilita'
    love.graphics.setColor(0, 0, 0, 0.45)
    love.graphics.rectangle("fill", 0, 0, W, H)
    love.graphics.setColor(1, 1, 1, 1)
  else
    -- fallback blu profondo Final Bout
    love.graphics.clear(0.02, 0.02, 0.10, 1)
    for i = 5, 1, -1 do
      col({0.20, 0.40, 0.85}, 0.04 / i)
      love.graphics.circle("fill", W/2, H/2, 200 + i * 60)
    end
  end
end

-- Icona dei 4 riquadri
local function draw_icon(kind, cx, cy, r, c, a)
  col(c, a or 1)
  love.graphics.setLineWidth(2)
  if kind == "battle" then
    love.graphics.rectangle("line", cx - r*0.7, cy - r*0.4, r*0.6, r*0.8, 2, 2)
    love.graphics.rectangle("line", cx + r*0.1, cy - r*0.4, r*0.6, r*0.8, 2, 2)
    love.graphics.line(cx - r*0.1, cy, cx + r*0.1, cy)
  elseif kind == "tournament" then
    love.graphics.rectangle("line", cx - r*0.6, cy - r*0.2, r*1.2, r*0.7, 2, 2)
    love.graphics.polygon("line",
      cx - r*0.8, cy - r*0.2,
      cx, cy - r*0.8,
      cx + r*0.8, cy - r*0.2)
  elseif kind == "buildup" then
    love.graphics.rectangle("line", cx - r*0.6, cy + r*0.2, r*1.2, r*0.2, 1, 1)
    love.graphics.rectangle("line", cx - r*0.6, cy - r*0.1, r*0.8, r*0.2, 1, 1)
    love.graphics.rectangle("line", cx - r*0.6, cy - r*0.4, r*0.4, r*0.2, 1, 1)
  elseif kind == "options" then
    love.graphics.circle("line", cx, cy, r*0.7)
    love.graphics.setFont(A.font(A.FONT_TITLE, math.floor(r*1.1)))
    love.graphics.printf("?", cx - r*0.5, cy - r*0.5, r, "center")
  end
  love.graphics.setLineWidth(1)
end

-- 4 riquadri in basso
local function draw_quadrants()
  local qw = 110
  local qh = 110
  local gap = 20
  local total_w = 4 * qw + 3 * gap
  local x0 = (W - total_w) / 2
  local y = H - Frame.BOTTOM_H - qh - 40

  local bg_img = A.image("assets/images/fb/bg/bg.png")

  for i, it in ipairs(ITEMS) do
    local start_t = (i - 1) * 0.12
    local p = 0
    if quad_anim.t >= start_t then
      p = math.min(1, (quad_anim.t - start_t) / 0.25)
      p = 1 - (1 - p) ^ 3
    end
    local x = x0 + (i - 1) * (qw + gap) + (1 - p) * (W + 200)
    local focused = (i == sel)
    local c = it.colour

    if focused then
      D.glow(x + qw/2, y + qh/2, qw * 1.2, c, 0.6)
    end

    -- sfondo: bg.png clippata dentro il quadrato
    love.graphics.setScissor(x, y, qw, qh)
    if bg_img then
      local iw, ih = bg_img:getDimensions()
      local sc = math.max(qw / iw, qh / ih)
      local dw, dh = iw * sc, ih * sc
      love.graphics.setColor(1, 1, 1, focused and 0.85 or 0.55)
      love.graphics.draw(bg_img, x + (qw - dw) / 2, y + (qh - dh) / 2, 0, sc, sc)
      love.graphics.setColor(1, 1, 1, 1)
    else
      if focused then
        col({c[1]*0.25, c[2]*0.25, c[3]*0.25}, 0.95)
      else
        col({0.04, 0.04, 0.12}, 0.9)
      end
      love.graphics.rectangle("fill", x, y, qw, qh, 6, 6)
    end
    love.graphics.setScissor()

    if focused then
      col(c, 1)
      love.graphics.setLineWidth(2.5)
      love.graphics.rectangle("line", x + 0.5, y + 0.5, qw - 1, qh - 1, 6, 6)
      love.graphics.setLineWidth(1)
      col(c, 0.95)
      for _, pp in ipairs({{x,y},{x+qw-8,y},{x,y+qh-8},{x+qw-8,y+qh-8}}) do
        love.graphics.rectangle("fill", pp[1], pp[2], 8, 8)
      end
    else
      col(c, 0.35)
      love.graphics.rectangle("line", x + 0.5, y + 0.5, qw - 1, qh - 1, 6, 6)
    end

    draw_icon(it.icon, x + qw/2, y + qh/2 - 8, 28, c, focused and 1 or 0.7)

    love.graphics.setFont(A.font(A.FONT_BODY_BOLD, focused and 14 or 12))
    col(focused and {1,1,1} or State.theme.text, 1)
    love.graphics.printf(it.key, x, y + qh - 22, qw, "center")
  end
end

function S.draw()
  draw_bg()
  -- draw_logo() rimosso: logo/scritta sono già nella PNG di sfondo
  draw_quadrants()

  Frame.draw_top("FGD", "mainmenu")
  Frame.draw_bottom({
    { key = "l/r", label = "Select" },
    { key = "a",   label = "Enter"  },
    { key = "b",   label = "Exit"   },
    { key = "l2",  label = "View"   },
  })
  Modal.draw()
  D.scanlines(W, H, 0.08)
  D.vignette(W, H, 0.65)
end

function S.override_sfx(name)
  if name == "a" then return true end
  return false
end

return S
