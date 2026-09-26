-- ui/modal.lua -- holographic confirm modal.
-- Symmetric footer buttons (same width), materialize/dematerialize
-- animations with scan line. Supports inline button tokens in the
-- message via ui/richtext.
local A     = require("core.assets")
local D     = require("ui.draw")
local BI    = require("ui.button_icons")
local RT    = require("ui.richtext")

local M = { current = nil }

local function ease_out(p) return 1 - (1 - p) ^ 3 end
local function ease_in(p)  return p * p * p end

local DUR_OPEN  = 0.30
local DUR_CLOSE = 0.24
local BTN_W     = 150   -- fixed footer button width for symmetry

function M.show(title, message, opts)
  opts = opts or {}
  M.current = {
    title        = title or "",
    message      = message or "",
    on_accept    = opts.on_accept,
    on_cancel    = opts.on_cancel,
    accept_label = opts.accept_label or "OK",
    cancel_label = opts.cancel_label or "CANCEL",
    hide_cancel  = opts.hide_cancel or false,
    hide_accept  = opts.hide_accept or false,
    color        = opts.color,
    accept_color = opts.accept_color,
    cancel_color = opts.cancel_color,
    accept_disabled = opts.accept_disabled or false,
    phase     = 0,
    closing   = false,
    close_t   = 0,
    _after    = nil,
    t         = 0,
  }
end

function M.is_open()
  return M.current ~= nil and not M.current.closing
end

function M.is_visible()
  return M.current ~= nil
end

function M.close()
  if not M.current then return end
  if M.current.closing then return end
  M.current.closing = true
  M.current.close_t = 0
end

function M.accept()
  local c = M.current
  if not c or c.closing then return end
  if c.accept_disabled or c.hide_accept then return end
  c._after = c.on_accept
  M.close()
end

function M.cancel()
  local c = M.current
  if not c or c.closing then return end
  if c.hide_cancel then
    c._after = c.on_accept
  else
    c._after = c.on_cancel
  end
  M.close()
end

function M.update(dt)
  local c = M.current
  if not c then return end
  c.t = c.t + dt
  if c.closing then
    c.close_t = math.min(1, c.close_t + dt / DUR_CLOSE)
    c.phase = 1 - ease_in(c.close_t)
    if c.close_t >= 1 then
      local cb = c._after
      M.current = nil
      if cb then pcall(cb) end
    end
  else
    c.phase = math.min(1, c.phase + dt / DUR_OPEN)
  end
end

local function accent_of(c)
  if c.color then return c.color end
  local ok, State = pcall(require, "core.state")
  if ok and State.theme and State.theme.amber then return State.theme.amber end
  return {0.94, 0.66, 0.35}
end

function M.draw()
  local c = M.current
  if not c then return end

  local W, H = love.graphics.getWidth(), love.graphics.getHeight()
  local ok, State = pcall(require, "core.state")
  local th = (ok and State.theme) or {
    text = {0.85, 0.82, 0.76},
    text_dim = {0.44, 0.42, 0.38},
    text_bright = {0.96, 0.94, 0.90},
    panel = {0.05, 0.05, 0.04},
  }
  local acc = accent_of(c)
  local p = c.phase

  love.graphics.setColor(0, 0, 0, 0.78 * p)
  love.graphics.rectangle("fill", 0, 0, W, H)
  if p <= 0.01 then return end

  local pad = 24
  local title_h = 22 + 14
  local footer_h = 44

  local msg_w = math.max(360, math.min(560, W - 160))
  local msg_h = RT.height(c.message, msg_w - pad * 2)

  local w = msg_w
  local h = pad + title_h + msg_h + 20 + footer_h + pad
  h = math.max(h, 170)

  local x = math.floor((W - w) / 2)
  local y = math.floor((H - h) / 2) + (1 - ease_out(p)) * 22
  local cx, cy = x + w / 2, y + h / 2

  D.glow(cx, cy, w * 0.68, acc, 0.55 * p)

  love.graphics.setColor(acc[1], acc[2], acc[3], 0.32 * p)
  love.graphics.rectangle("fill", x - 5, y - 5, w + 10, h + 10, 6, 6)

  love.graphics.setColor(0.020, 0.016, 0.024, 0.97 * p)
  love.graphics.rectangle("fill", x, y, w, h, 4, 4)

  love.graphics.setColor(acc[1], acc[2], acc[3], 0.95 * p)
  love.graphics.setLineWidth(1.6)
  love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, 4, 4)
  love.graphics.setLineWidth(1)

  love.graphics.setColor(acc[1], acc[2], acc[3], 0.28 * p)
  love.graphics.rectangle("line", x + 6.5, y + 6.5, w - 13, h - 13, 3, 3)

  D.corner_ticks(x + 10, y + 10, w - 20, h - 20, 16, acc, 0.95 * p)

  if p < 1 then
    local sy = y + h * ease_out(p)
    love.graphics.setColor(acc[1], acc[2], acc[3], 0.6 * (1 - p))
    love.graphics.rectangle("fill", x + 8, sy - 1, w - 16, 2)
  end

  if p < 0.35 then return end
  local ca = math.min(1, (p - 0.35) / 0.65)

  love.graphics.setColor(acc[1], acc[2], acc[3], ca)
  love.graphics.setFont(A.font(A.FONT_BODY_BOLD, 14))
  love.graphics.print("> " .. c.title:upper(), x + pad, y + 18)

  love.graphics.setColor(acc[1], acc[2], acc[3], 0.32 * ca)
  love.graphics.rectangle("fill", x + pad, y + 42, w - pad * 2, 1)

  RT.draw(c.message, x + pad, y + pad + title_h,
    w - pad * 2, "left", ca, { colour = th.text })

  -- Footer: two symmetric buttons
  local fy = y + h - footer_h - 6
  local btn_r = 11
  local f_btn = A.font(A.FONT_BODY_BOLD, 12)
  love.graphics.setFont(f_btn)
  local fh = f_btn:getHeight()
  local by = fy + (footer_h - fh - 8) / 2

  local function draw_btn(bx, key, label, colour, disabled)
    local bw = BTN_W
    local is_disabled = disabled

    if is_disabled then
      love.graphics.setColor(0.10, 0.10, 0.12, ca)
      love.graphics.rectangle("fill", bx, by, bw, fh + 10, 4, 4)
      love.graphics.setColor(0.30, 0.30, 0.34, ca)
      love.graphics.rectangle("line", bx + 0.5, by + 0.5, bw - 1, fh + 9, 4, 4)
      love.graphics.setFont(f_btn)
      love.graphics.setColor(0.42, 0.42, 0.46, ca)
      love.graphics.printf(label, bx, by + 5, bw, "center")
      return
    end

    love.graphics.setColor(colour[1]*0.22, colour[2]*0.22, colour[3]*0.22, ca)
    love.graphics.rectangle("fill", bx, by, bw, fh + 10, 4, 4)
    love.graphics.setColor(colour[1], colour[2], colour[3], 0.90 * ca)
    love.graphics.setLineWidth(1.5)
    love.graphics.rectangle("line", bx + 0.5, by + 0.5, bw - 1, fh + 9, 4, 4)
    love.graphics.setLineWidth(1)

    -- Button icon on the left, label centered after
    local icon_x = bx + 18
    local icon_cy = by + (fh + 10) / 2
    BI.draw(icon_x, icon_cy, 9, key)

    love.graphics.setFont(f_btn)
    love.graphics.setColor({1, 1, 1}, ca)
    love.graphics.printf(label, bx + 28, by + 5, bw - 34, "center")
  end

  -- Layout: if both buttons, side by side; else single centered
  local n_btns = 0
  if not c.hide_accept then n_btns = n_btns + 1 end
  if not c.hide_cancel then n_btns = n_btns + 1 end

  local gap = 24
  if n_btns == 2 then
    local total = BTN_W * 2 + gap
    local sx = x + (w - total) / 2
    draw_btn(sx, "a", c.accept_label, c.accept_color or acc, c.accept_disabled)
    draw_btn(sx + BTN_W + gap, "b", c.cancel_label, c.cancel_color or acc, false)
  elseif n_btns == 1 then
    local sx = x + (w - BTN_W) / 2
    if not c.hide_accept then
      draw_btn(sx, "a", c.accept_label, c.accept_color or acc, c.accept_disabled)
    else
      draw_btn(sx, "b", c.cancel_label, c.cancel_color or acc, false)
    end
  end
end

return M
