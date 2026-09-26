-- ui/path_selector.lua -- Reusable "no files found" screen helper.
-- Shows a message, lets the user pick a custom path with the OCK,
-- and calls a callback with the chosen path for rescan.
local A     = require("core.assets")
local D     = require("ui.draw")
local Frame = require("ui.frame")
local KB    = require("ui.keyboard")

local M = {}

-- Render the standard "no files" panel.
-- opts = {
--   title     = "SAVE BACKUP",          -- header
--   message   = "...",                  -- multi-line explanation
--   paths     = {"a", "b", "c"},        -- scanned paths
--   accent    = {r,g,b},
--   on_rescan = function() end,         -- called on X
--   on_pick   = function(path) end,     -- called when user picks a custom path
--   on_back   = function() end,         -- called on B
-- }
function M.draw(opts)
  local W, H = love.graphics.getWidth(), love.graphics.getHeight()
  local acc = opts.accent or {0.70, 0.55, 0.92}
  local th = require("core.state").theme

  love.graphics.setColor(acc[1], acc[2], acc[3], 0.06)
  for gy = Frame.TOP_H, H - Frame.BOTTOM_H, 18 do
    for gx = 0, W, 18 do
      love.graphics.rectangle("fill", gx, gy, 1, 1)
    end
  end

  -- Title
  love.graphics.setFont(A.font(A.FONT_TITLE, 20))
  love.graphics.setColor(acc[1], acc[2], acc[3], 1)
  love.graphics.printf(opts.title or "PLUGIN", 0, Frame.TOP_H + 8, W, "center")

  -- Message panel
  local px = 30
  local py = Frame.TOP_H + 50
  local pw = W - 60

  -- Measure message height
  love.graphics.setFont(A.font(A.FONT_BODY, 11))
  local _, msg_h = love.graphics.getFont():getWrap(opts.message or "", pw - 24)
  local panel_h = math.max(80, msg_h + 40)

  love.graphics.setColor(0.025, 0.020, 0.035, 0.9)
  love.graphics.rectangle("fill", px, py, pw, panel_h, 4, 4)
  love.graphics.setColor(acc[1], acc[2], acc[3], 0.45)
  love.graphics.rectangle("line", px + 0.5, py + 0.5, pw - 1, panel_h - 1, 4, 4)

  love.graphics.setFont(A.font(A.FONT_MONO, 9))
  love.graphics.setColor(acc[1], acc[2], acc[3], 0.9)
  love.graphics.print("MESSAGE", px + 12, py + 6)
  love.graphics.setColor(acc[1], acc[2], acc[3], 0.3)
  love.graphics.rectangle("fill", px + 12, py + 20, pw - 24, 1)

  love.graphics.setFont(A.font(A.FONT_BODY, 11))
  love.graphics.setColor(th.text, 0.95)
  love.graphics.printf(opts.message or "", px + 12, py + 26, pw - 24, "left")

  -- Paths panel
  if opts.paths and #opts.paths > 0 then
    local py2 = py + panel_h + 8
    local rows = #opts.paths
    local ph2 = 24 + rows * 14
    love.graphics.setColor(0.025, 0.020, 0.035, 0.9)
    love.graphics.rectangle("fill", px, py2, pw, ph2, 4, 4)
    love.graphics.setColor(acc[1], acc[2], acc[3], 0.45)
    love.graphics.rectangle("line", px + 0.5, py2 + 0.5, pw - 1, ph2 - 1, 4, 4)

    love.graphics.setFont(A.font(A.FONT_MONO, 9))
    love.graphics.setColor(acc[1], acc[2], acc[3], 0.9)
    love.graphics.print("SCANNED PATHS", px + 12, py2 + 6)
    love.graphics.setColor(acc[1], acc[2], acc[3], 0.3)
    love.graphics.rectangle("fill", px + 12, py2 + 20, pw - 24, 1)

    love.graphics.setFont(A.font(A.FONT_MONO, 10))
    local ry = py2 + 26
    for _, path in ipairs(opts.paths) do
      love.graphics.setColor(acc[1], acc[2], acc[3], 0.7)
      love.graphics.print(">", px + 12, ry)
      love.graphics.setColor(th.text, 0.9)
      love.graphics.print(path, px + 26, ry)
      ry = ry + 14
    end
  end

  -- Footer hints
  local hints = {
    { key = "x", label = "Rescan" },
    { key = "y", label = "Set path" },
    { key = "b", label = "Back" },
  }
  Frame.draw_bottom(hints)

  -- KB overlay if opened
  KB.draw()
end

-- Handle input. Returns true if the input was consumed.
function M.pad(b, opts)
  local Input = require("core.input_map")
  if KB.is_open() then
    KB.pad(b)
    return true
  end
  if b == Input.X then
    if opts.on_rescan then opts.on_rescan() end
    return true
  end
  if b == Input.Y then
    KB.open({
      title = "Enter path",
      initial = (opts.paths and opts.paths[1]) or "/",
      on_accept = function(t)
        if t and t ~= "" and opts.on_pick then opts.on_pick(t) end
      end,
    })
    return true
  end
  if b == Input.B or b == Input.SELECT then
    if opts.on_back then opts.on_back() end
    return true
  end
  return false
end

return M
