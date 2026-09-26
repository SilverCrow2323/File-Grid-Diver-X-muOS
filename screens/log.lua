-- screens/log.lua — runtime + session log viewer.
local A     = require("core.assets")
local State = require("core.state")
local Input = require("core.input_map")
local Frame = require("ui.frame")
local D     = require("ui.draw")

local S = {}
local W, H = 640, 480
local SOURCES = {
  { key = "runtime", label = "RUNTIME ERRORS",  path = "data/fgd_runtime.log" },
  { key = "session", label = "SESSION LOG",     path = ".desktopbase/logs/latest.log" },
  { key = "launcher",label = "muOS LAUNCHER",   path = "data/logs/launcher.log" },
}

local cur = 1
local lines = {}
local scroll = 0
local last_reload = 0

local function reload()
  local src = SOURCES[cur]
  lines = {}
  local f = io.open(src.path, "r")
  if not f then
    lines = { "(missing: " .. src.path .. ")" }
    return
  end
  local all = {}
  for line in f:lines() do all[#all + 1] = line end
  f:close()
  -- keep last 500 lines
  local start = math.max(1, #all - 499)
  for i = start, #all do lines[#lines + 1] = all[i] end
  if #lines == 0 then lines = { "(empty)" } end
  scroll = #lines
end

function S.enter()
  reload()
  last_reload = 0
end
function S.leave() end

function S.update(dt)
  last_reload = last_reload + dt
  if last_reload > 2 then
    last_reload = 0
    local old = scroll
    reload()
    scroll = math.max(1, math.min(#lines, old))
  end
end

local function scroll_by(n)
  scroll = math.max(1, math.min(#lines, scroll + n))
end

function S.pad(b)
  if b == Input.B or b == Input.SELECT then State.back()
  elseif b == Input.UP   then scroll_by(-1)
  elseif b == Input.DOWN then scroll_by( 1)
  elseif b == Input.L1   then scroll_by(-10)
  elseif b == Input.R1   then scroll_by( 10)
  elseif b == Input.X    then
    cur = (cur % #SOURCES) + 1
    reload()
  end
end
function S.hat(dir)
  if     dir == "up"   then scroll_by(-1)
  elseif dir == "down" then scroll_by( 1) end
end
function S.key(k)
  if k == "escape" or k == "backspace" then State.back()
  elseif k == "up"    then scroll_by(-1)
  elseif k == "down"  then scroll_by( 1)
  elseif k == "pageup"   then scroll_by(-10)
  elseif k == "pagedown" then scroll_by( 10)
  elseif k == "tab" then
    cur = (cur % #SOURCES) + 1
    reload()
  end
end

function S.draw()
  local th = State.theme
  D.bg()

  -- Source tabs
  local tab_x = 10
  for i, src in ipairs(SOURCES) do
    local f = A.font(A.FONT_BODY_BOLD, 12)
    love.graphics.setFont(f)
    local w = f:getWidth(src.label) + 14
    local active = (i == cur)
    love.graphics.setColor(active and th.amber_hi or th.text_dim)
    love.graphics.rectangle("line", tab_x, Frame.TOP_H + 4, w, 16)
    love.graphics.print(src.label, tab_x + 7, Frame.TOP_H + 7)
    tab_x = tab_x + w + 4
  end

  -- Log text
  local font = A.font(A.FONT_MONO, 12)
  love.graphics.setFont(font)
  local line_h = 12
  local pad_l = 14
  local pad_t = Frame.TOP_H + 26
  local pad_b = Frame.BOTTOM_H + 4
  local max_vis = math.floor((H - pad_t - pad_b) / line_h)
  local first = math.max(1, scroll - max_vis + 1)
  local last  = math.min(#lines, first + max_vis - 1)

  for i = first, last do
    local line = lines[i]
    local y = pad_t + (i - first) * line_h
    local is_cur = (i == scroll)
    local is_err = line:find("ERR", 1, true) or line:find("ERROR", 1, true)
                   or line:find("FATAL", 1, true)
    local is_warn = line:find("WARN", 1, true)
    if is_err then
      love.graphics.setColor(th.red_hi)
    elseif is_warn then
      love.graphics.setColor(th.amber_hi)
    elseif is_cur then
      love.graphics.setColor(th.cyan_hi)
    else
      love.graphics.setColor(th.text)
    end
    if is_cur then
      love.graphics.setColor(0.10, 0.08, 0.05, 1)
      love.graphics.rectangle("fill", 0, y - 1, W, line_h)
      love.graphics.setColor(is_err and th.red_hi or th.cyan_hi)
    end
    love.graphics.print(line, pad_l, y)
  end

  -- Position indicator
  love.graphics.setColor(th.text_dim)
  love.graphics.setFont(A.font(A.FONT_MONO, 12))
  love.graphics.printf(string.format("%d / %d",
    scroll, #lines), 0, Frame.TOP_H + 7, W - 12, "right")

  Frame.draw_top("FGD", "log")
  Frame.draw_bottom({
    { key = "UP/DN",  label = "Scroll" },
    { key = "L1/R1",  label = "±10" },
    { key = "X",      label = "Source" },
    { key = "B",      label = "Back" },
  })
  D.scanlines(W, H, 0.06)
end

return S
