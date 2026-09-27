-- screens/mainmenu.lua -- router con lazy loading robusto.
-- Carica le view on-demand con pcall: se una fallisce, le altre funzionano.
local Store = require("core.settings_store")

-- View base (senza finalbout: quella si sblocca)
local BASE_ORDER = { "console", "hud", "rez" }

-- Cache dei moduli caricati (lazy)
local _cache = {}

local function load_view(key)
  if _cache[key] then return _cache[key] end
  local path = "screens.mainmenu_" .. key
  local ok, mod = pcall(require, path)
  if not ok or type(mod) ~= "table" then
    print("[mainmenu] load FAIL '" .. key .. "': " .. tostring(mod))
    _cache[key] = false
    return nil
  end
  _cache[key] = mod
  return mod
end

-- Ordine attivo: base + finalbout se sbloccata
local function active_order()
  local order = {}
  for _, k in ipairs(BASE_ORDER) do order[#order + 1] = k end
  local unlocked = Store.get("dev", "fb_view_unlocked") == true
  if unlocked then
    order[#order + 1] = "finalbout"
  end
  return order
end

local S = {}
local current_key = "console"

local function sanitize_key(k)
  local order = active_order()
  for _, v in ipairs(order) do
    if v == k then return v end
  end
  -- se la chiave non e' piu' valida (es. finalbout non piu' sbloccata)
  return order[1] or "console"
end

local function current_view()
  local v = load_view(current_key)
  if not v then
    -- fallback in cascata
    for _, k in ipairs(active_order()) do
      local alt = load_view(k)
      if alt then
        current_key = k
        return alt
      end
    end
  end
  return v
end

local function load_saved_key()
  local v = Store.get("ui", "mainmenu_view") or "console"
  return sanitize_key(v)
end

function S.enter()
  current_key = load_saved_key()
  local v = current_view()
  if v and v.enter then pcall(v.enter) end
end

function S.leave()
  local v = current_view()
  if v and v.leave then pcall(v.leave) end
end

function S.update(dt)
  local v = current_view()
  if v and v.update then pcall(v.update, dt) end
end

function S.draw()
  local v = current_view()
  if v and v.draw then
    pcall(v.draw)
  else
    love.graphics.clear(0.05, 0.05, 0.08, 1)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.printf("mainmenu: no view loaded", 0, 240, 640, "center")
  end
end

local function cycle_view(dir)
  local order = active_order()
  local i = 1
  for k, v in ipairs(order) do
    if v == current_key then i = k end
  end
  local prev = current_view()
  if prev and prev.leave then pcall(prev.leave) end
  i = ((i - 1 + dir) % #order + #order) % #order + 1
  current_key = order[i]
  local nv = current_view()
  if nv and nv.enter then pcall(nv.enter) end
  Store.set("ui", "mainmenu_view", current_key)
  Store.save()
  local ok, N = pcall(require, "ui.notify")
  if ok and N.show then N.show("info", "view: " .. current_key) end
end

function S.pad(b)
  if b == "lefttrigger"  then cycle_view(-1); return end
  if b == "righttrigger" then cycle_view( 1); return end
  local v = current_view()
  if v and v.pad then pcall(v.pad, b) end
end

function S.hat(d)
  local v = current_view()
  if v and v.hat then pcall(v.hat, d) end
end

function S.key(k)
  if k == "q" then cycle_view(-1); return end
  if k == "e" then cycle_view( 1); return end
  local v = current_view()
  if v and v.key then pcall(v.key, k) end
end

-- API per forzare il refresh dopo sblocco
S.refresh = function()
  current_key = load_saved_key()
  local v = current_view()
  if v and v.enter then pcall(v.enter) end
end

return S
