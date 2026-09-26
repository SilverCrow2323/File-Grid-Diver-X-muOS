-- screens/epub_reader_guide.lua -- EPUB Reader Pro guide.
-- Explains that TOC, bookmarks and themes are already integrated
-- inside GD-X Library. No separate install required.
local A     = require("core.assets")
local State = require("core.state")
local Input = require("core.input_map")
local Frame = require("ui.frame")
local D     = require("ui.draw")
local BI    = require("ui.button_icons")

local S = {}
local W, H = 640, 480
local acc = {0.70, 0.55, 0.92}

local function col(c, a) love.graphics.setColor(c[1], c[2], c[3], a or 1) end

function S.enter() end
function S.leave() end
function S.update(dt) end

function S.pad(b)
  if b == Input.B or b == Input.SELECT or b == Input.A then
    State.back()
  end
end
function S.hat(_) end
function S.key(k)
  if k == "escape" or k == "backspace" or k == "return" then
    State.back()
  end
end

function S.draw()
  local th = State.theme
  D.bg()
  col(acc, 0.06)
  for gy = Frame.TOP_H, H - Frame.BOTTOM_H, 18 do
    for gx = 0, W, 18 do love.graphics.rectangle("fill", gx, gy, 1, 1) end
  end

  love.graphics.setFont(A.font(A.FONT_TITLE, 22))
  col(acc, 1)
  love.graphics.printf("EPUB READER PRO", 0, Frame.TOP_H + 24, W, "center")

  love.graphics.setFont(A.font(A.FONT_MONO, 10))
  col(acc, 0.75)
  love.graphics.printf("// ALREADY INTEGRATED IN GD-X LIBRARY",
    0, Frame.TOP_H + 56, W, "center")

  -- Info box
  local y = Frame.TOP_H + 90
  local x = 40
  local w = W - 80
  local h = 130
  col({0.030, 0.020, 0.045}, 0.95)
  love.graphics.rectangle("fill", x, y, w, h, 5, 5)
  col(acc, 0.85)
  love.graphics.setLineWidth(1.6)
  love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, 5, 5)
  love.graphics.setLineWidth(1)
  D.corner_ticks(x + 8, y + 8, w - 16, h - 16, 12, acc, 0.9)

  love.graphics.setFont(A.font(A.FONT_BODY, 12))
  col(th.text, 0.95)
  love.graphics.printf(
    "EPUB Reader Pro is not a separate plugin.\n\n" ..
    "Its features are already built into GD-X Library:\n" ..
    "open any .epub file from the File Explorer.",
    x + 20, y + 20, w - 40, "left")

  -- Features
  y = y + h + 14
  local features = {
    { "Chapter TOC overlay", "Y" },
    { "Bookmark current page", "START" },
    { "Reading themes: dark, amber, light", "X" },
    { "Previous / next page", "L1 / R1" },
    { "Zoom in / out", "L2 / R2" },
    { "Resume from last position", "auto" },
  }
  love.graphics.setFont(A.font(A.FONT_MONO, 10))
  col(acc, 0.9)
  love.graphics.print("FEATURES", x, y)
  col(acc, 0.3)
  love.graphics.rectangle("fill", x, y + 14, w, 1)
  y = y + 22

  for _, f in ipairs(features) do
    love.graphics.setFont(A.font(A.FONT_BODY, 11))
    col(acc, 0.9)
    love.graphics.print(">", x + 4, y)
    col(th.text, 0.95)
    love.graphics.print(f[1], x + 18, y)
    col(acc, 0.75)
    love.graphics.printf(f[2], 0, y, x + w - 4, "right")
    y = y + 16
  end

  Frame.draw_top("FGD", "plugins")
  Frame.draw_bottom({ { key = "b", label = "Back" } })
  D.scanlines(W, H, 0.06)
end

return S
