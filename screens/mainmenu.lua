-- screens/mainmenu.lua -- router for FGD://CONSOLE.
-- L2/R2 (or Q/E) cycles between the 5 main menu views.
-- The chosen view is persisted in data/fgd.json under ui.mainmenu_view.
local Store = require("core.settings_store")

local BASE_ORDER = { "console", "rez", "cartridge", "marquee", "hud" }
local VIEWS = {
  console   = require("screens.mainmenu_console"),
  rez       = require("screens.mainmenu_rez"),
  cartridge = require("screens.mainmenu_cartridge"),
  marquee   = require("screens.mainmenu_marquee"),
  hud       = require("screens.mainmenu_hud"),
  finalbout = require("screens.mainmenu_finalbout"),
}

local S = {}
-- VIEW_ORDER dinamico: finalbout solo se sbloccata
local function active_order()
  local order = {}
  for _, k in ipairs(BASE_ORDER) do order[#order+1] = k end
  local ok, Store = pcall(require, "core.settings_store")
  if ok and Store.get("dev", "fb_view_unlocked") == true then
    order[#order+1] = "finalbout"
  end
  return order
end
local current_key = "console"

local function load_key()
  local v = Store.get("ui", "mainmenu_view") or "console"
  if v == "finalbout" and Store.get("dev", "fb_view_unlocked") ~= true then
    v = "console"
  end

  if not VIEWS[v] then v = "console" end
  return v
end

local function pick() return VIEWS[current_key] or VIEWS.console end

local function cycle_view(dir)
  local order = active_order()
  local i = 1
  for k, v in ipairs(order) do
    if v == current_key then i = k end
  end
  i = ((i - 1 + dir) % #order + #order) % #order + 1
  local new_key = order[i]
  local old = VIEWS[current_key]
  if old and old.leave then pcall(old.leave) end
  current_key = new_key
  local nv = VIEWS[new_key]
  if nv and nv.enter then pcall(nv.enter) end
  Store.set("ui", "mainmenu_view", new_key)
  Store.save()
  local ok, N = pcall(require, "ui.notify")
  if ok then N.show("info", "view: " .. new_key) end
  local ok2, SFX = pcall(require, "core.audio")
  if ok2 and SFX and SFX.play then SFX.play("toggle_badge") end
end

function S.enter()  current_key = load_key(); pick().enter() end
function S.leave()  pick().leave() end
function S.update(dt) pick().update(dt) end
function S.draw()   pick().draw() end

function S.pad(b)
  if b == "lefttrigger"  then cycle_view(-1); return end
  if b == "righttrigger" then cycle_view( 1); return end
  pick().pad(b)
end

function S.hat(d) pick().hat(d) end

function S.key(k)
  if k == "q" then cycle_view(-1); return end
  if k == "e" then cycle_view( 1); return end
  pick().key(k)
end

return S
