-- ============================================================
-- main.lua -- File-GD X entry point (definitive edition)
--
-- Responsibilities:
--   1. Load core modules (native, state, input, audio)
--   2. Register native screens + plugins
--   3. Manage the navigation stack (go / back)
--   4. Route input: modal > overlay > keyboard > capture > screen
--   5. Centralized update / draw tick
--
-- Universal input map:
--   A = confirm/activate    B = cancel/back
--   X = quick actions       Y = extra (log, etc.)
--   Start = SPDW panel (grid) / context (elsewhere)
--   Select = back to main menu
--   Start+Select (or Ctrl+Q) = quit app
--   M / guide = status overlay (downloads, ops, system)
--   L1/R1 = switch tab/pane
--   L2/R2 = change view
--   D-pad = navigate / change values
-- ============================================================

-- ------------------------------------------------------------
-- 0. Bootstrap: cpath + probe native modules
-- ------------------------------------------------------------
require("core.native")

local State = require("core.state")
local Input = require("core.input_map")
local SFX   = require("core.audio")

-- ------------------------------------------------------------
-- 1. Screen registry
-- ------------------------------------------------------------
local SCREENS = {
  boot          = require("screens.boot"),
  mainmenu      = require("screens.mainmenu"),
  grid          = require("screens.grid"),
  filex_home    = require("screens.filex_home"),
  muos_apps     = require("screens.muos_apps"),
  app_detail    = require("screens.app_detail"),
  editor        = require("screens.editor"),
  image_viewer  = require("screens.image_viewer"),
  search        = require("screens.search"),
  settings      = require("screens.settings"),
  log           = require("screens.log"),
  about         = require("screens.about"),
  pad_test      = require("screens.pad_test"),
  operations    = require("screens.operations"),
  device        = require("screens.device"),
  plugins       = require("screens.plugins"),
  help          = require("screens.help"),
  grid_dev      = require("screens.grid_dev"),
  storage       = require("screens.storage"),
  fgd_plugins   = require("screens.fgd_plugins"),
  plugin_info          = require("screens.plugin_info"),
  video_clipper = require("screens.video_clipper"),
  epub_reader_guide = require("screens.epub_reader_guide"),
  save_backup = require("screens.save_backup"),
  screenshot_gallery = require("screens.screenshot_gallery"),
  image_resizer = require("screens.image_resizer"),
  font_preview = require("screens.font_preview"),
  hex_viewer = require("screens.hex_viewer"),
  comic_reader = require("screens.comic_reader"),
  web_browser = require("screens.web_browser"),
  archive_rt    = require("screens.archive_rt"),
  gdx_library   = require("screens.gdx_library"),
  net_sphere    = require("screens.net_sphere"),
  office_rt     = require("screens.office_rt"),
  audio_player  = require("screens.audio_player"),
  video_player  = require("screens.video_player"),
}

-- Plugins: dynamic screens registered by the loader
local PluginLoader = require("plugins.loader")
PluginLoader.scan()

local function sync_plugin_screens()
  for _, plug in ipairs(PluginLoader.list()) do
    if plug.key and type(plug.screen) == "table" then
      SCREENS[plug.key] = plug.screen
    end
    -- Some plugins have a folder name that differs from manifest.key
    -- (e.g. plugins/input_holmes/ -> key="input_investigation"). Register
    -- both so State.go() can reach the screen regardless of which
    -- name the caller uses.
    if plug.pkg and plug.pkg ~= plug.key
       and type(plug.screen) == "table" then
      SCREENS[plug.pkg] = plug.screen
    end
    if plug.manage_key and type(plug.manage_screen) == "table" then
      SCREENS[plug.manage_key] = plug.manage_screen
    end
  end
end
sync_plugin_screens()

-- ------------------------------------------------------------
-- 2. Module state
-- ------------------------------------------------------------
local current        = nil      -- active screen table
local current_name   = "?"      -- active screen key
local screen_stack   = {}       -- navigation stack (max 20)
local STACK_MAX      = 20

local FB             = nil      -- ui.finalbout (limit break overlay)
local status_overlay = nil      -- ui.status_overlay (M / guide overlay)

local debug_input    = false    -- F3 overlay
local debug_events   = {}
local DEBUG_MAX      = 14

local HUBS = { mainmenu=true, boot=true, plugins=true,
               settings=true, storage=true, filex_home=true }

-- ------------------------------------------------------------
-- 3. Structured logging with rotation
-- ------------------------------------------------------------
local LOG_PATH      = "data/fgd_runtime.log"
local LOG_MAX_KB    = 512
local log_size_check = 0

local function log(level, msg)
  local line = string.format("[%s] %s", level, tostring(msg))
  print(line)
  local f = io.open(LOG_PATH, "a")
  if not f then return end
  f:write(os.date("%Y-%m-%d %H:%M:%S ") .. line .. "\n")
  f:close()

  -- Rotate: trim to half when file exceeds LOG_MAX_KB
  log_size_check = log_size_check + 1
  if log_size_check > 100 then
    log_size_check = 0
    local rf = io.open(LOG_PATH, "r")
    if rf then
      local sz = rf:seek("end")
      rf:close()
      if sz > LOG_MAX_KB * 1024 then
        local sh = require("core.sh")
        os.execute("tail -c " .. (LOG_MAX_KB * 512) .. " " ..
          sh.shq(LOG_PATH) .. " > " ..
          sh.shq(LOG_PATH .. ".tmp") .. " 2>/dev/null && " ..
          "mv " .. sh.shq(LOG_PATH .. ".tmp") .. " " ..
          sh.shq(LOG_PATH))
      end
    end
  end
end

local function report(where, err)
  log("ERR", where .. ": " .. tostring(err))
end

-- ------------------------------------------------------------
-- 4. Safe access to the current screen
-- ------------------------------------------------------------
local function has_screen()
  return type(current) == "table"
end

local function call_screen(method, ...)
  if not has_screen() then return end
  local fn = current[method]
  if type(fn) ~= "function" then return end
  local ok, err = pcall(fn, ...)
  if not ok then report(method, err) end
end

-- ------------------------------------------------------------
-- 5. Switch screen
-- ------------------------------------------------------------
local function switch(name)
  if has_screen() and type(current.leave) == "function" then
    pcall(current.leave)
  end

  local screen = SCREENS[name]
  if type(screen) ~= "table" then
    log("WARN", "SCREENS[" .. tostring(name) .. "] invalid, fallback to boot")
    screen = SCREENS.boot
  end
  if type(screen) ~= "table" then
    log("ERR", "no valid screen for " .. tostring(name))
    screen = nil
  end

  current      = screen
  current_name = name

  if has_screen() and type(current.enter) == "function" then
    local ok, err = pcall(current.enter)
    if not ok then report("enter", err) end
  end
  State._screen_enter_t = love.timer.getTime()
end

-- ------------------------------------------------------------
-- 6. State.go / State.back (public API)
-- ------------------------------------------------------------
function State.go(name, opts)
  opts = opts or {}

  -- Refresh plugin screens (in case of rescan)
  sync_plugin_screens()

  if type(SCREENS[name]) ~= "table" then
    log("ERR", "State.go: screen '" .. tostring(name) ..
      "' not registered (type=" .. type(SCREENS[name]) .. "), fallback to mainmenu")
    name = "mainmenu"
  end

  if opts.replace then
    -- replace current screen without pushing to stack
  elseif HUBS[name] then
    screen_stack = {}
  elseif current_name
     and current_name ~= name
     and current_name ~= "boot" then
    -- Push even if current is an hub: allows back from sub-screens
    -- (About/Help/Log from Settings, plugin screens from Plugins, etc.)
    screen_stack[#screen_stack + 1] = current_name
    if #screen_stack > STACK_MAX then
      table.remove(screen_stack, 1)
    end
  end

  switch(name)
end

function State.back()
  local prev = table.remove(screen_stack)
  if prev and SCREENS[prev] then
    State._returning = true
    switch(prev)
    State._returning = nil
    return
  end
  if current == SCREENS.mainmenu then
    love.event.quit()
  else
    switch("mainmenu")
  end
end

-- ------------------------------------------------------------
-- 7. Input dedup (d-pad + stick overlap)
-- ------------------------------------------------------------
local last_dispatch = {}
local DEDUP_WINDOW  = 0.20

local function dedup(k)
  local now = love.timer.getTime()
  if last_dispatch[k] and (now - last_dispatch[k]) < DEDUP_WINDOW then
    return false
  end
  last_dispatch[k] = now
  return true
end

local function direction_key(name)
  if name == "dpup"    or name == "up"    then return "dir:up"    end
  if name == "dpdown"  or name == "down"  then return "dir:down"  end
  if name == "dpleft"  or name == "left"  then return "dir:left"  end
  if name == "dpright" or name == "right" then return "dir:right" end
  return nil
end

local function pass_dedup(prefix, name)
  local dk = direction_key(name)
  return dedup(dk or (prefix .. ":" .. name))
end

-- ------------------------------------------------------------
-- 8. Debug overlay
-- ------------------------------------------------------------
local function log_input(kind, value)
  if not debug_input then return end
  debug_events[#debug_events + 1] = {
    t = love.timer.getTime(), kind = kind, value = tostring(value),
  }
  while #debug_events > DEBUG_MAX do
    table.remove(debug_events, 1)
  end
end

-- ------------------------------------------------------------
-- 9. Sound: per-screen nav variant
-- ------------------------------------------------------------
local NAV_VARIANT = {
  settings = "nav2", device = "nav2", about = "nav2", pad_test = "nav2",
  plugins  = "nav2", help   = "nav2",
  log      = "nav3", operations = "nav3", storage = "nav3",
  grid_dev = "nav3", tech_us = "nav3", input_investigation = "nav3",
}

local function nav_sound()
  return NAV_VARIANT[current_name] or "nav"
end

local function play_sfx(name)
  if name == "a" then
    SFX.play("enter")
  elseif name == "b" then
    SFX.play("back")
  elseif name == "dpup" or name == "dpdown"
      or name == "dpleft" or name == "dpright" then
    SFX.play(nav_sound())
  elseif name == "leftshoulder" or name == "rightshoulder" then
    SFX.play("nav2")
  elseif name == "lefttrigger" or name == "righttrigger" then
    SFX.play("nav3")
  end
end

-- ------------------------------------------------------------
-- 10. Capture mode (Input Holmes)
-- ------------------------------------------------------------
local function capture_active()
  if not has_screen() then return false end
  local wc = current.wants_capture
  if type(wc) ~= "function" then return false end
  local ok, wants = pcall(wc)
  return ok and wants == true
end

-- ------------------------------------------------------------
-- 11. Final Bout (Konami sequence)
-- ------------------------------------------------------------
-- FGDX_FB_VIEW_SEQ: codice 1 -- sblocca la view Final Bout
local FB_VIEW_SEQ = { "dpright", "dpleft", "dpdown", "dpup",
                     "dpright", "dpleft", "dpdown", "dpup" }
local FB_VIEW_BUF = {}

-- FGDX_FB_AUDIO_SEQ: codice 2 -- sblocca FB AUDIO MODE
-- (8x X, poi 8x Y). Uso sequenze separate per i due tasti.
local FB_AUDIO_X_COUNT = 8
local FB_AUDIO_Y_COUNT = 8
local FB_AUDIO_X_BUF = 0
local FB_AUDIO_Y_BUF = 0

local FB_SEQ = { "dpright", "dpleft", "dpdown", "dpup",
                 "dpright", "dpleft", "dpdown", "dpup", "start" }
local FB_BUF = {}

local function fb_check(name)
  if not FB then return false end

-- FGDX_FB_VIEW: codice 1
local function fb_view_check(name)
  if not FB then return false end
  if current_name ~= "mainmenu" then FB_VIEW_BUF = {}; return false end
  FB_VIEW_BUF[#FB_VIEW_BUF + 1] = name
  if #FB_VIEW_BUF > #FB_VIEW_SEQ then table.remove(FB_VIEW_BUF, 1) end
  if #FB_VIEW_BUF < #FB_VIEW_SEQ then return false end
  for i = 1, #FB_VIEW_SEQ do
    if FB_VIEW_BUF[i] ~= FB_VIEW_SEQ[i] then return false end
  end
  FB_VIEW_BUF = {}
  return true
end

-- FGDX_FB_AUDIO: codice 2 (8x X, poi 8x Y)
local function fb_audio_check_x(name)
  if current_name ~= "mainmenu" then FB_AUDIO_X_BUF = 0; return false end
  if name == "x" then
    FB_AUDIO_X_BUF = FB_AUDIO_X_BUF + 1
    if FB_AUDIO_X_BUF >= FB_AUDIO_X_COUNT then
      FB_AUDIO_X_BUF = 0
      return true
    end
  else
    FB_AUDIO_X_BUF = 0
  end
  return false
end

local function fb_audio_check_y(name)
  if current_name ~= "mainmenu" then FB_AUDIO_Y_BUF = 0; return false end
  if name == "y" then
    FB_AUDIO_Y_BUF = FB_AUDIO_Y_BUF + 1
    if FB_AUDIO_Y_BUF >= FB_AUDIO_Y_COUNT then
      FB_AUDIO_Y_BUF = 0
      return true
    end
  else
    FB_AUDIO_Y_BUF = 0
  end
  return false
end

  if current_name ~= "mainmenu" or FB.active then
    FB_BUF = {}
    return false
  end
  FB_BUF[#FB_BUF + 1] = name
  if #FB_BUF > #FB_SEQ then table.remove(FB_BUF, 1) end
  if #FB_BUF < #FB_SEQ then return false end
  for i = 1, #FB_SEQ do
    if FB_BUF[i] ~= FB_SEQ[i] then return false end
  end
  FB_BUF = {}
  return true
end

-- ------------------------------------------------------------
-- 12. Held d-pad auto-repeat
-- ------------------------------------------------------------
local held_dirs = {}
local HOLD_DELAY = 0.45
local HOLD_RATE  = 0.08

local dispatch_pad_no_dedup   -- forward decl

local function register_hold(name)
  held_dirs[name] = { next_t = love.timer.getTime() + HOLD_DELAY }
end
local function clear_hold(name) held_dirs[name] = nil end
local function clear_all_holds() held_dirs = {} end

local function tick_holds()
  local now = love.timer.getTime()
  for name, h in pairs(held_dirs) do
    if now >= h.next_t then
      dispatch_pad_no_dedup(name)
      h.next_t = now + HOLD_RATE
    end
  end
end

-- ------------------------------------------------------------
-- 13. Analog sticks
-- ------------------------------------------------------------
local stick = { lx = 0, ly = 0, rx = 0, ry = 0 }
local stick_prev = { l = nil, r = nil }
local stick_next = { l = 0, r = 0 }
local STICK_DZ          = 0.50
local STICK_HOLD_DELAY  = 0.40
local STICK_HOLD_RATE   = 0.09

local function process_stick(which, x, y)
  local dir = nil
  if math.abs(x) > math.abs(y) then
    if     x >  STICK_DZ then
      dir = (which == "l") and "dpright" or "rightshoulder"
    elseif x < -STICK_DZ then
      dir = (which == "l") and "dpleft"  or "leftshoulder"
    end
  else
    if     y >  STICK_DZ then
      dir = (which == "l") and "dpdown" or "righttrigger"
    elseif y < -STICK_DZ then
      dir = (which == "l") and "dpup"   or "lefttrigger"
    end
  end
  local now = love.timer.getTime()
  if dir ~= stick_prev[which] then
    stick_prev[which] = dir
    stick_next[which] = now + STICK_HOLD_DELAY
    if dir then dispatch_pad_no_dedup(dir) end
  elseif dir and now >= stick_next[which] then
    stick_next[which] = now + STICK_HOLD_RATE
    dispatch_pad_no_dedup(dir)
  end
end

-- ------------------------------------------------------------
-- 14. Modal / keyboard / overlay helpers
-- ------------------------------------------------------------
local function modal_open()
  local ok, M = pcall(require, "ui.modal")
  if ok and M and M.current then return true end
  return false
end

local function keyboard_open()
  local ok, K = pcall(require, "ui.keyboard")
  if ok and K and K.is_open and K.is_open() then return true end
  return false
end

local function overlay_open()
  return status_overlay
     and status_overlay.is_open
     and status_overlay.is_open()
end

-- ------------------------------------------------------------
-- 15. Pad dispatch (no dedup, used by auto-repeat)
-- ------------------------------------------------------------
dispatch_pad_no_dedup = function(name)
  if not name then return end

  -- Modal absorbs A/B
  if modal_open() then
    local M = require("ui.modal")
    if name == "a" then M.accept()
    elseif name == "b" or name == "back" then M.cancel() end
    return
  end

  if capture_active() then
    if type(current.capture_input) == "function" then
      pcall(current.capture_input, "gamepad", name)
    end
    return
  end

  log_input("pad", name)
  play_sfx(name)

  -- Directional: prefer S.hat, fall back to S.pad
  local DIRECTIONAL_MAP = {
    dpup    = "up",
    dpdown  = "down",
    dpleft  = "left",
    dpright = "right",
  }
  local dir = DIRECTIONAL_MAP[name]
  if dir and has_screen() then
    if type(current.hat) == "function" then
      local ok, err = pcall(current.hat, dir)
      if not ok then report("hat", err) end
      return
    end
    if type(current.pad) == "function" then
      local ok, err = pcall(current.pad, name)
      if not ok then report("pad", err) end
      return
    end
  end

  call_screen("pad", name)
end

-- ------------------------------------------------------------
-- 16. Pad dispatch (full, with dedup and overlay routing)
-- ------------------------------------------------------------
local dispatch_pad
dispatch_pad = function(name)
  if not name then return end

  -- 1. Modal has absolute priority
  if modal_open() then
    local M = require("ui.modal")
    if name == "a" then M.accept()
    elseif name == "b" or name == "back" then M.cancel() end
    return
  end

  -- 2. Status overlay: any of these closes it
  if overlay_open() then
    if name == "b" or name == "a" or name == "back"
       or name == "guide" or name == "start" then
      status_overlay.close()
    end
    return
  end

  -- 3. Guide opens/closes overlay
  if name == "guide" then
    if status_overlay then status_overlay.toggle() end
    return
  end

  -- 4. Capture mode
  if capture_active() then
    if type(current.capture_input) == "function" then
      pcall(current.capture_input, "gamepad", name)
    end
    return
  end

  if not pass_dedup("pad", name) then return end

  -- Periodo di grazia: ignora input ravvicinati al cambio schermata
  if State._screen_enter_t
     and (love.timer.getTime() - State._screen_enter_t) < 0.20 then
    return
  end

  log_input("pad", name)

  -- 5. Screen may override default SFX (for toggles/enums/sliders)
  local skip_default = false
  if has_screen() and type(current.override_sfx) == "function" then
    local ok, ov = pcall(current.override_sfx, name)
    if ok and ov == true then skip_default = true end
  end
  if not skip_default then play_sfx(name) end

  -- 6. Select universal: back to main menu unless screen reserves it
  if name == "back" and not modal_open() and not keyboard_open()
     and not (has_screen() and current.reserve_select) then
    State.go("mainmenu")
    return
  end

  -- 7. Directional inputs: try S.hat first, then fall back to S.pad.
  -- On muOS the d-pad often arrives as "dpup" (SDL button), not as an hat
  -- event. Screens like grid.lua only define S.hat, screens like filex_home
  -- only define S.pad. Handle both, in that order.
  local DIRECTIONAL_MAP = {
    dpup    = "up",
    dpdown  = "down",
    dpleft  = "left",
    dpright = "right",
  }
  local dir = DIRECTIONAL_MAP[name]
  if dir and has_screen() then
    if type(current.hat) == "function" then
      local ok, err = pcall(current.hat, dir)
      if not ok then report("hat", err) end
      return
    end
    if type(current.pad) == "function" then
      local ok, err = pcall(current.pad, name)
      if not ok then report("pad", err) end
      return
    end
  end

  call_screen("pad", name)
end

-- ------------------------------------------------------------
-- 17. Key dispatch
-- ------------------------------------------------------------
local dispatch_key
dispatch_key = function(k)
  if not k then return end

  -- Modal has priority
  if modal_open() then
    local M = require("ui.modal")
    if k == "return" or k == "space" then M.accept()
    elseif k == "escape" or k == "backspace" then M.cancel() end
    return
  end

  if not dedup("key:" .. k) then return end
  log_input("key", k)
  call_screen("key", k)
end

-- ------------------------------------------------------------
-- 18. love.load
-- ------------------------------------------------------------
function love.load()
  FB             = require("ui.finalbout")
  status_overlay = require("ui.status_overlay")

  -- Settings (with dev_unlocked migration)
  local Store = require("core.settings_store")
  Store.load()

  -- FONT_SCALE_MIGRATION_V4: bump per leggibilità su 640x480 @ 3.5"
  do
    local fs = Store.get("ui", "font_scale")
    if type(fs) ~= "number" or fs < 1.30 then
      Store.set("ui", "font_scale", 1.40)
      Store.save()
      print("[migrate] font_scale -> 1.40")
    end
  end

  if Store.get("ui", "dev_unlocked") ~= nil then
    Store.set("ui", "dev_unlocked", nil)
    Store.save()
  end
  State.dev_unlocked = (Store.get("dev", "persist_unlock") == true)
  -- FGDX_FB_LOAD: ripristina stato FB
  State.fb_view_used = (Store.get("dev", "fb_view_unlocked") == true)
  State.fb_audio_used = (Store.get("dev", "fb_audio_unlocked") == true)
  State.fb_audio_awaiting_y = false
  if State.fb_audio_used then
    pcall(function() require("core.audio").set_fb_mode(true) end)
  end


  -- Theme from settings
  local theme_name = Store.get("general", "theme") or "blame"
  local ok, mod = pcall(require, "themes.theme_" .. theme_name)
  if ok and type(mod) == "table" then
    State.theme_name = theme_name
    State.theme = mod
  else
    State.theme_name = "blame"
    State.theme = require("themes.theme_blame")
  end

  -- Assets + audio
  require("core.assets").init()
  SFX.load()
  SFX.set_enabled(Store.get("sound", "enabled") == true)
  local vol = Store.get("sound", "volume")
  if type(vol) == "number" then
    SFX.set_volume(math.max(0, math.min(1, vol / 100)))
  end

  -- State defaults
  State.booted               = false
  State.konami_used          = false
  State.mainmenu_intro_shown = false
  State.root_path            = love.filesystem.getSource() or "."
  State.t_ui                 = 0
  State.cwd                  = os.getenv("HOME") or "/tmp"

  love.graphics.setBackgroundColor(State.theme.bg)
  love.graphics.setDefaultFilter("linear", "linear")

  log("INFO", "File-GD X started. Theme: " .. State.theme_name)

  switch("boot")

  -- Avvio in background di catalog refresh + app version check.
  do
    local Cat = require("services.catalog")
    State.app_version = "v1.5.0"  -- aggiorna qui o leggi da version.txt
    if Cat.refresh_on_boot then Cat.refresh_on_boot() end
    if Cat.check_app_version_async then
      Cat.check_app_version_async(State.app_version)
    end
    catalog_poll_t = 0
  end
end

-- ------------------------------------------------------------
-- 19. love.update
-- ------------------------------------------------------------
function love.update(dt)
  State.t_ui = (State.t_ui or 0) + dt

  -- Poll del risultato update check (una volta ogni ~2s, max 5 tentativi)
  if catalog_poll_t and catalog_poll_t < 10 then
    catalog_poll_t = catalog_poll_t + dt
    if catalog_poll_t >= 2 then
      catalog_poll_t = 99
      pcall(function()
        require("services.catalog").poll_update_result(State.app_version)
      end)
    end
  end

  -- Plugin intro animation
  do
    local PI = require("ui.plugin_intro")
    PI.update(dt)
  end

  -- Asset sync (cached fonts)
  pcall(function() require("core.assets").sync() end)
  pcall(function() require("ui.frame").sync() end)
  pcall(function() SFX.update_bgm(dt) end)

  -- Status overlay animation
  if status_overlay and status_overlay.update then
    status_overlay.update(dt)
  end

  if FB and FB.update then FB.update(dt) end

  -- FGDX_FB_JINGLE: suona finalbout_griddev2 dopo la conferma
  if State._fb_jingle_t and State._fb_jingle_t > 0 then
    State._fb_jingle_t = State._fb_jingle_t - dt
    if State._fb_jingle_t <= 0 then
      State._fb_jingle_t = nil
      local ok, SFX = pcall(require, "core.audio")
      if ok and SFX.play then SFX.play("finalbout_griddev2") end
    end
  end


  -- Keyboard OCK has priority
  local KB = require("ui.keyboard")
  if KB.is_open() then
    KB.update(dt)
    return
  end

  call_screen("update", dt)

  require("ui.notify").update(dt)
  require("ui.modal").update(dt)
  tick_holds()
end

-- ------------------------------------------------------------
-- 20. love.draw
-- ------------------------------------------------------------
function love.draw()
  call_screen("draw")

  -- Plugin intro overlay (drawn above screen, below modals)
  do
    local PI = require("ui.plugin_intro")
    if PI.is_active() then
      PI.draw()
      return
    end
  end

  require("ui.notify").draw(640, 480)
  require("ui.modal").draw()
  require("ui.keyboard").draw()
  if status_overlay and status_overlay.draw then
    status_overlay.draw()
  end
  if FB and FB.draw then FB.draw() end

  if debug_input then
    love.graphics.setColor(0, 0, 0, 0.85)
    love.graphics.rectangle("fill", 8, 60, 260, 200, 4, 4)
    love.graphics.setColor(1, 0.7, 0.3, 1)
    love.graphics.rectangle("line", 8.5, 60.5, 259, 199, 4, 4)
    love.graphics.print("INPUT DEBUG (F3)", 16, 66)
    love.graphics.print("screen: " .. current_name, 16, 82)
    for i, e in ipairs(debug_events) do
      if i > 12 then break end
      love.graphics.print(
        string.format("%.2f  %s  %s", e.t % 100, e.kind, e.value),
        16, 100 + (i - 1) * 14)
    end
  end
end

function love.focus(f)
  if not f then
    clear_all_holds()
  end
end

-- ------------------------------------------------------------
-- 21. Gamepad events
-- ------------------------------------------------------------
local held_buttons = {}

function love.gamepadpressed(_, name)
  -- Plugin intro: any button skips it
  do
    local PI = require("ui.plugin_intro")
    if PI.is_active() then
      PI.skip()
      return
    end
  end

  -- Modal absorbs A/B
  if modal_open() then
    local M = require("ui.modal")
    if name == "a" then M.accept()
    elseif name == "b" or name == "back" then M.cancel() end
    return
  end

  held_buttons[name] = love.timer.getTime()

  -- Start+Select => quit (either order)
  if (name == "start" and held_buttons["back"])
     or (name == "back" and held_buttons["start"]) then
    love.event.quit()
    return
  end

  if FB and FB.active then return end

  if capture_active() then
    if type(current.capture_input) == "function" then
      pcall(current.capture_input, "gamepad", name)
    end
    return
  end

  if not State.dev_unlocked and not State.konami_used and fb_check(name) then
    State.konami_used = true
    FB.trigger(function()
      State.dev_unlocked = true
      local ok, N = pcall(require, "ui.notify")
      if ok then N.show("success", "GRiD-Dev unlocked -- Settings > SYSTEM", 4.0) end
    end)
    return
  end

  -- FGDX_FB_VIEW: codice 1 -- sblocca la view Final Bout
  if not State.fb_view_used and fb_view_check(name) then
    State.fb_view_used = true
    local ok, Store = pcall(require, "core.settings_store")
    if ok then Store.set("dev", "fb_view_unlocked", true); Store.save() end
    local ok2, SFX = pcall(require, "core.audio")
    if ok2 and SFX.play then SFX.play("finalbout") end
    local ok3, N = pcall(require, "ui.notify")
    if ok3 then N.show("success", "FINAL BOUT view unlocked (L2/R2)", 4.0) end
    return
  end

  -- FGDX_FB_AUDIO: codice 2 -- sblocca FB AUDIO MODE
  if not State.fb_audio_used and fb_audio_check_x(name) then
    -- Primo pezzo: X x8. Ora aspettiamo Y x8.
    State.fb_audio_awaiting_y = true
    return
  end
  if State.fb_audio_awaiting_y and fb_audio_check_y(name) then
    State.fb_audio_awaiting_y = false
    State.fb_audio_used = true
    local ok, Store = pcall(require, "core.settings_store")
    if ok then Store.set("dev", "fb_audio_unlocked", true); Store.save() end
    local ok2, SFX = pcall(require, "core.audio")
    if ok2 and SFX.play then
      SFX.play("finalbout")           -- conferma
      SFX.set_fb_mode(true)            -- attiva modalita'
      -- jingle dopo un piccolo delay
      State._fb_jingle_t = 0.35
    end
    local ok3, N = pcall(require, "ui.notify")
    if ok3 then N.show("success", "FB AUDIO MODE unlocked", 4.0) end
    return
  end


  if name == "dpup" or name == "dpdown"
     or name == "dpleft" or name == "dpright" then
    register_hold(name)
  end

  dispatch_pad(name)
end

function love.gamepadreleased(_, name)
  held_buttons[name] = nil
  if name == "dpup" or name == "dpdown"
     or name == "dpleft" or name == "dpright" then
    clear_hold(name)
  end
end

-- ------------------------------------------------------------
-- 22. Raw joystick events
-- ------------------------------------------------------------
function love.joystickpressed(_, num)
  if modal_open() then return end
  if capture_active() then
    if type(current.capture_input) == "function" then
      pcall(current.capture_input, "button", num)
    end
    return
  end
  local logical  = Input.raw_to_logical[num]
  local sdl_name = logical and Input.logical_to_sdl[logical]
  if sdl_name then
    dispatch_pad(sdl_name)
  end
end

function love.joystickhat(_, _, dir)
  if modal_open() then return end
  if dir == "c" then
    clear_hold("dpup"); clear_hold("dpdown")
    clear_hold("dpleft"); clear_hold("dpright")
    return
  end
  local map = {
    u="up", d="down", l="left", r="right",
    ru="up", rd="down", lu="up", ld="down",
  }
  local d = map[dir]
  if capture_active() then
    if type(current.capture_input) == "function" then
      pcall(current.capture_input, "hat", dir)
    end
    return
  end
  if d then
    if not pass_dedup("hat", d) then return end
    log_input("hat", d)
    SFX.play(nav_sound())
    call_screen("hat", d)
  end
end

function love.joystickaxis(_, axis, value)
  if modal_open() then return end
  if capture_active() then
    if type(current.capture_input) == "function" then
      pcall(current.capture_input, "axis", { axis = axis, value = value })
    end
    return
  end
  if axis == 4 then
    if math.abs(value) >= 0.5 then dispatch_pad("lefttrigger") end
    return
  elseif axis == 5 then
    if math.abs(value) >= 0.5 then dispatch_pad("righttrigger") end
    return
  end
  if     axis == 0 then stick.lx = value; process_stick("l", stick.lx, stick.ly)
  elseif axis == 1 then stick.ly = value; process_stick("l", stick.lx, stick.ly)
  elseif axis == 2 then stick.rx = value; process_stick("r", stick.rx, stick.ry)
  elseif axis == 3 then stick.ry = value; process_stick("r", stick.rx, stick.ry)
  end
end

-- ------------------------------------------------------------
-- 23. Keyboard events
-- ------------------------------------------------------------
-- Physical key -> SDL pad name
local K2P = {
  ["a"]="a", ["b"]="b", ["x"]="x", ["y"]="y",
  ["1"]="leftshoulder", ["2"]="lefttrigger",
  ["3"]="righttrigger", ["4"]="rightshoulder",
  ["backslash"]="back", ["\\"]="back",
  ["up"]="dpup", ["down"]="dpdown",
  ["left"]="dpleft", ["right"]="dpright",
}

function love.keypressed(k)
  -- Plugin intro: any key skips it and is consumed
  do
    local PI = require("ui.plugin_intro")
    if PI.is_active() then
      PI.skip()
      return
    end
  end

  -- Modal absorbs everything
  if modal_open() then
    local M = require("ui.modal")
    if k == "return" or k == "space" or k == "enter" then M.accept()
    elseif k == "escape" or k == "backspace" then M.cancel() end
    return
  end

  if FB and FB.active then return end

  -- Ctrl+Q = quit
  if k == "q" and love.keyboard.isDown("lctrl", "rctrl") then
    love.event.quit()
    return
  end

  -- Keyboard OCK has priority
  local KB = require("ui.keyboard")
  if KB.is_open() then
    KB.key(k)
    return
  end

  -- Status overlay
  if overlay_open() then
    if k == "m" or k == "escape" or k == "return"
       or k == "space" or k == "backspace" then
      status_overlay.close()
    end
    return
  end
  if k == "m" then
    if status_overlay then status_overlay.toggle() end
    return
  end

  -- F3 debug overlay
  if k == "f3" then
    debug_input = not debug_input
    debug_events = {}
    return
  end

  -- Escape => mainmenu (screen may intercept via escape_passthrough)
  if k == "escape" then
    if has_screen() and current.escape_passthrough
       and type(current.key) == "function" then
      pcall(current.key, "escape")
      return
    end
    if current == SCREENS.mainmenu then
      love.event.quit()
    else
      State.go("mainmenu")
    end
    return
  end

  -- Keyboard -> pad emulation
  local raw = has_screen() and current.raw_keys == true
  local pad = (not raw) and K2P[k]
  if pad then
    -- Konami sequence from keyboard
    if not State.dev_unlocked and not State.konami_used
         and current_name == "mainmenu" and fb_check(pad) then
      State.konami_used = true
      FB.trigger(function()
        State.dev_unlocked = true
        local ok, N = pcall(require, "ui.notify")
        if ok then N.show("success", "GRiD-Dev unlocked -- Settings > SYSTEM", 4.0) end
      end)
      return
end
    -- Directional -> hat
    local DIR = { dpup="up", dpdown="down", dpleft="left", dpright="right" }
    if DIR[pad] then
      if not pass_dedup("hat", DIR[pad]) then return end
      log_input("hat", DIR[pad])
      SFX.play(nav_sound())
      call_screen("hat", DIR[pad])
    else
      dispatch_pad(pad)
    end
    return
  end

  -- Raw key
  dispatch_key(k)
end

function love.textinput(txt)
  if not has_screen() then return end
  local fn = current.textinput
  if type(fn) == "function" then
    local ok, err = pcall(fn, txt)
    if not ok then report("textinput", err) end
  end
end

-- ------------------------------------------------------------
-- 24. Public API for plugins
-- ------------------------------------------------------------
package.loaded["main"] = {
  get_current      = function() return current end,
  get_current_name = function() return current_name end,
  switch           = switch,
  register_screen  = function(key, screen)
    if type(key) == "string" and type(screen) == "table" then
      SCREENS[key] = screen
    end
  end,
}
