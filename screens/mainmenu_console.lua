-- mainmenu_console.lua -- industrial dashboard.
local A     = require("core.assets")
local State = require("core.state")
local Input = require("core.input_map")
local Frame = require("ui.frame")
local D     = require("ui.draw")
local sh    = require("core.sh")
local Modal = require("ui.modal")

local S = {}
local W, H = 640, 480
local AMB = {0.94, 0.66, 0.35}
local CYA = {0.48, 0.80, 0.90}
local PUR = {0.70, 0.55, 0.92}
local GRN = {0.55, 0.85, 0.45}
local RED = {0.95, 0.30, 0.25}
local GRY = {0.45, 0.45, 0.50}

local function col(c, a) love.graphics.setColor(c[1], c[2], c[3], a or 1) end

local _ct, _cv = {}, {}
local function cached(k, ttl, fn)
  local now = love.timer.getTime()
  if not _ct[k] or (now - _ct[k]) > ttl then _cv[k] = fn(); _ct[k] = now end
  return _cv[k]
end

local function read_line(p)
  local f = io.open(p, "r"); if not f then return nil end
  local v = f:read("*l"); f:close(); return v
end

local function get_uptime()
  return cached("up", 10, function()
    local s = read_line("/proc/uptime")
    if not s then return nil end
    return math.floor(tonumber(s:match("^(%d+)")) or 0)
  end)
end

local function get_temp()
  return cached("tp", 5, function()
    for i = 0, 4 do
      local v = tonumber(read_line("/sys/class/thermal/thermal_zone"..i.."/temp"))
      if v then if v > 1000 then v = v / 1000 end; return v end
    end
    return nil
  end)
end

local function scan_vols()
  local out = sh.read("df -kP 2>/dev/null")
  if not out then return {} end
  local seen, vols = {}, {}
  for line in out:gmatch("[^\n]+") do
    local d, _t, _u, a, _p, m = line:match("^(%S+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%%%s+(.+)$")
    if d and d:sub(1,5) == "/dev/" and not seen[m] then
      seen[m] = true
      vols[#vols+1] = { free = (tonumber(a) or 0) * 1024 }
    end
  end
  return vols
end

local function free_total()
  return cached("fr", 15, function()
    local s = 0
    for _, v in ipairs(scan_vols()) do s = s + v.free end
    return s
  end)
end

local function vol_count()
  return cached("vc", 15, function() return #scan_vols() end)
end

local function human_gb(n)
  if not n or n <= 0 then return "0 G" end
  local g = n / (1024*1024*1024)
  if g >= 1024 then return string.format("%.1fT", g/1024) end
  if g >= 100 then return string.format("%.0fG", g) end
  if g >= 10 then return string.format("%.1fG", g) end
  return string.format("%.2fG", g)
end

local function human_up(sec)
  if not sec then return "--" end
  local d = math.floor(sec/86400)
  local h = math.floor((sec%86400)/3600)
  local m = math.floor((sec%3600)/60)
  if d > 0 then return string.format("%dd %dh", d, h) end
  if h > 0 then return string.format("%dh %dm", h, m) end
  return string.format("%dm", m)
end

local function human_sess(sec)
  if not sec then return "--" end
  sec = math.floor(sec)
  local h = math.floor(sec/3600)
  local m = math.floor((sec%3600)/60)
  if h > 0 then return string.format("%dh %dm", h, m) end
  if m > 0 then return string.format("%dm %ds", m, sec%60) end
  return string.format("%ds", sec%60)
end

local focus = 0
local t = 0
local entering = false
local enter_t = 0

local CARDS = {
  { label = "SYSTEM",   sub = "diagnostics · cockpit", colour = CYA, target = "device" },
  { label = "PLUGINS",  sub = "store · launch",         colour = PUR, target = "plugins" },
  { label = "SETTINGS", sub = "interface · input",      colour = GRN, target = "settings" },
}

local PAD, GAP = 8, 6
local Y_HERO = Frame.TOP_H + PAD
local H_HERO = 110
local Y_NHDR = Y_HERO + H_HERO + GAP + 4
local Y_CARDS = Y_NHDR + 18
local H_CARDS = 120
local Y_SHDR = Y_CARDS + H_CARDS + 8
local Y_STAT = Y_SHDR + 18
local H_STAT = 56

function S.enter()  t = 0; entering = true; enter_t = 0; if not State._returning then focus = 0 end end
function S.leave() end
function S.update(dt)
  t = t + dt
  if entering then enter_t = enter_t + dt; if enter_t > 0.35 then entering = false end end
end

local function move(d)
  focus = (focus + d) % 4
  if focus < 0 then focus = focus + 4 end
  local ok, SFX = pcall(require, "core.audio")
  if ok and SFX.play then SFX.play("nav") end
end

local function quit_app()
  Modal.show("Close File-GD X", "Quit the application?",
    { accept_label = "QUIT", cancel_label = "CANCEL", accept_color = RED,
      on_accept = function() love.event.quit() end })
end

local function activate()
  local ok, SFX = pcall(require, "core.audio")
  if ok and SFX.play then SFX.play("enter") end
  if focus == 0 then State.go("filex_home")
  elseif CARDS[focus] then State.go(CARDS[focus].target) end
end

function S.pad(b)
  if Modal.is_open() then
    if b == Input.A then Modal.accept() elseif b == Input.B then Modal.cancel() end
    return
  end
  if b == Input.UP or b == Input.LEFT then move(-1)
  elseif b == Input.DOWN or b == Input.RIGHT then move(1)
  elseif b == Input.A then activate()
  elseif b == Input.B or b == Input.SELECT then quit_app() end
end

function S.hat(d)
  if Modal.is_open() then return end
  if d == "up" or d == "left" then move(-1)
  elseif d == "down" or d == "right" then move(1) end
end

function S.key(k)
  if Modal.is_open() then
    if k == "return" or k == "space" then Modal.accept()
    elseif k == "escape" then Modal.cancel() end
    return
  end
  if k == "up" or k == "left" then move(-1)
  elseif k == "down" or k == "right" then move(1)
  elseif k == "return" or k == "space" then activate()
  elseif k == "escape" then quit_app() end
end

local function draw_hero(x, y, w, h, foc)
  local acc = AMB
  local pulse = 0.6 + 0.4 * math.sin(t * 2.5)
  if foc then
    D.glow(x + w/2, y + h/2, w * 0.85, acc, 0.35 + 0.15 * pulse)
    col({acc[1]*0.14, acc[2]*0.14, acc[3]*0.14}, 0.98)
    love.graphics.rectangle("fill", x, y, w, h, 6, 6)
    col(acc, 0.95); love.graphics.setLineWidth(1.8)
    love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, 6, 6)
    love.graphics.setLineWidth(1)
    D.corner_ticks(x + 10, y + 10, w - 20, h - 20, 14, acc, 0.95)
    col(acc, 0.7 + 0.3 * pulse)
    love.graphics.rectangle("fill", x, y + 14, 4, h - 28, 2, 2)
  else
    col({0.024, 0.022, 0.030}, 0.92)
    love.graphics.rectangle("fill", x, y, w, h, 6, 6)
    col(acc, 0.32); love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, 6, 6)
  end
  local icx, icy, ir = x + 44, y + h/2, 30
  col({acc[1]*0.22, acc[2]*0.22, acc[3]*0.22}, 0.95)
  love.graphics.circle("fill", icx, icy, ir)
  col(acc, foc and 0.95 or 0.55)
  love.graphics.setLineWidth(foc and 1.8 or 1.2)
  love.graphics.circle("line", icx, icy, ir)
  love.graphics.setLineWidth(1)
  col(acc, foc and 1 or 0.8); love.graphics.setLineWidth(2)
  local fw, fh = ir*0.85, ir*0.62
  love.graphics.rectangle("line", icx - fw/2, icy - fh/2, fw, fh, 2, 2)
  love.graphics.rectangle("fill", icx - fw/2, icy - fh/2 - 4, fw*0.42, 4, 1, 1)
  love.graphics.setLineWidth(1)
  love.graphics.setFont(A.font(A.FONT_TITLE, foc and 20 or 19))
  col(foc and {1,1,1} or State.theme.text, 1)
  love.graphics.print("FILE XPLORER", icx + ir + 16, y + 14)
  love.graphics.setFont(A.font(A.FONT_BODY, 11))
  col(State.theme.text_dim, 0.85)
  love.graphics.print("browse, manage, open files on every volume", icx + ir + 16, y + 40)
  love.graphics.setFont(A.font(A.FONT_MONO, 10))
  col(acc, foc and 0.95 or 0.65)
  love.graphics.print(string.format("%d volumes  ·  %s free",
    vol_count() or 0, human_gb(free_total() or 0)), icx + ir + 16, y + 62)
  love.graphics.setFont(A.font(A.FONT_MONO, 9))
  col(State.theme.text_dim, 0.55)
  love.graphics.print("SD1 · SD2 · USB · ROOT", icx + ir + 16, y + 80)
  if foc then
    local ax, ay = x + w - 34, y + h/2
    local off = math.sin(t * 5) * 2
    col(acc, 0.9); love.graphics.setLineWidth(2.5)
    love.graphics.line(ax - 8 + off, ay - 9, ax + 2 + off, ay, ax - 8 + off, ay + 9)
    love.graphics.setLineWidth(1)
  end
end

local function draw_card(x, y, w, h, card, foc)
  local acc = card.colour
  local pulse = 0.6 + 0.4 * math.sin(t * 3)
  if foc then
    D.glow(x + w/2, y + h/2, w * 0.85, acc, 0.35 + 0.15 * pulse)
    col({acc[1]*0.16, acc[2]*0.16, acc[3]*0.16}, 0.98)
    love.graphics.rectangle("fill", x, y, w, h, 5, 5)
    col(acc, 0.95); love.graphics.setLineWidth(1.7)
    love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, 5, 5)
    love.graphics.setLineWidth(1)
    D.corner_ticks(x + 8, y + 8, w - 16, h - 16, 10, acc, 0.95)
    col(acc, 0.7 + 0.3 * pulse)
    love.graphics.rectangle("fill", x, y + 12, 3, h - 24, 1, 1)
  else
    col({0.024, 0.022, 0.030}, 0.92)
    love.graphics.rectangle("fill", x, y, w, h, 5, 5)
    col(acc, 0.30); love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, 5, 5)
  end
  local icx, icy, ir = x + w/2, y + 38, 22
  col({acc[1]*0.22, acc[2]*0.22, acc[3]*0.22}, 0.95)
  love.graphics.circle("fill", icx, icy, ir)
  col(acc, foc and 0.95 or 0.55)
  love.graphics.setLineWidth(foc and 1.5 or 1)
  love.graphics.circle("line", icx, icy, ir)
  love.graphics.setLineWidth(1)
  col(acc, foc and 1 or 0.75); love.graphics.setLineWidth(1.8)
  if card.label == "SYSTEM" then
    love.graphics.circle("line", icx, icy, ir*0.42)
    love.graphics.line(icx, icy - ir*0.62, icx, icy - ir*0.30)
    love.graphics.circle("fill", icx, icy, ir*0.14)
  elseif card.label == "PLUGINS" then
    love.graphics.rectangle("line", icx - ir*0.42, icy - ir*0.12, ir*0.84, ir*0.55, 2, 2)
    love.graphics.line(icx - ir*0.20, icy - ir*0.12, icx - ir*0.20, icy - ir*0.55)
    love.graphics.line(icx + ir*0.20, icy - ir*0.12, icx + ir*0.20, icy - ir*0.55)
  else
    for i = 0, 7 do
      local a = i * math.pi / 4
      love.graphics.line(icx + math.cos(a)*ir*0.40, icy + math.sin(a)*ir*0.40,
                         icx + math.cos(a)*ir*0.62, icy + math.sin(a)*ir*0.62)
    end
    love.graphics.circle("line", icx, icy, ir*0.40)
    love.graphics.circle("line", icx, icy, ir*0.15)
  end
  love.graphics.setLineWidth(1)
  love.graphics.setFont(A.font(A.FONT_BODY_BOLD, foc and 14 or 13))
  col(foc and {1,1,1} or State.theme.text, 1)
  love.graphics.printf(card.label, x, y + 66, w, "center")
  love.graphics.setFont(A.font(A.FONT_MONO, 8))
  col(State.theme.text_dim, foc and 0.85 or 0.6)
  love.graphics.printf(card.sub, x, y + 88, w, "center")
end

local function draw_tile(x, y, w, h, label, value, acc)
  col({0.022, 0.022, 0.028}, 0.85)
  love.graphics.rectangle("fill", x, y, w, h, 4, 4)
  col(acc, 0.32); love.graphics.setLineWidth(1)
  love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, 4, 4)
  love.graphics.setLineWidth(1)
  love.graphics.setFont(A.font(A.FONT_MONO, 8))
  col(acc, 0.80); love.graphics.print(label, x + 8, y + 6)
  love.graphics.setFont(A.font(A.FONT_BODY_BOLD, 13))
  col({1,1,1}, 1); love.graphics.print(value, x + 8, y + 22)
end

function S.draw()
  D.bg()
  local th = State.theme
  col(th.grid_faint, 0.07)
  for gy = Frame.TOP_H, H - Frame.BOTTOM_H, 16 do
    for gx = 0, W, 16 do love.graphics.rectangle("fill", gx, gy, 1, 1) end
  end
  D.corner_ticks(PAD, Frame.TOP_H + 4, W - 2*PAD,
    H - Frame.TOP_H - Frame.BOTTOM_H - 8, 18, CYA, 0.25)

  local ease = 1
  if entering then
    local p = math.min(1, enter_t / 0.35)
    ease = 1 - (1 - p) * (1 - p) * (1 - p)
  end
  love.graphics.push()
  love.graphics.translate(0, (1 - ease) * 20)

  draw_hero(PAD, Y_HERO, W - 2*PAD, H_HERO, focus == 0)

  love.graphics.setFont(A.font(A.FONT_MONO, 10))
  col(CYA, 0.85); love.graphics.print("NAVIGATE", PAD + 4, Y_NHDR + 2)
  col(CYA, 0.30); love.graphics.rectangle("fill", PAD + 4, Y_NHDR + 15, W - 2*PAD - 8, 1)

  local n = #CARDS
  local tw = math.floor((W - 2*PAD - (n - 1)*GAP) / n)
  for i = 1, n do
    local w_this = (i == n) and (W - PAD - (PAD + (i-1)*(tw+GAP))) or tw
    local x = PAD + (i - 1) * (tw + GAP)
    draw_card(x, Y_CARDS, w_this, H_CARDS, CARDS[i], focus == i)
  end

  love.graphics.setFont(A.font(A.FONT_MONO, 10))
  col(GRY, 0.85); love.graphics.print("STATUS", PAD + 4, Y_SHDR + 2)
  col(GRY, 0.25); love.graphics.rectangle("fill", PAD + 4, Y_SHDR + 15, W - 2*PAD - 8, 1)

  local up = get_uptime()
  local tp = get_temp()
  local fr = free_total()
  local tiles = {
    { label = "UPTIME",  value = human_up(up), acc = CYA },
    { label = "SESSION", value = human_sess(State.t_ui or 0), acc = PUR },
    { label = "STORAGE", value = human_gb(fr) .. " free", acc = GRN },
    { label = "TEMP",    value = tp and string.format("%.0f°C", tp) or "--",
      acc = (tp and tp >= 70) and RED or AMB },
  }
  n = #tiles
  tw = math.floor((W - 2*PAD - (n-1)*GAP) / n)
  for i = 1, n do
    local w_this = (i == n) and (W - PAD - (PAD + (i-1)*(tw+GAP))) or tw
    local x = PAD + (i - 1) * (tw + GAP)
    draw_tile(x, Y_STAT, w_this, H_STAT, tiles[i].label, tiles[i].value, tiles[i].acc)
  end

  love.graphics.pop()

  Frame.draw_top("FGD", "mainmenu")
  Frame.draw_bottom({
    { key = "dpad", label = "Navigate" },
    { key = "a",    label = "Enter" },
    { key = "b",    label = "Quit" },
    { key = "l2",   label = "View" },
  })
  Modal.draw()
  D.scanlines(W, H, 0.06)
  D.vignette(W, H, 0.55)
end

return S
