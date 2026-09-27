-- ui/scroll.lua -- scrolling helpers per tutte le schermate.
local M = {}

function M.clamp(scroll, total_h, view_h)
  local mx = math.max(0, total_h - view_h)
  if scroll < 0 then return 0 end
  if scroll > mx then return mx end
  return scroll
end

function M.ensure(sel_y, sel_h, scroll, view_h, margin)
  margin = margin or 8
  if sel_y - margin < scroll then return sel_y - margin end
  if sel_y + sel_h + margin > scroll + view_h then
    return sel_y + sel_h + margin - view_h
  end
  return scroll
end

function M.bar(x, y, h, scroll, total_h, view_h, colour)
  if total_h <= view_h then return end
  local track_h = h - 8
  local thumb_h = math.max(20, track_h * (view_h / total_h))
  local denom = math.max(1, total_h - view_h)
  local thumb_y = y + 4 + (track_h - thumb_h) * (scroll / denom)
  love.graphics.setColor(colour[1], colour[2], colour[3], 0.55)
  love.graphics.rectangle("fill", x, thumb_y, 3, thumb_h, 1, 1)
end

return M
