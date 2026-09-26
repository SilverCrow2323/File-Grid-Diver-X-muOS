-- ui/context_menu.lua -- popup menu with scroll.
-- If items exceed the viewport, the menu scrolls to keep the
-- focused item visible. Works with pad, hat and keyboard.
local A     = require("core.assets")
local D     = require("ui.draw")

local M = {
  open_flag = false,
  x = 0, y = 0,
  title = "",
  items = {},
  sel = 1,
  scroll = 0,
  t = 0,
}

local ITEM_H   = 24
local PAD_X    = 12
local PAD_Y    = 30
local MIN_W    = 200
local MAX_W    = 340
local MAX_H    = 400    -- viewport max height for the menu body

function M.open(opts)
  opts = opts or {}
  M.open_flag = true
  M.x         = opts.x or (love.graphics.getWidth() / 2 - 100)
  M.y         = opts.y or (love.graphics.getHeight() / 2 - 100)
  M.title     = opts.title or ""
  M.items     = opts.items or {}
  M.sel       = 1
  M.scroll    = 0
  M.t         = 0
  M._skip()
end

function M.close() M.open_flag = false end
function M.is_open() return M.open_flag end
function M.update(dt) if M.open_flag then M.t = M.t + dt end end

function M._skip()
  local n = #M.items
  local tries = 0
  while M.items[M.sel] and M.items[M.sel].sep do
    M.sel = M.sel + 1
    if M.sel > n then M.sel = 1 end
    tries = tries + 1
    if tries > n then break end
  end
end

function M._move(dir)
  local n = #M.items
  if n == 0 then return end
  local i = M.sel
  local tries = 0
  repeat
    i = i + dir
    if i < 1 then i = n end
    if i > n then i = 1 end
    tries = tries + 1
  until (not M.items[i].sep) or tries > n
  M.sel = i
end

function M._activate()
  local it = M.items[M.sel]
  if not it or it.sep then return end
  M.close()
  if it.act then pcall(it.act) end
end

function M.pad(b)
  if not M.open_flag then return false end
  local Input = require("core.input_map")
  if     b == Input.UP   then M._move(-1)
  elseif b == Input.DOWN then M._move( 1)
  elseif b == Input.L1   then for _ = 1, 5 do M._move(-1) end
  elseif b == Input.R1   then for _ = 1, 5 do M._move( 1) end
  elseif b == Input.A    then M._activate()
  elseif b == Input.B or b == Input.SELECT then M.close() end
  return true
end

function M.hat(dir)
  if not M.open_flag then return false end
  if     dir == "up"   then M._move(-1)
  elseif dir == "down" then M._move( 1)
  elseif dir == "left" or dir == "right" then M.close() end
  return true
end

function M.key(k)
  if not M.open_flag then return false end
  if     k == "up"   then M._move(-1)
  elseif k == "down" then M._move( 1)
  elseif k == "pageup"   then for _ = 1, 5 do M._move(-1) end
  elseif k == "pagedown" then for _ = 1, 5 do M._move( 1) end
  elseif k == "return" or k == "space" then M._activate()
  elseif k == "escape" then M.close() end
  return true
end

-- Compute total height including separators
local function total_body_h()
  local h = 0
  for _, it in ipairs(M.items) do
    if it.sep then h = h + 8 else h = h + ITEM_H end
  end
  return h
end

-- Compute width: measure label + btn
local function compute_w()
  local w = MIN_W
  local font = A.font(A.FONT_BODY_BOLD, 12)
  for _, it in ipairs(M.items) do
    if it.label then
      local lw = font:getWidth(it.label)
      -- btn reserved on the right
      local bw = it.btn and 26 or 0
      if lw + PAD_X * 2 + bw + 12 > w then
        w = lw + PAD_X * 2 + bw + 12
      end
    end
  end
  if w > MAX_W then w = MAX_W end
  return w
end

function M.draw()
  if not M.open_flag then return end

  local W, H = love.graphics.getWidth(), love.graphics.getHeight()
  local w = compute_w()
  local body_h = total_body_h()
  local visible_h = math.min(body_h, MAX_H)
  local has_title = (M.title and M.title ~= "")
  local title_h = has_title and PAD_Y or 8
  local h = title_h + visible_h + 12

  local x, y = M.x, M.y
  if x + w > W - 6 then x = W - w - 6 end
  if y + h > H - 6 then y = H - h - 6 end
  if x < 6 then x = 6 end
  if y < 6 then y = 6 end

  local ok, State = pcall(require, "core.state")
  local th = ok and State.theme or {
    text = {0.85, 0.82, 0.76},
    text_bright = {0.96, 0.94, 0.90},
    text_dim = {0.44, 0.42, 0.38},
    panel = {0.05, 0.05, 0.04},
    amber_hi = {0.94, 0.66, 0.35},
    amber_lo = {0.35, 0.22, 0.10},
  }

  -- Shadow + body
  love.graphics.setColor(0, 0, 0, 0.65)
  love.graphics.rectangle("fill", x + 3, y + 3, w, h, 5, 5)
  love.graphics.setColor(th.panel)
  love.graphics.rectangle("fill", x, y, w, h, 5, 5)

  love.graphics.setColor(th.amber_lo[1], th.amber_lo[2], th.amber_lo[3], 0.9)
  love.graphics.setLineWidth(1.4)
  love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, 5, 5)
  love.graphics.setLineWidth(1)

  -- Title
  if has_title then
    love.graphics.setFont(A.font(A.FONT_MONO, 10))
    love.graphics.setColor(th.amber_hi)
    love.graphics.print(M.title:sub(1, 34), x + PAD_X, y + 8)
    love.graphics.setColor(th.amber_lo[1], th.amber_lo[2], th.amber_lo[3], 0.5)
    love.graphics.rectangle("fill", x + PAD_X, y + PAD_Y - 6, w - PAD_X * 2, 1)
  end

  -- Compute scroll to keep selection visible
  local y_off = 0
  local sel_y = nil
  for i, it in ipairs(M.items) do
    if i == M.sel then sel_y = y_off end
    y_off = y_off + (it.sep and 8 or ITEM_H)
  end
  local sel_h = ITEM_H
  local need_scroll = 0
  if sel_y then
    local body_top = M.scroll
    local body_bottom = M.scroll + visible_h
    if sel_y < body_top then
      M.scroll = sel_y
    elseif sel_y + sel_h > body_bottom then
      M.scroll = sel_y + sel_h - visible_h
    end
    M.scroll = math.max(0, math.min(body_h - visible_h, M.scroll))
  end

  -- Scissor the body
  local body_x = x + 4
  local body_y = y + title_h
  local body_w = w - 8
  love.graphics.setScissor(body_x, body_y, body_w, visible_h)

  -- Items
  local iy = body_y - M.scroll
  for i, it in ipairs(M.items) do
    if it.sep then
      love.graphics.setColor(th.amber_lo[1], th.amber_lo[2], th.amber_lo[3], 0.4)
      love.graphics.rectangle("fill", x + PAD_X, iy + 3, w - PAD_X * 2, 1)
      iy = iy + 8
    else
      local focused = (i == M.sel)
      if focused then
        love.graphics.setColor(th.amber_hi[1], th.amber_hi[2], th.amber_hi[3], 0.20)
        love.graphics.rectangle("fill", x + 4, iy, w - 8, ITEM_H - 2, 3, 3)
        love.graphics.setColor(th.amber_hi[1], th.amber_hi[2], th.amber_hi[3], 0.9)
        love.graphics.setLineWidth(1.4)
        love.graphics.rectangle("line", x + 4.5, iy + 0.5, w - 9, ITEM_H - 3, 3, 3)
        love.graphics.setLineWidth(1)
      end
      love.graphics.setFont(A.font(A.FONT_BODY_BOLD, 12))
      love.graphics.setColor(focused and th.text_bright or th.text, 1)
      local lx = x + PAD_X + 6
      local lw = w - PAD_X * 2 - 30
      local label = it.label or ""
      local f = love.graphics.getFont()
      while f:getWidth(label) > lw and #label > 1 do
        label = label:sub(1, -2)
      end
      if label ~= (it.label or "") then label = label .. "…" end
      love.graphics.print(label, lx, iy + ITEM_H/2 - 7)

      if it.btn then
        local ok2, BI = pcall(require, "ui.button_icons")
        if ok2 then BI.draw(x + w - 16, iy + ITEM_H/2 - 1, 7, it.btn) end
      end
    end
    iy = iy + (it.sep and 8 or ITEM_H)
  end

  love.graphics.setScissor()

  -- Scrollbar
  if body_h > visible_h then
    local track_x = x + w - 4
    local track_y = body_y
    local track_h = visible_h
    local thumb_h = math.max(20, track_h * (visible_h / body_h))
    local thumb_y = track_y + (track_h - thumb_h) * (M.scroll / (body_h - visible_h))
    love.graphics.setColor(th.amber_hi[1], th.amber_hi[2], th.amber_hi[3], 0.55)
    love.graphics.rectangle("fill", track_x, thumb_y, 2, thumb_h, 1, 1)
  end
end

return M
