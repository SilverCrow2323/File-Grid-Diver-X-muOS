-- screens/font_preview.lua -- Font Preview plugin.
local A     = require("core.assets")
local State = require("core.state")
local Input = require("core.input_map")
local Frame = require("ui.frame")
local D     = require("ui.draw")
local PathSel = require("ui.path_selector")

local S = {}
local W, H = 640, 480
local acc = {0.85, 0.70, 1.00}

local font_path = nil
local loaded_fonts = {}
local pangram = "The quick brown fox jumps over the lazy dog 0123456789"
local sizes = { 12, 18, 24, 36 }
local t_enter = 0
local scroll = 0
local max_scroll = 0

local function col(c, a) love.graphics.setColor(c[1], c[2], c[3], a or 1) end
local function basename(p) return (p or ""):match("([^/]+)$") or p or "?" end

local function load_all()
  loaded_fonts = {}
  if not font_path then return end
  for _, sz in ipairs(sizes) do
    local ok, fnt = pcall(love.graphics.newFont, font_path, sz)
    if ok and fnt then
      loaded_fonts[sz] = fnt
    end
  end
end

function S.enter()
  t_enter = 0
  scroll = 0
  font_path = State.font_preview_path
  State.font_preview_path = nil
  if not font_path then
    -- Scan assets/fonts and data/
    local candidates = {
      "assets/fonts/Oxanium-Regular.ttf",
      "assets/fonts/Oxanium-Bold.ttf",
      "assets/fonts/JetBrainsMono-Regular.ttf",
    }
    for _, c in ipairs(candidates) do
      local f = io.open(c, "rb")
      if f then f:close(); font_path = c; break end
    end
  end
  load_all()
end
function S.leave() end
function S.update(dt) t_enter = t_enter + dt end

function S.pad(b)
  if not font_path then
    PathSel.pad(b, {
      paths = { "assets/fonts/", "data/fonts/" },
      on_rescan = function()
        for _, c in ipairs({
          "assets/fonts/Oxanium-Regular.ttf",
          "assets/fonts/Oxanium-Bold.ttf",
          "assets/fonts/JetBrainsMono-Regular.ttf",
        }) do
          local f = io.open(c, "rb")
          if f then f:close(); font_path = c; load_all(); break end
        end
      end,
      on_pick = function(p)
        font_path = p
        load_all()
        Notify.show("info", "font loaded")
      end,
      on_back = function() State.back() end,
    })
    return
  end
  if     b == Input.B or b == Input.SELECT then State.back()
  elseif b == Input.UP   then scroll = math.max(0, scroll - 30)
  elseif b == Input.DOWN then scroll = scroll + 30 end
end
function S.hat(dir)
  if     dir == "up"   then scroll = math.max(0, scroll - 30)
  elseif dir == "down" then scroll = scroll + 30 end
end
function S.key(k)
  if     k == "escape" or k == "backspace" then State.back()
  elseif k == "up"   then scroll = math.max(0, scroll - 30)
  elseif k == "down" then scroll = scroll + 30 end
end

function S.draw()
  local th = State.theme
  D.bg()
  col(acc, 0.06)
  for gy = Frame.TOP_H, H - Frame.BOTTOM_H, 18 do
    for gx = 0, W, 18 do love.graphics.rectangle("fill", gx, gy, 1, 1) end
  end

  love.graphics.setFont(A.font(A.FONT_TITLE, 20))
  col(acc, 1)
  love.graphics.printf("FONT PREVIEW", 0, Frame.TOP_H + 8, W, "center")

  love.graphics.setFont(A.font(A.FONT_MONO, 10))
  col(acc, 0.75)
  local title = basename(font_path or "no font")
  love.graphics.printf(title, 0, Frame.TOP_H + 34, W, "center")

  local vp_y = Frame.TOP_H + 54
  local vp_h = H - Frame.BOTTOM_H - vp_y - 4
  local content_h = 40 + #sizes * 84
  max_scroll = math.max(0, content_h - vp_h)
  if scroll > max_scroll then scroll = max_scroll end

  love.graphics.setScissor(0, vp_y, W, vp_h)
  local y = vp_y - scroll + 10

  if not font_path then
    love.graphics.setScissor()
    PathSel.draw({
      title = "FONT PREVIEW",
      message = "No font file selected.\n\n" ..
                "Open a .ttf / .otf / .woff from the File Explorer to preview it.\n\n" ..
                "You can also press Y to load a font from a custom path.",
      paths = { "assets/fonts/", "data/fonts/" },
      accent = acc,
      on_rescan = function()
        for _, c in ipairs({
          "assets/fonts/Oxanium-Regular.ttf",
          "assets/fonts/Oxanium-Bold.ttf",
          "assets/fonts/JetBrainsMono-Regular.ttf",
        }) do
          local f = io.open(c, "rb")
          if f then f:close(); font_path = c; load_all(); break end
        end
      end,
      on_pick = function(p)
        font_path = p
        load_all()
        Notify.show("info", "font loaded")
      end,
      on_back = function() State.back() end,
    })
    return
  else
    for _, sz in ipairs(sizes) do
      local f = loaded_fonts[sz]
      col(acc, 0.5)
      love.graphics.setFont(A.font(A.FONT_MONO, 10))
      love.graphics.print(string.format("%d px", sz), 20, y)
      col(acc, 0.3)
      love.graphics.rectangle("fill", 20, y + 14, W - 40, 1)
      y = y + 20

      if f then
        love.graphics.setFont(f)
        col(th.text_bright, 1)
        love.graphics.print("ABCDEFGHIJKLMNOPQRSTUVWXYZ", 24, y)
        y = y + f:getHeight() + 2
        love.graphics.print("abcdefghijklmnopqrstuvwxyz", 24, y)
        y = y + f:getHeight() + 2
        love.graphics.print("0123456789 !?@#$%&*()-_=+", 24, y)
        y = y + f:getHeight() + 2
        love.graphics.print(pangram, 24, y)
        y = y + f:getHeight() + 8
      else
        col(th.text_dim, 0.7)
        love.graphics.print("(cannot load at this size)", 24, y)
        y = y + 20
      end
      y = y + 12
    end
  end
  love.graphics.setScissor()

  Frame.draw_top("FGD", "plugins")
  Frame.draw_bottom({
    { key = "up",   label = "Scroll" },
    { key = "down", label = "Scroll" },
    { key = "b",    label = "Back" },
  })
  D.scanlines(W, H, 0.06)
end

return S
