-- ui/title_loader.lua -- Choose the right title image based on current theme.
local A = require("core.assets")

local M = {}

-- Return the best title image path for the current theme.
function M.current()
  local ok, State = pcall(require, "core.state")
  local theme = (ok and State.theme_name) or "blame"

  -- Dark / grunge themes use the black version
  if theme == "neon" or theme == "blood" or theme == "toxic" or theme == "deepseek" then
    return "assets/images/titles/title3.png"
  end
  -- Default metal plaque
  return "assets/images/titles/title2.png"
end

-- Draw the title centered horizontally at y with a target height.
function M.draw(W, y, target_h)
  local img = A.image(M.current())
  if not img then return false end
  local iw, ih = img:getDimensions()
  local sc = target_h / ih
  local dw = iw * sc
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(img, W/2 - dw/2, y, 0, sc, sc)
  love.graphics.setColor(1, 1, 1, 1)
  return true
end

return M
