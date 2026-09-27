-- ui/fb_background.lua -- sfondi Final Bout contestuali.
local A = require("core.assets")
local M = {}

local function active(context)
  local ok, State = pcall(require, "core.state")
  if not ok or State.fb_view_used ~= true then return false end
  -- startup: mostra FB solo se la view FB è EFFETTIVAMENTE selezionata
  if context == "startup" then
    local ok2, Store = pcall(require, "core.settings_store")
    if not ok2 then return false end
    if Store.get("ui", "mainmenu_view") ~= "finalbout" then return false end
  end
  return true
end

local function audio_active()
  local ok, State = pcall(require, "core.state")
  return ok and State.fb_audio_used == true
end

-- context = "mainmenu" | "settings" | "startup" | "congrats"
-- alpha = opacita' (default 1.0)
function M.draw(context, alpha)
  if not active(context) then return false end
  alpha = alpha or 1.0
  local path
  if context == "mainmenu" then
    local t = love.timer.getTime()
    local frames = { "menu1", "menu2", "menu4" }
    local idx = (math.floor(t / 6) % #frames) + 1
    path = "assets/images/fb/bg/" .. frames[idx] .. ".png"
  elseif context == "settings" then
    path = "assets/images/fb/bg/options.png"
  elseif context == "startup" then
    path = audio_active()
      and "assets/images/fb/bg/startup+.png"
      or  "assets/images/fb/bg/startup.png"
  elseif context == "congrats" then
    path = "assets/images/fb/bg/congrats.png"
  end
  if not path then return false end
  local img = A.image(path)
  if not img then return false end
  local W, H = love.graphics.getWidth(), love.graphics.getHeight()
  local iw, ih = img:getDimensions()
  local sc = math.max(W / iw, H / ih)
  local dw, dh = iw * sc, ih * sc
  love.graphics.setColor(1, 1, 1, alpha)
  love.graphics.draw(img, (W - dw) / 2, (H - dh) / 2, 0, sc, sc)
  love.graphics.setColor(1, 1, 1, 1)
  return true
end

-- ============================================================
--  Per-screen FB background mapping
-- ============================================================
local SCREEN_BG = {
  mainmenu           = "menu1",
  mainmenu_console   = "menu1",
  mainmenu_rez       = "menu2",
  mainmenu_cartridge = "menu4",
  mainmenu_marquee   = "menu1",
  mainmenu_hud       = "menu2",
  mainmenu_finalbout = "menu4",
  settings           = "options",
  grid_dev           = "options",
  about              = "license",
  about_fb           = "congrats",
  about_fb_game      = "finalboss",
  help               = "bgkeyconfig",
  log                = "bgbattle",
  operations         = "bgbattle",
  pad_test           = "bgbattle",
  device             = "Roster",
  storage            = "bgtournament",
  disk_tools         = "bgtournament",
  filex_home         = "bgsky",
  grid               = "bgsky",
  search             = "bgsky",
  archive_rt         = "bgsky",
  editor             = "bgkeyconfig",
  plugins            = "bgdual",
  fgd_plugins        = "bgdual",
  plugin_info        = "bgdual",
  muos_apps          = "bgdual",
  app_detail         = "Roster",
  image_viewer       = "bgbattle",
  video_player       = "bgbattle",
  audio_player       = "bgbattle",
  comic_reader       = "bgbattle",
  gdx_library        = "bgbattle",
  net_sphere         = "bgbattle",
  hex_viewer         = "bgbattle",
  font_preview       = "bgbattle",
  image_resizer      = "bgbattle",
  screenshot_gallery = "bgbattle",
  save_backup        = "bgbattle",
  video_clipper      = "bgbattle",
  office_rt          = "bgsky",
  web_browser        = "bgsky",
  epub_reader_guide  = "bgsky",
}

function M.draw_for_screen(screen_name, alpha)
  if not active(nil) then return false end
  -- solo se la view Final Bout è selezionata
  do
    local ok, Store = pcall(require, "core.settings_store")
    if not ok or Store.get("ui", "mainmenu_view") ~= "finalbout" then
      return false
    end
  end
  if not screen_name then return false end
  if screen_name == "boot" or screen_name == "mainmenu_finalbout" then
    return false
  end
  local bg_name = SCREEN_BG[screen_name]
  if not bg_name then return false end
  local img = A.image("assets/images/fb/bg/" .. bg_name .. ".png")
  if not img then return false end
  local W, H = love.graphics.getWidth(), love.graphics.getHeight()
  local iw, ih = img:getDimensions()
  local sc = math.max(W / iw, H / ih)
  local dw, dh = iw * sc, ih * sc
  love.graphics.setColor(1, 1, 1, alpha or 0.72)
  love.graphics.draw(img, (W - dw) / 2, (H - dh) / 2, 0, sc, sc)
  love.graphics.setColor(1, 1, 1, 1)
  return true
end

return M
