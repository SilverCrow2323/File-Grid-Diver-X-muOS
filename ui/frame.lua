-- ui/frame.lua -- top bar and bottom bar for File-GD X.
-- Header / footer thicknesses and their fonts are controlled by
-- settings (ui.header_h, ui.footer_h) and DO NOT scale with the
-- global font_scale. Call F.sync() every frame from love.update.

local A     = require("core.assets")
local BI    = require("ui.button_icons")
local D     = require("ui.draw")
local State = require("core.state")

local F = {}
F.TOP_H    = 48
F.BOTTOM_H = 40

local function read_setting(key, default)
  local ok, Store = pcall(require, "core.settings_store")
  if ok then
    local v = Store.get("ui", key)
    if v then return v end
  end
  return default
end

function F.sync()
  F.TOP_H    = read_setting("header_h", 48)
  F.BOTTOM_H = read_setting("footer_h", 40)
  -- Publish as globals so any screen (even one loaded earlier) can
  -- read fresh values without caching its own local copy.
  TOP_H    = F.TOP_H
  BOTTOM_H = F.BOTTOM_H
end
F.sync()  -- run once at load, so the globals exist immediately


local function ui_flag(key, default)
  local ok, Store = pcall(require, "core.settings_store")
  if ok then
    local v = Store.get("ui", key)
    if v ~= nil then return v end
  end
  return default
end

local TITLES = {
  boot = "FILE GRID DIVER", mainmenu = "FILE GRID DIVER",
  grid = "FILE MANAGER", editor = "TEXT EDITOR",
  image_viewer = "IMAGE VIEWER", search = "SEARCH",
  settings = "SETTINGS", log = "LOG", about = "ABOUT",
  pad_test = "PAD TEST", operations = "OPERATIONS",
  disk_tools = "DISK TOOLS", device = "SYSTEM",
  plugins = "PLUGINS", input_investigation = "INPUT HOLMES",
  grid_dev = "GRID-DEV",
  storage = "STORAGE",
  help = "GUIDE",
}

-- ===== telemetry =====
local _bat_v, _bat_t = nil, -999
local _wifi_v, _wifi_t = -1, -999
local _clock, _clock_t = "", -999
local _mem_v, _mem_t = nil, -999

local function now_t()
  if love and love.timer then return love.timer.getTime() end
  return os.time()
end
local function read_line(p)
  local f = io.open(p, "r"); if not f then return nil end
  local v = f:read("*l"); f:close(); return v
end

local function read_battery()
  local t = now_t(); if t - _bat_t < 10 then return _bat_v end
  _bat_t = t; _bat_v = nil
  for _, p in ipairs({
    "/sys/class/power_supply/battery/capacity",
    "/sys/class/power_supply/BAT0/capacity",
    "/sys/class/power_supply/BAT1/capacity",
  }) do
    local v = tonumber(read_line(p)); if v then _bat_v = v; break end
  end
  return _bat_v
end

local function read_wifi()
  local t = now_t(); if t - _wifi_t < 10 then return _wifi_v end
  _wifi_t = t; _wifi_v = 0
  local h = io.popen("ls /sys/class/net/ 2>/dev/null")
  if h then
    for name in h:lines() do
      if name:match("^wl") then
        local c = read_line("/sys/class/net/" .. name .. "/carrier")
        if c == "1" then _wifi_v = 2 end
        break
      end
    end
    h:close()
  end
  return _wifi_v
end

local function read_clock()
  local t = now_t(); if t - _clock_t < 1 then return _clock end
  _clock_t = t; _clock = os.date("%H:%M:%S"); return _clock
end

local function read_mem_pct()
  local t = now_t(); if t - _mem_t < 10 then return _mem_v end
  _mem_t = t; _mem_v = nil
  local f = io.open("/proc/meminfo", "r"); if not f then return nil end
  local total, avail = 0, 0
  for line in f:lines() do
    local k, v = line:match("^(%w+):%s+(%d+)")
    if k == "MemTotal" then total = tonumber(v) or 0
    elseif k == "MemAvailable" then avail = tonumber(v) or 0 end
  end
  f:close()
  if total <= 0 then return nil end
  _mem_v = math.floor((1 - avail / total) * 100 + 0.5)
  return _mem_v
end

-- ===== primitives =====
local function irregular_rim(cx, cy, r, thickness, seed)
  local N = 26; local pts = {}
  for i = 0, N - 1 do
    local a = (i / N) * math.pi * 2
    local n = (math.sin((seed or 1) + i * 12.9898) * 43758.5453) % 1
    local rr = r + (n - 0.5) * 1.6
    pts[#pts+1] = cx + math.cos(a) * rr
    pts[#pts+1] = cy + math.sin(a) * rr
  end
  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.setLineWidth(thickness)
  love.graphics.polygon("line", pts)
  love.graphics.setLineWidth(1)
end

local function plaque_circle(cx, cy, r, seed)
  irregular_rim(cx, cy, r, 5, seed)
  irregular_rim(cx, cy, r + 1, 3, (seed or 1) + 11)
  love.graphics.setColor(0.055, 0.05, 0.045, 1)
  love.graphics.circle("fill", cx, cy, r)
  love.graphics.setColor(0.16, 0.15, 0.14, 0.9)
  love.graphics.setLineWidth(1.4)
  love.graphics.circle("line", cx, cy, r - 3)
  love.graphics.setLineWidth(1)
end

local function plaque_rect(x, y, w, h, r)
  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.setLineWidth(5)
  love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, r, r)
  love.graphics.setLineWidth(3)
  love.graphics.rectangle("line", x - 0.5, y - 0.5, w + 1, h + 1, r, r)
  love.graphics.setLineWidth(1)
  love.graphics.setColor(0.055, 0.05, 0.045, 1)
  love.graphics.rectangle("fill", x, y, w, h, r, r)
  love.graphics.setColor(0.16, 0.15, 0.14, 0.9)
  love.graphics.setLineWidth(1.2)
  love.graphics.rectangle("line", x + 2, y + 2, w - 4, h - 4, r - 1, r - 1)
  love.graphics.setLineWidth(1)
end

-- ===== badges =====
local BADGE = {
  a = { label = "A", col = {0.90, 0.30, 0.30} },
  b = { label = "B", col = {0.30, 0.55, 0.95} },
  x = { label = "X", col = {0.30, 0.75, 0.40} },
  y = { label = "Y", col = {0.95, 0.80, 0.20} },
  l1 = { label = "L1", col = {0.55, 0.55, 0.60} },
  r1 = { label = "R1", col = {0.55, 0.55, 0.60} },
  l2 = { label = "L2", col = {0.45, 0.45, 0.55} },
  r2 = { label = "R2", col = {0.45, 0.45, 0.55} },
  l3 = { label = "L3", col = {0.40, 0.40, 0.50} },
  r3 = { label = "R3", col = {0.40, 0.40, 0.50} },
  start = { label = "ST", col = {0.35, 0.40, 0.55} },
  select = { label = "SE", col = {0.35, 0.40, 0.55} },
  dpad = { label = "D", col = {0.30, 0.35, 0.45} },
  dpup = { label = "D+", col = {0.30, 0.35, 0.45} },
  dpdown = { label = "D-", col = {0.30, 0.35, 0.45} },
  dpleft = { label = "D<", col = {0.30, 0.35, 0.45} },
  dpright = { label = "D>", col = {0.30, 0.35, 0.45} },
  volup = { label = "V+", col = {0.60, 0.55, 0.40} },
  voldown = { label = "V-", col = {0.60, 0.55, 0.40} },
  m = { label = "M", col = {0.55, 0.40, 0.55} },
  spc = { label = "*", col = {0.60, 0.55, 0.40} },
  any = { label = "*", col = {0.60, 0.55, 0.40} },
  tab = { label = "T", col = {0.45, 0.40, 0.55} },
  ctrl = { label = "C", col = {0.55, 0.45, 0.35} },
  default = { label = "?", col = {0.45, 0.42, 0.38} },
}

local function normalize_key(key)
  key = (key or ""):lower()
  if key == "up/dn" or key == "d-pad" or key == "dpad" then return "dpad" end
  if key == "l1/r1" or key == "l/r" then return "dpad" end
  if key == "l2/r2" then return "dpad" end
  if key == "st" then return "start" end
  if key == "sel" then return "select" end
  if key == "spc" then return "spc" end
  if key:match("^c%+") or key:match("^ctrl") then return "ctrl" end
  return key:gsub("[^%w]", "")
end

function F.draw_badge(cx, cy, r, key)
  -- Delegate to the centralized button icon renderer.
  BI.draw(cx, cy, r, key)
end


-- ===== device drawers =====
local function draw_clock_device(cx, cy, r)
  plaque_circle(cx, cy, r, 3)
  love.graphics.setFont(A.font_raw(A.FONT_MONO, 12))
  love.graphics.setColor(0.55, 0.86, 0.95, 1)
  local s = read_clock()
  local w = love.graphics.getFont():getWidth(s)
  love.graphics.print(s, cx - w/2, cy - 7)
end

local function draw_wifi_device(x, y, w, h)
  plaque_rect(x, y, w, h, 6)
  local strength = read_wifi() or 0
  love.graphics.setFont(A.font_raw(A.FONT_BODY_BOLD, 11))
  if strength > 0 then love.graphics.setColor(0.96,0.96,0.92,1)
  else                love.graphics.setColor(0.28,0.27,0.24,1) end
  love.graphics.print("WIFI", x + 8, y + h/2 - 8)

  local bx = x + 42; local by = y + h - 8
  for i = 1, 4 do
    local bh = 3 + (i - 1) * 11 / 3
    local on = (i <= strength)
    local col
    if on then
      local t = 1 - (i - 1) / 3
      col = {0.30 + 0.45 * (1 - t), 0.85 - 0.15 * (1 - t), 0.30}
    else col = {0.10, 0.10, 0.09} end
    love.graphics.setColor(col[1], col[2], col[3], 1)
    love.graphics.rectangle("fill", bx + (i - 1) * 5, by - bh, 3, bh)
  end

  local lx, ly = x + w - 8, y + 6
  if strength > 0 then
    love.graphics.setColor(0.30, 0.92, 0.40, 0.35); love.graphics.circle("fill", lx, ly, 5)
    love.graphics.setColor(0.60, 1.0, 0.60, 1);   love.graphics.circle("fill", lx, ly, 2.4)
  else
    love.graphics.setColor(0.92, 0.15, 0.10, 0.35); love.graphics.circle("fill", lx, ly, 5)
    love.graphics.setColor(1.0, 0.30, 0.22, 1);   love.graphics.circle("fill", lx, ly, 2.4)
  end
end

local function draw_battery_device(x, y, w, h)
  plaque_rect(x, y, w, h, 6)
  love.graphics.setFont(A.font_raw(A.FONT_BODY_BOLD, 11))
  love.graphics.setColor(0.92, 0.92, 0.88, 1)
  love.graphics.print("BATT", x + 8, y + h/2 - 8)

  local pct = read_battery()
  if not pct then
    love.graphics.setColor(0.35, 0.33, 0.30, 1)
    love.graphics.print("--", x + w - 26, y + h/2 - 6)
    return
  end
  local bx, by = x + 42, y + h/2 - 6
  love.graphics.setColor(0.75, 0.74, 0.70, 1)
  love.graphics.setLineWidth(1.3)
  love.graphics.rectangle("line", bx, by, 22, 12, 2, 2)
  love.graphics.rectangle("fill", bx + 23, by + 3, 2, 6)
  love.graphics.setLineWidth(1)
  local col = pct > 55 and {0.35,0.85,0.40}
          or (pct > 20 and {0.95,0.72,0.25} or {0.95,0.28,0.22})
  local fw = 19 * (math.max(0, math.min(100, pct)) / 100)
  love.graphics.setColor(col[1], col[2], col[3], 1)
  love.graphics.rectangle("fill", bx + 1.5, by + 1.5, fw, 9, 1, 1)
  love.graphics.setFont(A.font_raw(A.FONT_MONO, 10))
  love.graphics.print(string.format("%d%%", pct), bx + 28, by)
end

local function draw_mem_device(x, y, w, h)
  plaque_rect(x, y, w, h, 6)
  love.graphics.setFont(A.font_raw(A.FONT_BODY_BOLD, 11))
  love.graphics.setColor(0.92, 0.92, 0.88, 1)
  love.graphics.print("MEM", x + 8, y + h/2 - 8)
  local pct = read_mem_pct()
  if not pct then
    love.graphics.setColor(0.35, 0.33, 0.30, 1)
    love.graphics.print("--", x + w - 26, y + h/2 - 6)
    return
  end
  local bx, by = x + 42, y + h/2 - 6
  love.graphics.setColor(0.75, 0.74, 0.70, 1)
  love.graphics.setLineWidth(1.3)
  love.graphics.rectangle("line", bx, by, 22, 12, 2, 2)
  love.graphics.setLineWidth(1)
  local col = pct < 50 and {0.35,0.85,0.40}
          or (pct < 75 and {0.95,0.72,0.25} or {0.95,0.28,0.22})
  love.graphics.setColor(col[1], col[2], col[3], 1)
  love.graphics.rectangle("fill", bx + 1.5, by + 1.5,
    19 * math.min(1, pct / 100), 9, 1, 1)
  love.graphics.setFont(A.font_raw(A.FONT_MONO, 10))
  love.graphics.print(string.format("%d%%", pct), bx + 28, by)
end

-- ===== public =====

-- -- Download indicator (top bar) -------------------------------
local function draw_download_indicator(W, H, th)
  local ok, DL = pcall(require, "services.downloader")
  if not ok then return end
  local active = DL.active_count()
  if active <= 0 then return end

  -- small pill in the top bar, left of the clock cluster
  local pill_w = 68
  local pill_h = 20
  local px = W - 320
  local py = (H - pill_h) / 2
  if px < 200 then px = 200 end

  love.graphics.setColor(0.10, 0.30, 0.15, 0.9)
  love.graphics.rectangle("fill", px, py, pill_w, pill_h, 4, 4)
  love.graphics.setColor(0.40, 0.95, 0.45, 0.9)
  love.graphics.setLineWidth(1.2)
  love.graphics.rectangle("line", px + 0.5, py + 0.5, pill_w - 1, pill_h - 1, 4, 4)
  love.graphics.setLineWidth(1)

  local f = A.font_raw(A.FONT_BODY_BOLD, 10)
  love.graphics.setFont(f)
  love.graphics.setColor(0.85, 1.0, 0.85, 1)
  love.graphics.print("DL " .. active, px + 8, py + 4)
end

function F.draw_top(title, sub)
  F.sync()
  local th = State.theme
  local W  = love.graphics.getWidth()
  local H  = F.TOP_H

  love.graphics.setColor(0.010, 0.008, 0.007, 1)
  love.graphics.rectangle("fill", 0, 0, W, H)

  love.graphics.setColor(th.amber_lo[1], th.amber_lo[2], th.amber_lo[3], 0.9)
  love.graphics.rectangle("fill", 0, H - 3, W, 3)
  love.graphics.setColor(th.amber_hi[1], th.amber_hi[2], th.amber_hi[3], 0.55)
  love.graphics.rectangle("fill", 0, H - 1, W, 1)

  love.graphics.setColor(th.grid_faint[1], th.grid_faint[2], th.grid_faint[3], 0.14)
  for x = 0, W, 6 do
    love.graphics.rectangle("fill", x, H - 5, 1, 1)
  end

  -- BRAND LOGO: hanging neon sign, mainmenu / boot only.
  local used_logo = false
  if sub == "mainmenu" or sub == "boot" then
    local show_logo = true
    do
      local ok, Store = pcall(require, "core.settings_store")
      if ok then
        local v = Store.get("ui", "header_logo")
        if v == false then show_logo = false end
      end
    end
    if show_logo then
      local logo = A.image("assets/images/fgd_logo.png")
      if logo then
        local iw, ih = logo:getDimensions()
        -- Bigger target: ~82% of header height
        local logo_h = math.floor(H * 0.82)
        local sc = logo_h / ih
        local dw = iw * sc
        -- Safety cap on width so we never invade the right cluster
        local max_w = 320
        if dw > max_w then
          sc = sc * (max_w / dw)
          logo_h = ih * sc
          dw = max_w
        end
        local lx = 16
        local ly = math.floor((H - logo_h) / 2) + 1

        local amber = {0.94, 0.66, 0.35}
        local cyan  = {0.48, 0.80, 0.90}
        local now   = love.timer.getTime()
        local pulse = 0.85 + 0.15 * math.sin(now * 2.2)

        -- Two hanging chains + rings at the very top of the header
        local hx1 = lx + dw * 0.26
        local hx2 = lx + dw * 0.74
        love.graphics.setLineWidth(1.2)
        love.graphics.setColor(amber[1], amber[2], amber[3], 0.55)
        love.graphics.line(hx1, 0, hx1, ly + 2)
        love.graphics.line(hx2, 0, hx2, ly + 2)
        love.graphics.setColor(amber[1], amber[2], amber[3], 0.9)
        love.graphics.circle("line", hx1, 2.5, 2.4)
        love.graphics.circle("line", hx2, 2.5, 2.4)
        love.graphics.setLineWidth(1)

        -- Additive glow layers
        love.graphics.setBlendMode("add")
        -- Wide soft amber halo
        love.graphics.setColor(amber[1] * 0.45, amber[2] * 0.45, amber[3] * 0.45,
                               0.22 * pulse)
        love.graphics.draw(logo, lx - 5, ly - 5, 0, sc * 1.12, sc * 1.12)
        -- Medium amber ring
        love.graphics.setColor(amber[1] * 0.70, amber[2] * 0.70, amber[3] * 0.70,
                               0.32 * pulse)
        love.graphics.draw(logo, lx - 2, ly - 2, 0, sc * 1.05, sc * 1.05)
        -- Tight cyan edge
        love.graphics.setColor(cyan[1] * 0.75, cyan[2] * 0.75, cyan[3] * 0.75,
                               0.22 * pulse)
        love.graphics.draw(logo, lx + 1, ly + 1, 0, sc, sc)
        love.graphics.draw(logo, lx - 1, ly - 1, 0, sc, sc)
        love.graphics.setBlendMode("alpha")

        -- The logo itself on top
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(logo, lx, ly, 0, sc, sc)

        used_logo = true
      end
    end
  end

  if not used_logo then
    local full = TITLES[sub or ""] or title or ""
    local title_size = math.max(13, math.min(18, math.floor(H * 0.40)))
    local sub_text = (sub and sub ~= "") and ("// " .. sub:upper()) or nil
    if sub_text and sub_text:upper() == ("// " .. full:upper()) then
      sub_text = nil
    end
    local sub_size = math.max(8, math.floor(H * 0.19))

    love.graphics.setColor(th.text_bright)
    love.graphics.setFont(A.font_raw(A.FONT_BODY_BOLD, title_size))

    if sub_text then
      love.graphics.print(full, 16, 4)
      love.graphics.setColor(th.amber_hi)
      love.graphics.setFont(A.font_raw(A.FONT_MONO, sub_size))
      love.graphics.print(sub_text, 16, H - sub_size - 5)
    else
      local f = A.font_raw(A.FONT_BODY_BOLD, title_size)
      local y = math.floor((H - f:getHeight()) / 2)
      love.graphics.print(full, 16, y)
    end
  end

  -- right cluster: clock / wifi / battery / mem (respect toggles)
  local cy      = H / 2
  local clock_r = math.floor(H * 0.36)
  local cursor_x = W - 12

  if ui_flag("show_clock", true) ~= false then
    local clock_x = W - clock_r - 12
    draw_clock_device(clock_x, cy, clock_r)
    cursor_x = clock_x - clock_r - 10
  end

  local dev_h = math.floor(H * 0.58)
  local dev_w = math.floor(dev_h * 2.8)
  local dev_y = cy - dev_h / 2

  if ui_flag("show_wifi", true) ~= false and (cursor_x - dev_w) > 200 then
    draw_wifi_device(cursor_x - dev_w, dev_y, dev_w, dev_h)
    cursor_x = cursor_x - dev_w - 8
  end

  if ui_flag("show_battery", true) ~= false and (cursor_x - dev_w) > 200 then
    draw_battery_device(cursor_x - dev_w, dev_y, dev_w, dev_h)
    cursor_x = cursor_x - dev_w - 8
  end

  if ui_flag("show_mem", true) ~= false and (cursor_x - dev_w) > 200 then
    draw_mem_device(cursor_x - dev_w, dev_y, dev_w, dev_h)
    cursor_x = cursor_x - dev_w - 8
  end

  -- download indicator pill
  if ui_flag("show_download", true) ~= false then
    draw_download_indicator(W, H, th)
  end
end

function F.draw_bottom(hints)
  F.sync()
  local th = State.theme
  local W  = love.graphics.getWidth()
  local H  = love.graphics.getHeight()
  local y0 = H - F.BOTTOM_H

  love.graphics.setColor(0.010, 0.008, 0.007, 1)
  love.graphics.rectangle("fill", 0, y0, W, F.BOTTOM_H)

  love.graphics.setColor(th.amber_lo[1], th.amber_lo[2], th.amber_lo[3], 0.9)
  love.graphics.rectangle("fill", 0, y0, W, 3)
  love.graphics.setColor(th.amber_hi[1], th.amber_hi[2], th.amber_hi[3], 0.55)
  love.graphics.rectangle("fill", 0, y0 + 3, W, 1)

  love.graphics.setColor(th.grid_faint[1], th.grid_faint[2], th.grid_faint[3], 0.14)
  for x = 0, W, 6 do
    love.graphics.rectangle("fill", x, y0 + F.BOTTOM_H - 5, 1, 1)
  end

  if not hints or #hints == 0 then return end

  local badge_r     = math.max(8,  math.floor(F.BOTTOM_H * 0.30))
  local gap_bl      = 6
  local gap_between = 16
  local label_size  = math.max(10, math.floor(F.BOTTOM_H * 0.36))
  local font_lbl    = A.font_raw(A.FONT_BODY, label_size)

  local total = 0
  local measured = {}
  for i, h in ipairs(hints) do
    local lw = font_lbl:getWidth(h.label or "")
    local w = badge_r * 2 + gap_bl + lw
    measured[i] = { w = w, key = h.key or "", label = h.label or "" }
    total = total + w + gap_between
  end
  total = total - gap_between

  local x  = math.floor((W - total) / 2)
  local cy = y0 + F.BOTTOM_H / 2 + 1

  for i, m in ipairs(measured) do
    F.draw_badge(x + badge_r, cy, badge_r, m.key)
    love.graphics.setFont(font_lbl)
    love.graphics.setColor(th.text, 0.95)
    love.graphics.print(m.label, x + badge_r * 2 + gap_bl,
      cy - font_lbl:getHeight() / 2)
    x = x + m.w + gap_between
  end
end

function F.content_rect()
  F.sync()
  local W = love.graphics.getWidth()
  local H = love.graphics.getHeight()
  return 0, F.TOP_H, W, H - F.TOP_H - F.BOTTOM_H
end

return F
