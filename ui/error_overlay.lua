-- ui/error_overlay.lua - last-resort recovery overlay.
--
-- When a screen crashes and pcall catches the error, this module
-- shows a full-screen overlay instead of silently freezing.
--
-- Controls:
--   A  retry  -> re-enter the screen that crashed
--   B  back   -> go to main menu
--   X  quit   -> exit the application
--
-- The overlay shows the error message, the calling method, and the
-- last 10 lines of the runtime log so the user can see what broke.

local A     = require("core.assets")
local D     = require("ui.draw")
local Input = require("core.input_map")

local M = {
  active  = false,
  err     = "",
  ctx     = "",
  screen  = "",
  t       = 0,
  log_tail = {},
}

local LOG_PATH = "data/fgd_runtime.log"

local function read_tail(n)
  local out = {}
  local f = io.open(LOG_PATH, "r")
  if not f then return out end
  local lines = {}
  for line in f:lines() do lines[#lines + 1] = line end
  f:close()
  local total = #lines
  for i = math.max(1, total - n + 1), total do
    out[#out + 1] = lines[i]
  end
  return out
end

function M.show(err, ctx, screen_name)
  M.active  = true
  M.err     = tostring(err or "unknown error")
  M.ctx     = tostring(ctx or "?")
  M.screen  = tostring(screen_name or "?")
  M.t       = 0
  M.log_tail = read_tail(10)
end

function M.close()
  M.active = false
  M.err    = ""
  M.ctx    = ""
  M.log_tail = {}
end

function M.is_active()
  return M.active == true
end

function M.update(dt)
  if M.active then M.t = M.t + dt end
end

function M.pad(b)
  if not M.active then return end
  if b == Input.A then
    local target = M.screen
    M.close()
    if target and target ~= "?" then
      require("core.state").go(target)
    else
      require("core.state").go("mainmenu")
    end
  elseif b == Input.B then
    M.close()
    require("core.state").go("mainmenu")
  elseif b == Input.X then
    love.event.quit()
  end
end

function M.key(k)
  if not M.active then return end
  if k == "return" or k == "space" then M.pad(Input.A)
  elseif k == "escape" or k == "backspace" then M.pad(Input.B)
  elseif k == "q" then M.pad(Input.X) end
end

local function wrap(text, width, font)
  local lines = {}
  for raw in (text .. "\n"):gmatch("([^\n]*)\n") do
    local cur = ""
    for word in raw:gmatch("%S+%s*") do
      local test = cur .. word
      if font:getWidth(test) > width and cur ~= "" then
        lines[#lines + 1] = cur:gsub("%s+$", "")
        cur = word
      else
        cur = test
      end
    end
    lines[#lines + 1] = cur:gsub("%s+$", "")
  end
  return lines
end

function M.draw()
  if not M.active then return end
  local W, H = love.graphics.getWidth(), love.graphics.getHeight()
  local th = require("core.state").theme or {
    text = {0.85, 0.82, 0.76},
    text_dim = {0.44, 0.42, 0.38},
    panel = {0.05, 0.05, 0.04},
    amber_hi = {0.94, 0.66, 0.35},
    amber_lo = {0.35, 0.22, 0.10},
  }
  local accent = {0.95, 0.35, 0.30}

  love.graphics.setColor(0, 0, 0, 0.85)
  love.graphics.rectangle("fill", 0, 0, W, H)

  local x, y = 20, 20
  local w, h = W - 40, H - 40

  love.graphics.setColor(0.02, 0.01, 0.01, 0.98)
  love.graphics.rectangle("fill", x, y, w, h, 4, 4)
  love.graphics.setColor(accent[1], accent[2], accent[3], 0.95)
  love.graphics.setLineWidth(2)
  love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, 4, 4)
  love.graphics.setLineWidth(1)
  D.corner_ticks(x + 8, y + 8, w - 16, h - 16, 14, accent, 0.9)

  love.graphics.setFont(A.font(A.FONT_TITLE, 20))
  love.graphics.setColor(accent[1], accent[2], accent[3], 1)
  love.graphics.print("SCREEN CRASHED", x + 20, y + 16)

  love.graphics.setFont(A.font(A.FONT_MONO, 10))
  love.graphics.setColor(th.text_dim)
  love.graphics.print("screen: " .. M.screen .. "   method: " .. M.ctx,
    x + 20, y + 46)

  love.graphics.setFont(A.font(A.FONT_BODY_BOLD, 12))
  love.graphics.setColor(th.text)
  local err_lines = wrap(M.err, w - 40, A.font(A.FONT_BODY_BOLD, 12))
  local ey = y + 68
  for i = 1, math.min(#err_lines, 6) do
    love.graphics.print(err_lines[i], x + 20, ey)
    ey = ey + 16
  end

  -- Log tail
  if #M.log_tail > 0 then
    ey = ey + 8
    love.graphics.setColor(accent[1], accent[2], accent[3], 0.4)
    love.graphics.rectangle("fill", x + 20, ey, w - 40, 1)
    ey = ey + 8
    love.graphics.setFont(A.font(A.FONT_MONO, 9))
    love.graphics.setColor(th.text_dim)
    love.graphics.print("last log lines:", x + 20, ey)
    ey = ey + 12
    for i = 1, math.min(#M.log_tail, 10) do
      local line = M.log_tail[i] or ""
      if #line > 110 then line = line:sub(1, 109) .. "..." end
      love.graphics.print(line, x + 20, ey)
      ey = ey + 11
    end
  end

  -- Controls
  love.graphics.setFont(A.font(A.FONT_BODY_BOLD, 12))
  local by = y + h - 30
  love.graphics.setColor(accent[1] * 0.4, accent[2] * 0.4, accent[3] * 0.4, 1)
  love.graphics.rectangle("fill", x + 20, by - 6, w - 40, 1)

  love.graphics.setColor(th.text)
  love.graphics.printf("[A] retry   [B] main menu   [X] quit",
    x, by, w, "center")

  D.scanlines(W, H, 0.08)
end

return M
