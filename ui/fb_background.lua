-- ui/fb_background.lua -- sfondi Final Bout contestuali.
local A = require("core.assets")
local M = {}

local function active()
  local ok, State = pcall(require, "core.state")
  return ok and State.fb_view_used == true
end

local function audio_active()
  local ok, State = pcall(require, "core.state")
  return ok and State.fb_audio_used == true
end

-- context = "mainmenu" | "settings" | "startup" | "congrats"
-- alpha = opacita' (default 1.0)
function M.draw(context, alpha)
  if not active() then return false end
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

return M
