-- screens/grid_dev.lua -- GRiD-Dev developer console.
-- Same tab+list layout as Settings, but with unique dark-teal palette.
-- 6 tabs, mascot SSJ4 present. Restricted access.
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

-- GRiD-Dev palette: dark teal + cyan, distinctive
local TEAL   = {0.35, 0.95, 1.00}
local TEAL_HI= {0.60, 1.00, 1.00}
local TEAL_LO= {0.05, 0.25, 0.30}
local AMB    = {0.94, 0.66, 0.35}
local GRN    = {0.55, 0.85, 0.45}
local RED    = {0.95, 0.30, 0.25}
local ORG    = {1.00, 0.55, 0.20}
local PUR    = {0.70, 0.55, 0.92}
local GRY    = {0.45, 0.45, 0.50}

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

local function num(label, hint, sec, key, minv, maxv, step, fmt, default, on_change)
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
  { id="perf", label="PERFORMANCE", accent=AMB, rows={
    enu("Frame rate cap", "limite FPS",
      "dev", "fps_cap", {"vsync", "30", "60", "120", "unlimited"}, "vsync"),
    num("Particle density", "densita' particelle", "dev", "particle_density",
      0, 200, 10, function(v) return v .. "%" end, 100),
    tog("CRT scanlines", "linee CRT sui pannelli", "dev", "crt_scanlines", true),
    tog("Vignette", "oscuramento bordi", "dev", "vignette", true),
    tog("Smooth motion", "animazioni fluide", "dev", "smooth", true),
  }},

  { id="dbg", label="DEBUG", accent=GRN, rows={
    tog("Input debug overlay", "overlay F3 input", "dev", "dbg_input", false),
    tog("Screen debug overlay", "overlay nome schermata", "dev", "dbg_screen", false),
    tog("Verbose runtime log", "log dettagliato", "dev", "verbose", false),
    act("Save runtime snapshot", "scrive data/snapshots/*.txt",
      function()
        os.execute("mkdir -p data/snapshots")
        local ts = os.date("%Y%m%d_%H%M%S")
        local f = io.open("data/snapshots/" .. ts .. ".txt", "w")
        if f then
          f:write("manual snapshot " .. ts .. "\n")
          f:write("host: " .. (os.getenv("HOSTNAME") or "?") .. "\n")
          f:close()
          Notify.show("success", "snapshot: " .. ts)
        else
          Notify.show("error", "snapshot failed")
        end
      end),
  }},

  { id="sys", label="BEHAVIOR", accent=PUR, rows={
    num("Header thickness", "altezza barra superiore",
      "ui", "header_h", 34, 72, 4,
      function(v) return v .. " px" end, 48),
    num("Footer thickness", "altezza barra inferiore",
      "ui", "footer_h", 28, 64, 4,
      function(v) return v .. " px" end, 40),
    tog("Neon header logo", "logo appeso", "ui", "header_logo", true),
    enu("Boot animation", "animazione avvio",
      "dev", "boot_anim", {"on", "short", "off"}, "on"),
    tog("Confirm on delete", "chiedi conferma delete", "dev", "confirm_del", true),
    tog("Confirm on exit", "chiedi conferma uscita", "dev", "confirm_exit", false),
    tog("Trash on delete", "cestino invece di hard delete", "dev", "use_trash", true),
    tog("Auto-refresh grid", "refresh automatico griglia", "dev", "auto_refresh", true),
  }},

  { id="net", label="NETWORK", accent=ORG, rows={
    inf("Download folder", function()
      return Store.get("dev", "dl_folder") or "data/downloads"
    end),
    inf("User agent", function()
      return Store.get("dev", "user_agent") or "FileGDX/1.0"
    end),
    num("Timeout", "timeout download", "dev", "timeout", 10, 600, 15,
      function(v) return v .. "s" end, 60),
    tog("Show bytes", "mostra velocita' in bytes", "dev", "show_bytes", false),
  }},

  { id="maint", label="MAINTENANCE", accent=RED, rows={
    tog("Persist dev unlock", "sblocco persistente tra sessioni",
      "dev", "persist_unlock", false,
      function(v)
        if v then
          Notify.show("success", "GRiD-Dev persistente attivo")
        else
          Notify.show("warning", "GRiD-Dev tornera' locked al riavvio")
        end
      end),
    act("Clear all snapshots", "elimina data/snapshots/*",
      function()
        os.execute("rm -f data/snapshots/*.txt data/snapshots/*.log 2>/dev/null")
        Notify.show("warning", "snapshots cleared")
      end, true),
    act("Clear download cache", "elimina data/downloads/*",
      function()
        os.execute("rm -f data/downloads/* 2>/dev/null")
        Notify.show("warning", "download cache cleared")
      end, true),
    act("Reset dev settings", "ripristina i valori di default di GRiD-Dev",
      function()
        Modal.show("Reset dev settings",
          "Cancellare tutte le impostazioni dev e ripristinare i default?",
          { accept_label = "RESET", cancel_label = "CANCEL",
            accept_color = RED,
            on_accept = function()
              local sd = Store.data or {}
              sd.dev = {}
              Store.save()
              Notify.show("warning", "dev settings reset")
            end })
      end, true),
    act("Reset GRiD-Dev unlock", "blocca il menu fino al prossimo Konami",
      function()
        Modal.show("Reset unlock",
          "Bloccare GRiD-Dev? Dovrai reinserire il Konami code.",
          { accept_label = "LOCK", cancel_label = "CANCEL",
            accept_color = RED,
            on_accept = function()
              State.dev_unlocked = false
              Store.set("dev", "persist_unlock", false); Store.save()
              Notify.show("warning", "GRiD-Dev locked")
              State.go("settings")
            end })
      end, true),
  }},

  { id="goku", label="GOKU SSJ4", accent=ORG, rows=function()
    local r = {}
    r[#r+1] = { kind = "mascot_preview", label = "Mascot preview" }
    r[#r+1] = tog("Show mascot", "mostra la mascotte SSJ4", "goku", "show_mascot", true)
    r[#r+1] = enu("Sprite size", "dimensione sprite", "goku", "size",
      {"small", "medium", "large", "huge"}, "medium")
    r[#r+1] = num("Float amplitude", "ampiezza oscillazione", "goku", "amp",
      0, 30, 2, function(v) return v .. " px" end, 14)
    r[#r+1] = enu("Float speed", "velocita' oscillazione", "goku", "speed",
      {"very_slow", "slow", "normal", "fast", "wild"}, "normal")
    r[#r+1] = tog("Ground shadow", "ombra a terra", "goku", "shadow", true)
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
local mascot = { img_l = nil, img_r = nil, tried = false, phase = 0 }

local SIZE_MAP = { small=72, medium=112, large=144, huge=180 }
local SPEED_MAP = { very_slow=0.7, slow=1.0, normal=1.4, fast=2.0, wild=3.0 }

local function goku_get(key, default)
  local v = Store.get("goku", key)
  if v == nil then return default end
  return v
end

local function ensure_mascots()
  if mascot.tried then return end
  mascot.tried = true
  local sx = A.image("assets/images/gokussj4_sx.png")
  if sx then
    local w, h = sx:getDimensions()
    mascot.img_l = { img = sx, w = w, h = h }
  end
  local dx = A.image("assets/images/gokussj4_dx.png")
  if dx then
    local w, h = dx:getDimensions()
    mascot.img_r = { img = dx, w = w, h = h }
  end
end

-- ============================================================
--  Lifecycle
-- ============================================================
function S.enter()
  Store.load()
  t = 0
  if not State._returning then
    cur_tab = 1
    sel = 1
    S._scroll = 0
  end
  ensure_mascots()
  local ok, SFX = pcall(require, "core.audio")
  if ok and SFX.play then SFX.play("gokustep") end
end

function S.leave()
  local ok, SFX = pcall(require, "core.audio")
  if ok and SFX.stop_bgm then SFX.stop_bgm() end
end

function S.update(dt)
  t = t + dt
  last_dt = dt
  mascot.phase = mascot.phase + dt * (SPEED_MAP[goku_get("speed", "normal")] or 1.4)
end

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
  local ok, SFX = pcall(require, "core.audio")
  if ok then
    if TABS[cur_tab].id == "goku" then SFX.play("gokustep")
    else SFX.play("nav3") end
  end
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
  end
end

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
        else SFX.play("enter") end
      end
    end
    activate()
  elseif b == Input.SELECT then
    -- Toggle mascot visibility for this session
    S._mascot_hidden = not S._mascot_hidden
    local ok, SFX = pcall(require, "core.audio")
    if ok and SFX.play then SFX.play("toggle_switch") end
    local ok2, N = pcall(require, "ui.notify")
    if ok2 and N.show then
      N.show("info", S._mascot_hidden
        and "Mascot hidden (SELECT to show)"
        or "Mascot visible")
    end
  elseif b == Input.B then
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
  elseif k == "h" then
    S._mascot_hidden = not S._mascot_hidden
    local ok2, N = pcall(require, "ui.notify")
    if ok2 and N.show then N.show("info", S._mascot_hidden
      and "Mascot hidden" or "Mascot visible") end
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
--  Drawing primitives (same as settings but unique accent)
-- ============================================================
local function draw_toggle(cx, cy, w, h, on, id)
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
  if focused then D.glow(kx, ky, 16, accent, 0.7) end
  col({0, 0, 0}, 0.5)
  love.graphics.circle("fill", kx + 1, ky + 2, 7)
  col(accent, 0.95)
  love.graphics.circle("fill", kx, ky, 8)
  col({0.96, 0.96, 0.97}, 1)
  love.graphics.circle("fill", kx, ky, 7)
end

-- Mascot preview special row
local function draw_mascot_preview(x, y, w, h, focused)
  local accent = TEAL_HI
  -- dark preview box
  col({0.020, 0.050, 0.070}, 0.95)
  love.graphics.rectangle("fill", x, y, w, h, 4, 4)
  col(accent, focused and 0.90 or 0.35)
  love.graphics.setLineWidth(focused and 2 or 1)
  love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, 4, 4)
  love.graphics.setLineWidth(1)
  D.corner_ticks(x + 6, y + 6, w - 12, h - 12, 10, accent, focused and 0.9 or 0.35)

  -- left label
  love.graphics.setFont(A.font(A.FONT_MONO, 10))
  col(accent, 0.9)
  love.graphics.print("MASCOT PREVIEW", x + 14, y + 10)
  love.graphics.setFont(A.font(A.FONT_MONO, 9))
  col(accent, 0.7)
  love.graphics.print("Goku SSJ4 sprite", x + 14, y + 26)

  -- preview the sprite
  ensure_mascots()
  local side = goku_get("side", "left")
  local entry = (side == "left") and mascot.img_l or mascot.img_r
  entry = entry or mascot.img_l or mascot.img_r
  local px_cx = x + w - 100
  local px_cy = y + h / 2
  if entry then
    local target_h = math.min(h - 20, 90)
    local sc = target_h / entry.h
    local dw = entry.w * sc
    local dh = entry.h * sc
    local float_y = math.sin(mascot.phase) * 4
    col({1,1,1}, 1)
    love.graphics.draw(entry.img, px_cx - dw/2, px_cy - dh/2 + float_y, 0, sc, sc)
    col({1,1,1}, 1)
  else
    -- fallback
    col(accent, 0.9)
    love.graphics.circle("line", px_cx, px_cy, 30)
    love.graphics.setFont(A.font(A.FONT_MONO, 10))
    col(accent, 0.7)
    love.graphics.printf("sprite missing", px_cx - 50, px_cy - 6, 100, "center")
  end

  -- current config pill
  local pw, ph = 60, 20
  local pp = x + w - pw - 14
  col({accent[1]*0.20, accent[2]*0.20, accent[3]*0.20}, 1)
  love.graphics.rectangle("fill", pp, y + 10, pw, ph, 10, 10)
  col(accent, 0.9)
  love.graphics.rectangle("line", pp + 0.5, y + 10.5, pw - 1, ph - 1, 10, 10)
  love.graphics.setFont(A.font(A.FONT_MONO, 9))
  col({1,1,1}, 1)
  love.graphics.printf(goku_get("size", "medium"), pp, y + 13, pw, "center")
end

-- ============================================================
--  Row renderer
-- ============================================================
local ROW_H      = 46
local ROW_H_SLDR = 62
local ROW_H_MASC = 110
local ROW_GAP    = 4

local function row_h(r)
  if r.kind == "slider" then return ROW_H_SLDR end
  if r.kind == "mascot_preview" then return ROW_H_MASC end
  return ROW_H
end

local function draw_row(r, x, y, w, focused, accent, idx)
  local h = row_h(r)

  if r.kind == "mascot_preview" then
    draw_mascot_preview(x, y, w, h, focused)
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
      "g" .. cur_tab .. "_" .. idx)
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
--  Tab bar (GRiD-Dev style: hexagon icons, teal frame)
-- ============================================================
local function draw_tab_bar(x, y, w)
  local tab_h = 32
  local gap = 4
  local tw = (w - (NTAB - 1) * gap) / NTAB
  for i, tab in ipairs(TABS) do
    local tx = x + (i - 1) * (tw + gap)
    local focused = (i == cur_tab)
    local c = tab.accent
    if focused then
      col({c[1]*0.22, c[2]*0.22, c[3]*0.22}, 0.95)
      love.graphics.rectangle("fill", tx, y, tw, tab_h, 4, 4)
      col(c, 0.95)
      love.graphics.setLineWidth(1.8)
      love.graphics.rectangle("line", tx + 0.5, y + 0.5, tw - 1, tab_h - 1, 4, 4)
      love.graphics.setLineWidth(1)
      col(c, 0.45)
      love.graphics.rectangle("line", tx + 3.5, y + 3.5, tw - 7, tab_h - 7, 3, 3)
      col(c, 1)
      love.graphics.rectangle("fill", tx + 6, y + tab_h - 3, tw - 12, 3)
    else
      col({0.020, 0.040, 0.050}, 0.85)
      love.graphics.rectangle("fill", tx, y, tw, tab_h, 4, 4)
      col(c, 0.35)
      love.graphics.rectangle("line", tx + 0.5, y + 0.5, tw - 1, tab_h - 1, 4, 4)
    end
    love.graphics.setFont(A.font(A.FONT_BODY_BOLD, focused and 11 or 10))
    col(focused and {1,1,1} or {0.65, 0.68, 0.72}, 1)
    love.graphics.printf(tab.label, tx, y + 9, tw, "center")
  end
end

-- ============================================================
--  Main draw
-- ============================================================
function S.draw()
  D.bg()

  local tab = TABS[cur_tab]
  local acc = tab.accent

  -- dark teal ambient
  col(TEAL_LO, 0.08)
  for y = Frame.TOP_H, H - Frame.BOTTOM_H, 16 do
    for x = 0, W, 16 do
      love.graphics.rectangle("fill", x, y, 1, 1)
    end
  end
  D.corner_ticks(4, Frame.TOP_H + 2, W - 8,
    H - Frame.TOP_H - Frame.BOTTOM_H - 4, 18, TEAL_HI, 0.30)

  local hdr_y = Frame.TOP_H + 6
  love.graphics.setFont(A.font(A.FONT_TITLE, 14))
  col(TEAL_HI, 1)
  love.graphics.print("GRiD-Dev", 16, hdr_y)
  love.graphics.setFont(A.font(A.FONT_MONO, 9))
  col(TEAL_HI, 0.7)
  love.graphics.print("  //  " .. tab.label, 16 + 90, hdr_y + 4)

  love.graphics.setFont(A.font(A.FONT_MONO, 9))
  col(TEAL_HI, 0.8)
  love.graphics.printf(string.format("%02d/%02d", cur_tab, NTAB),
    0, hdr_y + 4, W - 16, "right")

  local tab_y = Frame.TOP_H + 26
  draw_tab_bar(16, tab_y, W - 32)

  local cx = 16
  local cy = tab_y + 32 + 8
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
    col(TEAL_HI, 0.55)
    love.graphics.rectangle("fill", W - 6, thumb_y, 3, thumb_h, 1, 1)
  end

  -- SSJ4 mascot HUD: visible on every tab when enabled.
  -- SELECT toggles visibility for the current session.
  if goku_get("show_mascot", true) and not S._mascot_hidden then
    ensure_mascots()
    local entry = mascot.img_r or mascot.img_l
    if entry then
      local size_key = goku_get("size", "medium")
      local target_h = (SIZE_MAP[size_key] or 112) * 0.55
      local sc2 = target_h / entry.h
      local dw = entry.w * sc2
      local dh = entry.h * sc2
      local float_y = math.sin(mascot.phase) * (goku_get("amp", 14) or 14) * 0.6
      local bx = W - dw - 18
      local by = H - Frame.BOTTOM_H - dh - 10 + float_y
      local alpha = (cur_tab == 6) and 0.92 or 0.70
      if goku_get("shadow", true) then
        col({0, 0, 0}, 0.35 * alpha)
        love.graphics.ellipse("fill", bx + dw/2, by + dh + 3, dw * 0.42, 3)
      end
      col({1, 1, 1}, alpha)
      love.graphics.draw(entry.img, bx, by, 0, sc2, sc2)
      col({1, 1, 1}, 1)
    end
  end

  Frame.draw_top("FGD", "grid_dev")
  Frame.draw_bottom({
    { key = "up",     label = "Row" },
    { key = "l/r",    label = "Value" },
    { key = "l1",     label = "Tab" },
    { key = "a",      label = "Run" },
    { key = "select", label = S._mascot_hidden and "Goku on" or "Goku off" },
    { key = "b",      label = "Back" },
  })
  Modal.draw()
  D.scanlines(W, H, 0.06)
  D.vignette(W, H, 0.60)
end

return S
