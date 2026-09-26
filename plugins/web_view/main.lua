local A     = require("core.assets")
local State = require("core.state")
local Input = require("core.input_map")
local Frame = require("ui.frame")
local D     = require("ui.draw")

local S = {}
local W, H = 640, 480
local acc = {0.30, 0.85, 0.95}

local function col(c, a) love.graphics.setColor(c[1], c[2], c[3], a or 1) end

function S.enter() end
function S.leave() end
function S.update(dt) end
function S.pad(b)
  if b == Input.B or b == Input.SELECT then State.back() end
end
function S.hat(d) end
function S.key(k)
  if k == "escape" or k == "backspace" then State.back() end
end

function S.draw()
  D.bg()
  col(acc, 0.06)
  for gy = Frame.TOP_H, H - Frame.BOTTOM_H, 18 do
    for gx = 0, W, 18 do love.graphics.rectangle("fill", gx, gy, 1, 1) end
  end

  love.graphics.setFont(A.font(A.FONT_TITLE, 22))
  col(acc, 1)
  love.graphics.printf("WEB VIEW", 0, Frame.TOP_H + 40, W, "center")

  love.graphics.setFont(A.font(A.FONT_MONO, 10))
  col(acc, 0.75)
  love.graphics.printf("// TRUE HTML RENDERING", 0, Frame.TOP_H + 72, W, "center")

  love.graphics.setFont(A.font(A.FONT_BODY, 12))
  col(State.theme.text, 0.95)
  local y = Frame.TOP_H + 130
  love.graphics.printf(
    "Rendering is handled by Net-Sphere Reader, the built-in\n" ..
    "engine of File-GD X. It parses HTML and displays the\n" ..
    "formatted content -- headings, paragraphs, lists, bold,\n" ..
    "italic, images, preformatted text, links and rules.",
    W/2 - 260, y, 520, "center")

  y = y + 100
  love.graphics.setFont(A.font(A.FONT_MONO, 11))
  col(acc, 0.9)
  love.graphics.printf(
    "Supported tags:  h1 h2 h3 h4 h5 h6  p  br  hr  ul  ol  li\n" ..
    "b  strong  i  em  u  s  a  img  pre  code  blockquote",
    W/2 - 260, y, 520, "center")

  y = y + 70
  love.graphics.setFont(A.font(A.FONT_BODY, 11))
  col(State.theme.text_dim, 0.9)
  love.graphics.printf(
    "Not a web browser: CSS and JavaScript are ignored.\n" ..
    "Perfect for saved articles, docs and offline pages.\n\n" ..
    "Open any .html or .htm file from the File Explorer.",
    W/2 - 260, y, 520, "center")

  Frame.draw_top("FGD", "plugins")
  Frame.draw_bottom({ { key = "b", label = "Back" } })
  D.scanlines(W, H, 0.06)
end

return S
