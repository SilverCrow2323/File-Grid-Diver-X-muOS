-- screens/hex_viewer.lua -- Hex Viewer plugin.
local A     = require("core.assets")
local State = require("core.state")
local Input = require("core.input_map")
local Frame = require("ui.frame")
local D     = require("ui.draw")

local S = {}
local W, H = 640, 480
local acc = {0.85, 0.80, 0.60}

local path = nil
local lines = {}
local scroll = 0
local total_lines = 0
local t_enter = 0
local MAX_BYTES = 2 * 1024 * 1024   -- 2 MB max

local function col(c, a) love.graphics.setColor(c[1], c[2], c[3], a or 1) end
local function basename(p) return (p or ""):match("([^/]+)$") or p or "?" end

local function load_file(p)
  lines = {}
  total_lines = 0
  if not p then return end
  local f = io.open(p, "rb")
  if not f then return end
  local data = f:read(MAX_BYTES)
  f:close()
  if not data then return end

  local PER_ROW = 16
  for i = 1, #data, PER_ROW do
    local chunk = data:sub(i, i + PER_ROW - 1)
    local hex = {}
    local ascii = {}
    for j = 1, PER_ROW do
      local b = chunk:byte(j)
      if b then
        hex[#hex+1] = string.format("%02X", b)
        if b >= 32 and b < 127 then
          ascii[#ascii+1] = string.char(b)
        else
          ascii[#ascii+1] = "."
        end
      else
        hex[#hex+1] = "  "
        ascii[#ascii+1] = " "
      end
    end
    total_lines = total_lines + 1
    lines[#lines+1] = {
      offset = string.format("%08X", i - 1),
      hex = table.concat(hex, " "),
      ascii = table.concat(ascii),
    }
  end
end

function S.enter()
  t_enter = 0
  scroll = 0
  path = State.hex_path
  State.hex_path = nil
  load_file(path)
end
function S.leave() end
function S.update(dt) t_enter = t_enter + dt end

function S.pad(b)
  if     b == Input.B or b == Input.SELECT then State.back()
  elseif b == Input.UP   then scroll = math.max(0, scroll - 1)
  elseif b == Input.DOWN then scroll = math.min(math.max(0, #lines - 20), scroll + 1)
  elseif b == Input.L1   then scroll = math.max(0, scroll - 20)
  elseif b == Input.R1   then scroll = math.min(math.max(0, #lines - 20), scroll + 20)
  elseif b == Input.Y    then scroll = 0
  elseif b == Input.X    then scroll = math.max(0, #lines - 20)
  end
end
function S.hat(dir)
  if     dir == "up"   then scroll = math.max(0, scroll - 1)
  elseif dir == "down" then scroll = math.min(math.max(0, #lines - 20), scroll + 1) end
end
function S.key(k)
  if     k == "escape" or k == "backspace" then State.back()
  elseif k == "up"   then scroll = math.max(0, scroll - 1)
  elseif k == "down" then scroll = math.min(math.max(0, #lines - 20), scroll + 1)
  elseif k == "pageup"   then scroll = math.max(0, scroll - 20)
  elseif k == "pagedown" then scroll = math.min(math.max(0, #lines - 20), scroll + 20)
  elseif k == "home" then scroll = 0
  elseif k == "end"  then scroll = math.max(0, #lines - 20) end
end

function S.draw()
  local th = State.theme
  D.bg()
  col(acc, 0.06)
  for gy = Frame.TOP_H, H - Frame.BOTTOM_H, 20 do
    for gx = 0, W, 20 do love.graphics.rectangle("fill", gx, gy, 1, 1) end
  end

  love.graphics.setFont(A.font(A.FONT_TITLE, 20))
  col(acc, 1)
  love.graphics.printf("HEX VIEWER", 0, Frame.TOP_H + 8, W, "center")

  love.graphics.setFont(A.font(A.FONT_MONO, 10))
  col(acc, 0.75)
  love.graphics.printf(basename(path), 0, Frame.TOP_H + 34, W, "center")

  local vp_y = Frame.TOP_H + 54
  local vp_h = H - Frame.BOTTOM_H - vp_y - 4

  if not path or #lines == 0 then
    love.graphics.setFont(A.font(A.FONT_BODY, 12))
    col(th.text_dim, 0.85)
    love.graphics.printf("no file loaded", 0, vp_y + vp_h/2, W, "center")
    return
  end

  love.graphics.setScissor(0, vp_y, W, vp_h)
  love.graphics.setFont(A.font(A.FONT_MONO, 12))
  local line_h = 16
  local vis = math.floor(vp_h / line_h)
  local first = scroll + 1
  local last = math.min(#lines, first + vis - 1)

  for i = first, last do
    local l = lines[i]
    local ry = vp_y + (i - first) * line_h

    col(acc, 0.75)
    love.graphics.print(l.offset, 12, ry)
    col({0.95, 0.95, 0.98}, 1)
    love.graphics.print(l.hex, 84, ry)
    col(acc, 0.9)
    love.graphics.print(l.ascii, 490, ry)
  end
  love.graphics.setScissor()

  -- Scrollbar
  if #lines > vis then
    local track_h = vp_h - 4
    local thumb_h = math.max(20, track_h * (vis / #lines))
    local max_s = math.max(1, #lines - vis)
    local thumb_y = vp_y + (track_h - thumb_h) * (scroll / max_s)
    col(acc, 0.55)
    love.graphics.rectangle("fill", W - 6, thumb_y, 3, thumb_h, 1, 1)
  end

  -- Info
  love.graphics.setFont(A.font(A.FONT_MONO, 10))
  col(acc, 0.75)
  love.graphics.printf(string.format("%d bytes  ·  %d rows  ·  offset 0x%08X",
    total_lines * 16, total_lines, scroll * 16),
    0, H - Frame.BOTTOM_H - 16, W, "center")

  Frame.draw_top("FGD", "plugins")
  Frame.draw_bottom({
    { key = "up",   label = "Line" },
    { key = "l1",   label = "Page" },
    { key = "y",    label = "Top" },
    { key = "x",    label = "Bottom" },
    { key = "b",    label = "Back" },
  })
  D.scanlines(W, H, 0.06)
end

return S
