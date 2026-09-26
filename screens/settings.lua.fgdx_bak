-- screens/settings.lua -- Settings Control Panel.
-- Layout: tab bar orizzontale (L1/R1), lista verticale (D-pad su/giu),
-- D-pad sx/dx modifica il valore con badge [-] e [+], A conferma.
local A     = require("core.assets")
local State = require("core.state")
local Input = require("core.input_map")
local Frame = require("ui.frame")
local D     = require("ui.draw")
local Store = require("core.settings_store")
local Notify= require("ui.notify")
local Modal = require("ui.modal")

local S = {}
S.reserve_select = true
S.escape_passthrough = true
local W, H = 640, 480

local AMB={0.94,0.66,0.35}
local CYA={0.48,0.80,0.90}
local GRN={0.55,0.85,0.45}
local BLU={0.55,0.75,0.95}
local PUR={0.70,0.55,0.92}
local YEL={0.95,0.80,0.30}
local RED={0.95,0.30,0.25}
local TEAL={0.35,0.95,1.00}
local GRY={0.45,0.45,0.50}

local function col(c, a) love.graphics.setColor(c[1], c[2], c[3], a or 1) end

-- ============================================================
--  Row factories
-- ============================================================
local function tog(label, hint, sec, key, default, on_change)
  return {
    kind = "toggle", label = label, hint = hint,
    get = function()
      local v = Store.get(sec, key)
      if v == nil then return default == true end
      return v == true
    end,
    toggle = function()
      local v = Store.get(sec, key)
      if v == nil then v = default == true end
      Store.set(sec, key, not v); Store.save()
      if on_change then on_change(not v) end
    end,
  }
end

local function enu(label, hint, sec, key, options, default, on_change)
  return {
    kind = "enum", label = label, hint = hint,
    get = function()
      local v = Store.get(sec, key)
      if v == nil or v == "" then return default end
      return v
    end,
    cycle = function(dir)
      local cur = Store.get(sec, key)
      if cur == nil or cur == "" then cur = default end
      local i = 1
      for k, v in ipairs(options) do if v == cur then i = k end end
      i = ((i - 1 + dir) % #options + #options) % #options + 1
      Store.set(sec, key, options[i]); Store.save()
      if on_change then on_change(options[i]) end
    end,
  }
end

local function sld(label, hint, sec, key, minv, maxv, step, fmt, default, on_change)
  return {
    kind = "slider", label = label, hint = hint,
    minv = minv, maxv = maxv, step = step,
    fmt = fmt or tostring,
    get = function()
      local v = Store.get(sec, key)
      if v == nil then v = default end
      return v
    end,
    cycle = function(dir)
      local v = Store.get(sec, key)
      if v == nil then v = default end
      v = v + dir * step
      if v < minv then v = minv end
      if v > maxv then v = maxv end
      Store.set(sec, key, v); Store.save()
      if on_change then on_change(v) end
    end,
  }
end

local function act(label, hint, fn, danger)
  return { kind = "action", label = label, hint = hint, act = fn, danger = danger }
end

local function inf(label, get_fn)
  return { kind = "info", label = label, get = get_fn }
end

-- ============================================================
--  Tabs
-- ============================================================
local TABS = {
  { id="general", label="GENERAL", accent=AMB, rows={
    enu("Theme", "colore dell'interfaccia",
      "general", "theme",
      {"blame","neon","toxic","blood","deepseek"}, "blame",
      function(new)
        State.theme_name = new
        local ok, m = pcall(require, "themes.theme_"..new)
        if ok and m then
          State.theme = m
          love.graphics.setBackgroundColor(m.bg)
        end
        Notify.show("success", "theme: "..new)
      end),
    sld("Font scale", "dimensione testo globale",
      "ui", "font_scale", 0.80, 1.80, 0.05,
      function(v) return string.format("%.2fx", v) end, 1.20),
    enu("Font family", "font alternativo",
      "ui", "font_family",
      {"auto","orbitron","oxanium","mono","default"}, "auto",
      function() require("core.assets").clear_cache() end),
  }},

  { id="layout", label="LAYOUT", accent=CYA, rows={
    enu("View mode", "default del file manager",
      "general", "view", {"list","grid","compact","details"}, "list"),
    enu("Main hub view", "stile della main menu",
      "ui", "mainmenu_view",
      {"classic","rez","grid","list","expanded list"}, "classic"),
    tog("Dual panel", "due directory affiancate",
      "general", "dual", false),
  }},

  { id="browser", label="BROWSER", accent=GRN, rows={
    enu("Default sort", "ordine dei file",
      "sort", "key", {"name","size","date","type"}, "name"),
    tog("Folders first", "cartelle prima dei file",
      "sort", "folders_first", true),
    tog("Show hidden", "mostra file .nascosti",
      "general", "show_hidden", false),
  }},

  { id="header", label="HEADER", accent=BLU, rows={
    tog("Clock", "orologio nell'header", "ui", "show_clock", true),
    tog("Wi-Fi signal", "indicatore wifi", "ui", "show_wifi", true),
    tog("Battery", "livello batteria", "ui", "show_battery", true),
    tog("Memory", "uso RAM", "ui", "show_mem", true),
    tog("Download indicator", "pill download", "ui", "show_download", true),
    tog("Neon header logo", "logo appeso", "ui", "header_logo", true),
  }},

  { id="interface", label="INTERFACE", accent=PUR, rows={
    tog("Show FPS", "contatore frame", "ui", "show_fps", false),
    tog("Particles & effects", "animazioni e particelle",
      "ui", "particles", true),
    tog("Sound effects", "SFX di sistema", "sound", "enabled", false,
      function(v)
        local ok, SFX = pcall(require, "core.audio")
        if ok then SFX.set_enabled(v) end
      end),
    sld("Sound volume", "volume SFX", "sound", "volume", 0, 100, 5,
      function(v) return string.format("%d%%", v) end, 70,
      function(v)
        local ok, SFX = pcall(require, "core.audio")
        if ok then SFX.set_volume(v/100) end
      end),
    sld("Header thickness", "altezza barra superiore",
      "ui", "header_h", 34, 72, 4,
      function(v) return v .. " px" end, 48),
    sld("Footer thickness", "altezza barra inferiore",
      "ui", "footer_h", 28, 64, 4,
      function(v) return v .. " px" end, 40),
  }},

  { id="updates", label="UPDATES", accent=YEL, rows={
    tog("Auto-update catalog", "scarica catalog.json ad ogni boot",
      "update", "auto_catalog", true),
    tog("Check app updates", "notifica nuova versione",
      "update", "auto_app_check", true),
    act("Refresh catalog now", "scarica subito catalog.json",
      function()
        local ok, Cat = pcall(require, "services.catalog")
        if not ok then Notify.show("error", "catalog service missing"); return end
        Cat.refresh_async()
        Notify.show("info", "refresh in background")
      end),
    act("Check app version", "confronta con remoto",
      function()
        local ok, Cat = pcall(require, "services.catalog")
        if not ok then Notify.show("error", "catalog service missing"); return end
        Cat.check_app_version_async(State.app_version or "v1.5.0")
        Notify.show("info", "check in background")
      end),
    inf("Local cache age", function()
      local f = io.open("data/catalog.cache.json", "r")
      if not f then return "no cache" end
      f:close()
      local out = require("core.sh").read(
        "stat -c %Y data/catalog.cache.json 2>/dev/null")
      local t = tonumber(out or "0") or 0
      if t == 0 then return "?" end
      local age = os.time() - t
      if age < 3600 then return string.format("%d min", math.floor(age/60)) end
      if age < 86400 then return string.format("%d h", math.floor(age/3600)) end
      return string.format("%d d", math.floor(age/86400))
    end),
  }},

  { id="system", label="SYSTEM", accent=RED, rows=function()
    local r = {}
    r[#r+1] = act("About File-GD X", "versione, crediti, licenza",
      function() State.go("about") end)
    r[#r+1] = act("Key guide", "tutti i binding in un posto",
      function() State.go("help") end)
    r[#r+1] = act("Open log viewer", "log runtime e sessione",
      function() State.go("log") end)
    if State.dev_unlocked then
      r[#r+1] = {
        kind = "grid_dev",
        label = "GRiD-Dev",
        hint = "developer console  ·  restricted access",
      }
    end
    r[#r+1] = act("Reset all settings", "ripristina i default",
      function()
        Modal.show("Reset all settings",
          "Ripristinare ogni preferenza al default?",
          { accept_label = "RESET", cancel_label = "CANCEL",
            accept_color = RED,
            on_accept = function()
              os.remove("data/fgd.json")
              Store.load()
              require("core.assets").clear_cache()
              Notify.show("success", "settings reset")
            end })
      end, true)
    r[#r+1] = inf("App version", function()
      return State.app_version or "v1.5.0"
    end)
    return r
  end },
}
local NTAB = #TABS

-- ============================================================
--  State
-- ============================================================
local cur_tab = 1
local sel = 1
local t = 0
local last_dt = 0.016
local tog_anim = {}

local function cur_rows()
  local tab = TABS[cur_tab]
  if type(tab.rows) == "function" then return tab.rows() end
  return tab.rows
end

local function cur_row()
  return cur_rows()[sel]
end

local function clamp_sel()
  local n = #cur_rows()
  if n == 0 then sel = 1
  elseif sel < 1 then sel = 1
  elseif sel > n then sel = n end
end

-- ============================================================
--  Lifecycle
-- ============================================================
function S.enter()
  Store.load()
  t = 0
  if State._returning then
    cur_tab = math.max(1, math.min(NTAB, State.settings_tab or 1))
    sel = math.max(1, State.settings_sel or 1)
  else
    cur_tab = 1
    sel = 1
  end
  clamp_sel()
end

function S.leave()
  State.settings_tab = cur_tab
  State.settings_sel = sel
end

function S.update(dt)
  t = t + dt
  last_dt = dt
  pcall(function() require("ui.frame").sync() end)
end

-- ============================================================
--  Navigation
-- ============================================================
local function move_row(d)
  local n = #cur_rows()
  if n == 0 then return end
  sel = sel + d
  if sel < 1 then sel = n end
  if sel > n then sel = 1 end
end

local function cycle_tab(d)
  cur_tab = cur_tab + d
  if cur_tab < 1 then cur_tab = NTAB end
  if cur_tab > NTAB then cur_tab = 1 end
  sel = 1
  S._scroll = 0
end

local function cycle_value(dir)
  local r = cur_row()
  if not r then return end
  if r.kind == "enum" or r.kind == "slider" then
    if r.cycle then r.cycle(dir) end
  elseif r.kind == "toggle" then
    if r.toggle then r.toggle() end
  end
end

local function activate()
  local r = cur_row()
  if not r then return end
  if r.kind == "toggle" then
    if r.toggle then r.toggle() end
  elseif r.kind == "enum" or r.kind == "slider" then
    if r.cycle then r.cycle(1) end
  elseif r.kind == "action" then
    if r.act then r.act() end
  elseif r.kind == "grid_dev" then
    local ok, SFX = pcall(require, "core.audio")
    if ok then SFX.play("gokustep") end
    State.go("grid_dev")
  end
end

-- ============================================================
--  Input
-- ============================================================
function S.hat(dir)
  if Modal.is_open() then return end
  local r = cur_row()
  local value_row = r and (r.kind == "toggle" or r.kind == "enum" or r.kind == "slider")
  if dir == "up" then
    move_row(-1)
  elseif dir == "down" then
    move_row(1)
  elseif dir == "left" then
    if value_row then
      local ok, SFX = pcall(require, "core.audio")
      if ok then
        if r.kind == "toggle" then SFX.play("toggle_switch")
        else SFX.play("toggle_badge") end
      end
      cycle_value(-1)
    end
  elseif dir == "right" then
    if value_row then
      local ok, SFX = pcall(require, "core.audio")
      if ok then
        if r.kind == "toggle" then SFX.play("toggle_switch")
        else SFX.play("toggle_badge") end
      end
      cycle_value(1)
    end
  end
end

function S.pad(b)
  if Modal.is_open() then
    if b == Input.A then Modal.accept()
    elseif b == Input.B then Modal.cancel() end
    return
  end
  if b == Input.A then
    local r = cur_row()
    if r then
      local ok, SFX = pcall(require, "core.audio")
      if ok then
        if r.kind == "toggle" then SFX.play("toggle_switch")
        elseif r.kind == "enum" or r.kind == "slider" then SFX.play("toggle_badge")
        elseif r.kind == "grid_dev" then -- handled in activate
        else SFX.play("enter") end
      end
    end
    activate()
  elseif b == Input.B or b == Input.SELECT then
    State.back()
  elseif b == Input.L1 then
    cycle_tab(-1)
  elseif b == Input.R1 then
    cycle_tab(1)
  end
end

function S.key(k)
  if Modal.is_open() then
    if k == "return" or k == "space" then Modal.accept()
    elseif k == "escape" or k == "backspace" then Modal.cancel() end
    return
  end
  if     k == "up"    then S.hat("up")
  elseif k == "down"  then S.hat("down")
  elseif k == "left"  then S.hat("left")
  elseif k == "right" then S.hat("right")
  elseif k == "return" or k == "space" then S.pad(Input.A)
  elseif k == "q"     then cycle_tab(-1)
  elseif k == "e"     then cycle_tab(1)
  elseif k == "escape" or k == "backspace" then State.back() end
end

function S.override_sfx(name)
  local r = cur_row()
  if not r then return false end
  local value_row = (r.kind == "toggle" or r.kind == "enum" or r.kind == "slider")
  if not value_row then return false end
  if name == "a" then return true end
  if name == "dpleft" or name == "dpright" then return true end
  return false
end

-- ============================================================
--  Drawing primitives
-- ============================================================
local function draw_toggle(cx, cy, w, h, on, id, accent)
  local x, y = cx - w/2, cy - h/2
  local tt = tog_anim[id]
  if tt == nil then tt = on and 1 or 0 end
  tt = tt + ((on and 1 or 0) - tt) * math.min(1, last_dt * 16)
  tog_anim[id] = tt

  local c_on  = {0.30, 0.85, 0.45}
  local c_off = {0.30, 0.30, 0.35}
  local c = on and c_on or c_off

  col({0.05, 0.06, 0.08}, 1)
  love.graphics.rectangle("fill", x, y, w, h, h/2, h/2)

  local fw = (w - 4) * tt
  if fw > 2 then
    col(c, 0.85)
    love.graphics.rectangle("fill", x + 2, y + 2, fw, h - 4, (h-4)/2, (h-4)/2)
  end

  col(c, 0.9)
  love.graphics.setLineWidth(1.4)
  love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, h/2, h/2)
  love.graphics.setLineWidth(1)

  local kr = h/2 - 3
  local kx = x + h/2 + (w - h) * tt
  col({0, 0, 0}, 0.5)
  love.graphics.circle("fill", kx + 1, cy + 2, kr)
  col({0.96, 0.96, 0.97}, 1)
  love.graphics.circle("fill", kx, cy, kr)

  if on then
    love.graphics.setFont(A.font(A.FONT_MONO, 8))
    col({0, 0, 0}, 0.75)
    love.graphics.print("ON", x + 7, cy - 4)
  end
end

local function draw_badge(cx, cy, r, accent, focused, kind)
  col({accent[1]*0.20, accent[2]*0.20, accent[3]*0.20}, 1)
  love.graphics.circle("fill", cx, cy, r)
  col(accent, focused and 0.95 or 0.45)
  love.graphics.setLineWidth(1.4)
  love.graphics.circle("line", cx, cy, r)
  love.graphics.setLineWidth(1)
  col(accent, focused and 1 or 0.65)
  love.graphics.setLineWidth(2)
  love.graphics.line(cx - r*0.42, cy, cx + r*0.42, cy)
  if kind == "plus" then
    love.graphics.line(cx, cy - r*0.42, cx, cy + r*0.42)
  end
  love.graphics.setLineWidth(1)
end

local function draw_enum(x_right, cy, value, accent, focused)
  local f = A.font(A.FONT_MONO, 12)
  love.graphics.setFont(f)
  local tw = f:getWidth(value)
  local r = 10
  local gap = 6
  local pill_h = 22
  local pill_w = math.max(60, tw + 22)
  local total = r*2 + gap + pill_w + gap + r*2
  local start_x = x_right - total

  draw_badge(start_x + r, cy, r, accent, focused, "minus")

  local px = start_x + r*2 + gap
  col({accent[1]*0.15, accent[2]*0.15, accent[3]*0.15}, focused and 1 or 0.55)
  love.graphics.rectangle("fill", px, cy - pill_h/2, pill_w, pill_h,
    pill_h/2, pill_h/2)
  if focused then
    col(accent, 0.9)
    love.graphics.setLineWidth(1.4)
    love.graphics.rectangle("line", px + 0.5, cy - pill_h/2 + 0.5,
      pill_w - 1, pill_h - 1, pill_h/2, pill_h/2)
    love.graphics.setLineWidth(1)
  end
  col(focused and {1,1,1} or {0.75, 0.78, 0.80}, 1)
  love.graphics.printf(value, px, cy - 7, pill_w, "center")

  draw_badge(start_x + total - r, cy, r, accent, focused, "plus")
end

local function draw_slider(x, y, w, value, minv, maxv, fmt, focused, accent)
  local f = A.font(A.FONT_MONO, 12)
  love.graphics.setFont(f)
  local vtxt = fmt(value)
  local vw = math.max(60, f:getWidth(vtxt) + 22)

  local bx = x + w - vw
  col({accent[1]*0.15, accent[2]*0.15, accent[3]*0.15}, focused and 1 or 0.55)
  love.graphics.rectangle("fill", bx, y - 10, vw, 20, 10, 10)
  if focused then
    col(accent, 0.9)
    love.graphics.setLineWidth(1.4)
    love.graphics.rectangle("line", bx + 0.5, y - 9.5, vw - 1, 19, 10, 10)
    love.graphics.setLineWidth(1)
  end
  col(focused and {1,1,1} or {0.75, 0.78, 0.80}, 1)
  love.graphics.printf(vtxt, bx, y - 7, vw, "center")

  local tx, ty, th = x, y + 8, 10
  col({0.06, 0.07, 0.09}, 1)
  love.graphics.rectangle("fill", tx, ty, w, th, th/2, th/2)

  local pct = (maxv > minv) and ((value - minv) / (maxv - minv)) or 0
  for i = 0, 10 do
    local ttx = tx + (w * i / 10)
    col({0.16, 0.18, 0.20}, 0.85)
    love.graphics.line(ttx, ty + 2, ttx, ty + th - 2)
  end

  local fw = w * pct
  if fw > 2 then
    col(accent, 0.85)
    love.graphics.rectangle("fill", tx + 1, ty + 1, fw - 2, th - 2,
      (th-2)/2, (th-2)/2)
  end
  col(focused and accent or {0.30, 0.34, 0.38}, focused and 0.9 or 0.55)
  love.graphics.setLineWidth(focused and 1.4 or 1)
  love.graphics.rectangle("line", tx + 0.5, ty + 0.5, w - 1, th - 1,
    th/2, th/2)
  love.graphics.setLineWidth(1)

  local kx = tx + fw
  local ky = ty + th/2
  if focused then
    D.glow(kx, ky, 16, accent, 0.7)
  end
  col({0, 0, 0}, 0.5)
  love.graphics.circle("fill", kx + 1, ky + 2, 7)
  col(accent, 0.95)
  love.graphics.circle("fill", kx, ky, 8)
  col({0.96, 0.96, 0.97}, 1)
  love.graphics.circle("fill", kx, ky, 7)
end

-- GRiD-Dev special row kind -- unique cyber/teal style
local function draw_grid_dev_row(x, y, w, h, focused)
  local TEAL_HI = TEAL
  local BG = {0.020, 0.060, 0.080}

  if focused then
    -- accent glow behind
    col({TEAL[1]*0.20, TEAL[2]*0.20, TEAL[3]*0.20}, 1)
    love.graphics.rectangle("fill", x, y, w, h, 4, 4)
    col(TEAL_HI, 0.95)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, 4, 4)
    love.graphics.setLineWidth(1)
    -- double frame
    col(TEAL_HI, 0.45)
    love.graphics.rectangle("line", x + 4.5, y + 4.5, w - 9, h - 9, 3, 3)
    -- corner ticks
    D.corner_ticks(x + 8, y + 8, w - 16, h - 16, 10, TEAL_HI, 0.95)
    -- side accent bar
    col(TEAL_HI, 1)
    love.graphics.rectangle("fill", x, y + 4, 4, h - 8)
    -- glow
    D.glow(x + w/2, y + h/2, w * 0.5, TEAL_HI, 0.45)
  else
    col(BG, 0.92)
    love.graphics.rectangle("fill", x, y, w, h, 4, 4)
    col(TEAL_HI, 0.55)
    love.graphics.setLineWidth(1.5)
    love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, 4, 4)
    love.graphics.setLineWidth(1)
    col(TEAL_HI, 0.30)
    love.graphics.rectangle("line", x + 4.5, y + 4.5, w - 9, h - 9, 3, 3)
    col(TEAL_HI, 0.85)
    love.graphics.rectangle("fill", x, y + 4, 3, h - 8)
  end

  -- hex icon "GD"
  local icx = x + 34
  local icy = y + h / 2
  local ir = 18
  -- hexagon
  local pts = {}
  for i = 0, 5 do
    local a = -math.pi/2 + i * math.pi/3
    pts[#pts+1] = icx + math.cos(a) * ir
    pts[#pts+1] = icy + math.sin(a) * ir
  end
  col({TEAL[1]*0.25, TEAL[2]*0.25, TEAL[3]*0.25}, 1)
  love.graphics.polygon("fill", pts)
  col(TEAL_HI, 0.95)
  love.graphics.setLineWidth(1.6)
  love.graphics.polygon("line", pts)
  love.graphics.setLineWidth(1)
  love.graphics.setFont(A.font(A.FONT_MONO, 11))
  col({1,1,1}, 1)
  love.graphics.printf("GD", icx - ir, icy - 6, ir * 2, "center")

  -- label
  love.graphics.setFont(A.font(A.FONT_TITLE, 17))
  col(TEAL_HI, 1)
  love.graphics.print("GRiD-Dev", x + 70, y + 10)
  love.graphics.setFont(A.font(A.FONT_MONO, 9))
  col(TEAL_HI, 0.75)
  love.graphics.print("developer console  ·  restricted access", x + 70, y + 30)

  -- ENTER pill right
  local pw, ph = 72, 22
  local px = x + w - pw - 14
  local py_ = y + (h - ph) / 2
  col({TEAL[1]*0.22, TEAL[2]*0.22, TEAL[3]*0.22}, 1)
  love.graphics.rectangle("fill", px, py_, pw, ph, 11, 11)
  col(TEAL_HI, focused and 0.95 or 0.55)
  love.graphics.setLineWidth(1.4)
  love.graphics.rectangle("line", px + 0.5, py_ + 0.5, pw - 1, ph - 1, 11, 11)
  love.graphics.setLineWidth(1)
  love.graphics.setFont(A.font(A.FONT_MONO, 10))
  col(TEAL_HI, focused and 1 or 0.75)
  love.graphics.printf("ENTER >", px, py_ + 5, pw, "center")
end

-- ============================================================
--  Row renderer
-- ============================================================
local ROW_H      = 46
local ROW_H_SLDR = 62
local ROW_H_GD   = 58
local ROW_GAP    = 4

local function row_h(r)
  if r.kind == "slider" then return ROW_H_SLDR end
  if r.kind == "grid_dev" then return ROW_H_GD end
  return ROW_H
end

local function draw_row(r, x, y, w, focused, accent, idx)
  local h = row_h(r)

  if r.kind == "grid_dev" then
    draw_grid_dev_row(x, y, w, h, focused)
    return
  end

  if focused then
    col({accent[1]*0.14, accent[2]*0.14, accent[3]*0.14}, 0.95)
    love.graphics.rectangle("fill", x, y, w, h, 4, 4)
    col(accent, 0.9)
    love.graphics.setLineWidth(1.6)
    love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, 4, 4)
    love.graphics.setLineWidth(1)
    col(accent, 1)
    love.graphics.rectangle("fill", x, y + 6, 3, h - 12)
  else
    col({0.028, 0.024, 0.022}, 0.75)
    love.graphics.rectangle("fill", x, y, w, h, 4, 4)
    col(accent, 0.18)
    love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, 4, 4)
  end

  love.graphics.setFont(A.font(A.FONT_BODY_BOLD, 13))
  col(focused and {1,1,1} or State.theme.text, 1)
  local label_y = y + (r.hint and 8 or (h - 14) / 2)
  love.graphics.print(r.label, x + 16, label_y)

  if r.hint then
    love.graphics.setFont(A.font(A.FONT_BODY, 9))
    col(State.theme.text_dim, 0.75)
    love.graphics.print(r.hint, x + 16, y + 26)
  end

  local right_x = x + w - 12

  if r.kind == "toggle" then
    local on = r.get()
    if focused then
      local pulse = 0.7 + 0.3 * math.sin(t * 2.4)
      D.glow(right_x - 28, y + h/2, 42, accent, 0.5 * pulse)
    end
    draw_toggle(right_x - 28, y + h/2, 56, 26, on,
      "t" .. cur_tab .. "_" .. idx, accent)

  elseif r.kind == "enum" then
    draw_enum(right_x, y + h/2, tostring(r.get()), accent, focused)

  elseif r.kind == "slider" then
    draw_slider(x + 16, y + 32, w - 32, r.get(),
      r.minv, r.maxv, r.fmt, focused, accent)

  elseif r.kind == "action" then
    local c = r.danger and RED or accent
    local bw, bh = 96, 22
    local bx = right_x - bw
    local by = y + (h - bh) / 2
    col({c[1]*0.22, c[2]*0.22, c[3]*0.22}, 1)
    love.graphics.rectangle("fill", bx, by, bw, bh, 11, 11)
    col(c, focused and 0.95 or 0.55)
    love.graphics.setLineWidth(1.4)
    love.graphics.rectangle("line", bx + 0.5, by + 0.5, bw - 1, bh - 1, 11, 11)
    love.graphics.setLineWidth(1)
    love.graphics.setFont(A.font(A.FONT_MONO, 10))
    col(c, focused and 1 or 0.75)
    love.graphics.printf("RUN", bx, by + 5, bw, "center")

  elseif r.kind == "info" then
    local v = r.get and r.get() or "-"
    love.graphics.setFont(A.font(A.FONT_MONO, 10))
    col(GRY, focused and 1 or 0.75)
    love.graphics.printf(tostring(v), 0, y + (h - 10) / 2, right_x, "right")
  end
end

-- ============================================================
--  Tab bar
-- ============================================================
local function draw_tab_bar(x, y, w)
  local tab_h = 30
  local gap = 4
  local tw = (w - (NTAB - 1) * gap) / NTAB

  for i, tab in ipairs(TABS) do
    local tx = x + (i - 1) * (tw + gap)
    local focused = (i == cur_tab)
    local c = tab.accent

    if focused then
      col({c[1]*0.20, c[2]*0.20, c[3]*0.20}, 0.95)
      love.graphics.rectangle("fill", tx, y, tw, tab_h, 4, 4)
      col(c, 0.95)
      love.graphics.setLineWidth(1.6)
      love.graphics.rectangle("line", tx + 0.5, y + 0.5, tw - 1, tab_h - 1, 4, 4)
      love.graphics.setLineWidth(1)
      col(c, 1)
      love.graphics.rectangle("fill", tx + 6, y + tab_h - 3, tw - 12, 3)
    else
      col({0.030, 0.028, 0.032}, 0.75)
      love.graphics.rectangle("fill", tx, y, tw, tab_h, 4, 4)
      col(c, 0.30)
      love.graphics.rectangle("line", tx + 0.5, y + 0.5, tw - 1, tab_h - 1, 4, 4)
    end

    love.graphics.setFont(A.font(A.FONT_BODY_BOLD, focused and 11 or 10))
    col(focused and {1,1,1} or {0.65, 0.68, 0.72}, 1)
    love.graphics.printf(tab.label, tx, y + 8, tw, "center")
  end
end

-- ============================================================
--  Main draw
-- ============================================================
function S.draw()
  D.bg()

  local tab = TABS[cur_tab]
  local acc = tab.accent

  col(acc, 0.05)
  for y = Frame.TOP_H, H - Frame.BOTTOM_H, 16 do
    for x = 0, W, 16 do
      love.graphics.rectangle("fill", x, y, 1, 1)
    end
  end

  D.corner_ticks(4, Frame.TOP_H + 2, W - 8,
    H - Frame.TOP_H - Frame.BOTTOM_H - 4, 18, acc, 0.30)

  local hdr_y = Frame.TOP_H + 6
  love.graphics.setFont(A.font(A.FONT_MONO, 10))
  col(acc, 0.85)
  love.graphics.print("SETTINGS  //  " .. tab.label, 16, hdr_y)

  love.graphics.setFont(A.font(A.FONT_MONO, 9))
  col(GRY, 0.8)
  love.graphics.printf(string.format("%02d/%02d", cur_tab, NTAB),
    0, hdr_y + 1, W - 16, "right")

  local tab_y = Frame.TOP_H + 24
  draw_tab_bar(16, tab_y, W - 32)

  local cx = 16
  local cy = tab_y + 30 + 8
  local cw = W - 32
  local ch = H - Frame.BOTTOM_H - cy - 4

  love.graphics.setScissor(cx, cy, cw, ch)

  local rows = cur_rows()
  local total = 0
  for _, r in ipairs(rows) do total = total + row_h(r) + ROW_GAP end

  local y_before = 0
  for i = 1, sel - 1 do y_before = y_before + row_h(rows[i]) + ROW_GAP end
  local row_bot = y_before + (rows[sel] and row_h(rows[sel]) or 0) + ROW_GAP
  local sc = S._scroll or 0
  if y_before < sc then sc = y_before end
  if row_bot > sc + ch then sc = row_bot - ch end
  sc = math.max(0, math.min(math.max(0, total - ch), sc))
  S._scroll = sc

  local ry = cy - sc
  for i, r in ipairs(rows) do
    local rh = row_h(r)
    if ry + rh > cy - 4 and ry < cy + ch + 4 then
      draw_row(r, cx, ry, cw, i == sel, acc, i)
    end
    ry = ry + rh + ROW_GAP
  end

  love.graphics.setScissor()

  if total > ch then
    local track_h = ch - 4
    local thumb_h = math.max(20, track_h * (ch / total))
    local denom = math.max(1, total - ch)
    local thumb_y = cy + 2 + (track_h - thumb_h) * (sc / denom)
    col(acc, 0.5)
    love.graphics.rectangle("fill", W - 6, thumb_y, 3, thumb_h, 1, 1)
  end

  Frame.draw_top("FGD", "settings")
  Frame.draw_bottom({
    { key = "up",   label = "Row" },
    { key = "l/r",  label = "Value" },
    { key = "l1",   label = "Tab -" },
    { key = "r1",   label = "Tab +" },
    { key = "a",    label = "Run" },
    { key = "b",    label = "Back" },
  })
  Modal.draw()
  D.scanlines(W, H, 0.05)
  D.vignette(W, H, 0.55)
end

return S
