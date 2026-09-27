-- main.lua -- Chou Henka Media Center v2.1
local D = require("ui.draw")
local State = require("core.state")
local Notify = require("ui.notify")
local A = require("core.assets")

local CFG = require("plugins.chou_henka.core.config")
local LIB = require("plugins.chou_henka.core.library")
local PB  = require("plugins.chou_henka.core.playback")
local T   = require("plugins.chou_henka.ui.theme")

local Boot     = require("plugins.chou_henka.screens.boot")
local Home     = require("plugins.chou_henka.screens.home")
local Library  = require("plugins.chou_henka.screens.library")
local Player   = require("plugins.chou_henka.screens.player")
local Settings = require("plugins.chou_henka.screens.settings")
local Addons   = require("plugins.chou_henka.screens.addons")
local Search   = require("plugins.chou_henka.screens.search")

local S = {}
S.reserve_select = true
S.escape_passthrough = true
local W, H = 640, 480
local stack = {}
local current, current_name = nil, "boot"
local scan_kicked = false

local SCREENS = {
  boot     = Boot,
  home     = Home,
  library  = Library,
  player   = Player,
  settings = Settings,
  addons   = Addons,
  search   = Search,
}

local function nav_to(name)
  if current and current.leave then pcall(current.leave) end
  current = SCREENS[name]
  current_name = name
  if current and current.enter then pcall(current.enter) end
end

local function go(name)
  if current and current_name ~= name and current_name ~= "boot" then
    stack[#stack+1] = current_name
  end
  nav_to(name)
end

local function back()
  local prev = table.remove(stack)
  if prev and SCREENS[prev] then nav_to(prev)
  else State.back() end
end

function S.enter()
  CFG.load()
  LIB.load()
  stack = {}
  scan_kicked = false
  nav_to("boot")
  local path = State.chou_henka_path
  State.chou_henka_path = nil
  if path and path ~= "" then
    S._pending_play = path
  end
end

function S.leave()
  pcall(function()
    require("plugins.chou_henka.ui.poster").clear()
  end)
  PB.stop()
  LIB.cancel_scan()
  if current and current.leave then pcall(current.leave) end
end

function S.update(dt)
  if LIB.is_scanning() then
    local done = LIB.poll_scan(dt)
    if done then Notify.show("success", "Library scan complete") end
  end

  if current_name == "boot" and Boot.is_done and Boot.is_done() then
    if S._pending_play then
      local p = S._pending_play
      S._pending_play = nil
      nav_to("player")
      if Player.play then Player.play(p) end
    else
      nav_to("home")
    end
    return
  end

  if current and current.update then pcall(current.update, dt) end

  if current_name == "home" and not scan_kicked then
    scan_kicked = true
    if CFG.get("library", "auto_scan_boot") and not LIB.is_scanning() then
      LIB.start_scan()
    end
  end
end

local function handle(r, a)
  if r == "back" then back(); return true end
  if r == "open" then
    go("player")
    if a and a.path and Player.play then Player.play(a.path) end
    return true
  end
  if r == "activate" and a then
    if a.key == "settings"  then go("settings"); return true end
    if a.key == "addons"    then go("addons");   return true end
    if a.key == "search"    then go("search"); return true end
    if a.key == "recent"    then Library.set_category("all"); Library.set_state("resume");   go("library"); return true end
    if a.key == "favorites" then Library.set_category("all"); Library.set_state("favorites");go("library"); return true end
    Library.set_category(a.key); go("library")
    return true
  end
  return r == true
end

function S.pad(b)
  if current_name == "boot" then
    if b == "a" or b == "b" or b == "start" then Boot.skip() end
    return
  end
  if current and current.pad then
    local ok, r, a = pcall(current.pad, b)
    if ok and handle(r, a) then return end
  end
end

function S.hat(dir)
  if current_name == "boot" then Boot.skip(); return end
  if current and current.hat then pcall(current.hat, dir) end
end

function S.key(k)
  if current_name == "boot" then Boot.skip(); return end
  if k == "escape" then
    if current and current.key then
      local ok, r = pcall(current.key, "escape")
      if ok and handle(r) then return end
    end
    back(); return
  end
  if current and current.key then
    local ok, r, a = pcall(current.key, k)
    if ok and handle(r, a) then return end
  end
end

function S.draw()
  if current and current.draw then pcall(current.draw) end

  if current_name ~= "boot" then
    if LIB.is_scanning() then
      local th = T.current()
      love.graphics.setFont(A.font(A.FONT_MONO, 9))
      love.graphics.setColor(th.accent_hi[1], th.accent_hi[2], th.accent_hi[3], 0.9)
      love.graphics.printf("SCANNING LIBRARY...", 0, H - 14, W, "center")
    end
    D.scanlines(W, H, 0.05)
  end
end

return S
