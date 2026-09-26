-- mainmenu_finalbout.lua -- fedele al menu di Dragon Ball GT: Final Bout.
-- Layout: logo in alto, 4 riquadri selezionabili in basso.
-- Voci: BATTLE / TOURNAMENT / BUILD UP / OPTIONS
-- Adattate per il file manager.
local A     = require("core.assets")
local State = require("core.state")
local Input = require("core.input_map")
local Frame = require("ui.frame")
local D     = require("ui.draw")
local Modal = require("ui.modal")

local S = {}
local W, H = 640, 480

-- Palette Final Bout: blu profondo, oro, arancio
local ORO  = {0.98, 0.78, 0.20}
local ARA  = {0.98, 0.48, 0.10}
local RED  = {0.95, 0.25, 0.20}
local CYA  = {0.30, 0.85, 0.95}
local VERDE= {0.35, 0.90, 0.45}
local BLU  = {0.20, 0.40, 0.85}

local function col(c, a) love.graphics.setColor(c[1], c[2], c[3], a or 1) end

-- 4 voci esatte come Final Bout, adattate al file manager
local ITEMS = {
  { key = "BATTLE",      sub = "file explorer",    target = "filex_home",
    colour = ORO, icon = "battle" },
  { key = "TOURNAMENT",  sub = "system cockpit",   target = "device",
    colour = CYA, icon = "tournament" },
  { key = "BUILD UP",    sub = "storage & cleanup", target = "storage",
    colour = VERDE, icon = "buildup" },
  { key = "OPTIONS",     sub = "settings",         target = "settings",
    colour = RED, icon = "options" },
}
local N = #ITEMS

local sel = 1
local t = 0

function S.enter()
  sel = 1
  t = 0
  local ok, SFX = pcall(require, "core.audio")
  if ok and SFX.play then SFX.play("select2fb") end
end
function S.leave() end
function S.update(dt) t = t + dt end

local function move(d)
  sel = sel + d
  if sel < 1 then sel = N end
  if sel > N then sel = 1 end
  local ok, SFX = pcall(require, "core.audio")
  if ok and SFX.play then SFX.play("navfb") end
end

local function activate()
  local it = ITEMS[sel]
  if not it then return end
  local ok, SFX = pcall(require, "core.audio")
  if ok and SFX.play then SFX.play("selectfb") end
  if it.target then
    State.go(it.target)
  else
    Modal.show("FINAL BOUT", "Leave the arena?",
      { accept_label = "EXIT", cancel_label = "STAY",
        accept_color = RED,
        on_accept = function() love.event.quit() end })
  end
end

function S.pad(b)
  if Modal.is_open() then
    if b == Input.A then Modal.accept() elseif b == Input.B then Modal.cancel() end
    return
  end
  if b == Input.LEFT then move(-1)
  elseif b == Input.RIGHT then move(1)
  elseif b == Input.A then activate()
  elseif b == Input.B or b == Input.SELECT then
    local ok, SFX = pcall(require, "core.audio")
    if ok and SFX.play then SFX.play("backfb") end
    Modal.show("FINAL BOUT", "Leave the arena?",
      { accept_label = "EXIT", cancel_label = "STAY", accept_color = RED,
        on_accept = function() love.event.quit() end })
  end
end

function S.hat(d)
  if Modal.is_open() then return end
  if d == "left" then move(-1)
  elseif d == "right" then move(1) end
end

function S.key(k)
  if Modal.is_open() then
    if k == "return" then Modal.accept() elseif k == "escape" then Modal.cancel() end
    return
  end
  if k == "left" then move(-1)
  elseif k == "right" then move(1)
  elseif k == "return" or k == "space" then activate()
  elseif k == "escape" then S.pad(Input.B) end
end

-- Icone dei 4 riquadri, ispirate a Final Bout
local function draw_icon(kind, cx, cy, r, c, a)
  col(c, a or 1)
  love.graphics.setLineWidth(2)
  if kind == "battle" then
    -- Due pugni che si scontrano (semplificato)
    love.graphics.rectangle("line", cx - r*0.7, cy - r*0.4, r*0.6, r*0.8, 2, 2)
    love.graphics.rectangle("line", cx + r*0.1, cy - r*0.4, r*0.6, r*0.8, 2, 2)
    love.graphics.line(cx - r*0.1, cy, cx + r*0.1, cy)
  elseif kind == "tournament" then
    -- Edificio/tempio
    love.graphics.rectangle("line", cx - r*0.6, cy - r*0.2, r*1.2, r*0.7, 2, 2)
    love.graphics.polygon("line",
      cx - r*0.8, cy - r*0.2,
      cx, cy - r*0.8,
      cx + r*0.8, cy - r*0.2)
  elseif kind == "buildup" then
    -- Barre di potenziamento
    love.graphics.rectangle("line", cx - r*0.6, cy + r*0.2, r*1.2, r*0.2, 1, 1)
    love.graphics.rectangle("line", cx - r*0.6, cy - r*0.1, r*0.8, r*0.2, 1, 1)
    love.graphics.rectangle("line", cx - r*0.6, cy - r*0.4, r*0.4, r*0.2, 1, 1)
  elseif kind == "options" then
    -- Punto interrogativo
    love.graphics.circle("line", cx, cy, r*0.7)
    love.graphics.setFont(A.font(A.FONT_TITLE, math.floor(r*1.2)))
    love.graphics.printf("?", cx - r*0.5, cy - r*0.5, r, "center")
  end
  love.graphics.setLineWidth(1)
end

-- Sfondo blu profondo con alone
local function draw_bg()
  D.bg()
  col({0.02, 0.02, 0.10}, 1)
  love.graphics.rectangle("fill", 0, 0, W, H)
  for i = 5, 1, -1 do
    col({BLU[1], BLU[2], BLU[3]}, 0.04 / i)
    love.graphics.circle("fill", W/2, H/2, 200 + i * 60)
  end
end

-- Logo stile Final Bout
local function draw_logo()
  local y = Frame.TOP_H + 18
  local cx = W/2
  local pulse = 0.85 + 0.15 * math.sin(t * 3)
  D.glow(cx, y + 22, 180, ORO, 0.5 * pulse)
  love.graphics.setFont(A.font(A.FONT_TITLE, 34))
  col({0,0,0}, 0.8)
  love.graphics.printf("FINAL BOUT", 2, y + 2, W, "center")
  col(ORO, 1)
  love.graphics.printf("FINAL BOUT", 0, y, W, "center")
  love.graphics.setFont(A.font(A.FONT_MONO, 10))
  col(ARA, 0.85)
  love.graphics.printf("~ FILE MANAGER EDITION ~", 0, y + 42, W, "center")
end

-- 4 riquadri in basso
local function draw_quadrants()
  local qw = 110
  local qh = 110
  local gap = 20
  local total_w = 4 * qw + 3 * gap
  local x0 = (W - total_w) / 2
  local y = H - Frame.BOTTOM_H - qh - 40

  for i, it in ipairs(ITEMS) do
    local x = x0 + (i - 1) * (qw + gap)
    local focused = (i == sel)
    local c = it.colour

    if focused then
      D.glow(x + qw/2, y + qh/2, qw * 1.2, c, 0.6)
      col({c[1]*0.25, c[2]*0.25, c[3]*0.25}, 0.95)
      love.graphics.rectangle("fill", x, y, qw, qh, 6, 6)
      col(c, 1)
      love.graphics.setLineWidth(2.5)
      love.graphics.rectangle("line", x + 0.5, y + 0.5, qw - 1, qh - 1, 6, 6)
      love.graphics.setLineWidth(1)
      -- angoli in stile arcade
      col(c, 0.95)
      for _, p in ipairs({{x,y},{x+qw-8,y},{x,y+qh-8},{x+qw-8,y+qh-8}}) do
        love.graphics.rectangle("fill", p[1], p[2], 8, 8)
      end
    else
      col({0.04, 0.04, 0.12}, 0.9)
      love.graphics.rectangle("fill", x, y, qw, qh, 6, 6)
      col(c, 0.35)
      love.graphics.rectangle("line", x + 0.5, y + 0.5, qw - 1, qh - 1, 6, 6)
    end

    -- icona grande
    draw_icon(it.icon, x + qw/2, y + qh/2 - 8, 28, c, focused and 1 or 0.7)

    -- etichetta
    love.graphics.setFont(A.font(A.FONT_BODY_BOLD, focused and 14 or 12))
    col(focused and {1,1,1} or State.theme.text, 1)
    love.graphics.printf(it.key, x, y + qh - 22, qw, "center")
  end
end

function S.draw()
  draw_bg()
  draw_logo()
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

return S
