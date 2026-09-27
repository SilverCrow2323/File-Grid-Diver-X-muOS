-- ui/widgets.lua
local A = require("core.assets")
local D = require("ui.draw")
local T = require("plugins.chou_henka.ui.theme")
local M = {}
local function col(c,a) love.graphics.setColor(c[1],c[2],c[3],a or 1) end
M.col = col
function M.header(title, subtitle)
  local th = T.current()
  love.graphics.setFont(A.font(A.FONT_TITLE, 20))
  col(th.accent_hi, 1)
  love.graphics.printf(title, 0, 34, 640, "center")
  if subtitle then
    love.graphics.setFont(A.font(A.FONT_MONO, 10))
    col(th.accent, 0.75)
    love.graphics.printf(subtitle, 0, 60, 640, "center")
  end
end
function M.pill(x,y,w,h,label,colour,focused)
  local th = T.current()
  if focused then
    col({colour[1]*0.25,colour[2]*0.25,colour[3]*0.25}, 0.98)
    love.graphics.rectangle("fill",x,y,w,h,h/2,h/2)
    col(colour,0.95); love.graphics.setLineWidth(1.5)
    love.graphics.rectangle("line",x+0.5,y+0.5,w-1,h-1,h/2,h/2); love.graphics.setLineWidth(1)
  else
    col(th.panel,0.9); love.graphics.rectangle("fill",x,y,w,h,h/2,h/2)
    col(colour,0.32); love.graphics.rectangle("line",x+0.5,y+0.5,w-1,h-1,h/2,h/2)
  end
  love.graphics.setFont(A.font(A.FONT_BODY_BOLD, 11))
  col(focused and {1,1,1} or th.text, 1)
  love.graphics.printf(label, x, y + h/2 - 7, w, "center")
end
function M.progress(x,y,w,h,pct,colour,focused)
  col({0.06,0.06,0.10},1); love.graphics.rectangle("fill",x,y,w,h,h/2,h/2)
  pct = math.max(0, math.min(1, pct or 0))
  if pct > 0 then col(colour,0.95); love.graphics.rectangle("fill",x,y,w*pct,h,h/2,h/2) end
  if focused then
    local kx, ky = x + w*pct, y + h/2
    col({0,0,0},0.5); love.graphics.circle("fill",kx+1,ky+1,h*0.9)
    col(colour,1); love.graphics.circle("fill",kx,ky,h*0.9)
  end
end
function M.card(x,y,w,h,accent,focused)
  local th = T.current()
  if focused then
    col({accent[1]*0.18,accent[2]*0.18,accent[3]*0.18},0.98)
    love.graphics.rectangle("fill",x,y,w,h,5,5)
    col(accent,0.95); love.graphics.setLineWidth(1.8)
    love.graphics.rectangle("line",x+0.5,y+0.5,w-1,h-1,5,5); love.graphics.setLineWidth(1)
    D.corner_ticks(x+8,y+8,w-16,h-16,12,accent,0.95)
  else
    col(th.panel,0.92); love.graphics.rectangle("fill",x,y,w,h,5,5)
    col(accent,0.35); love.graphics.rectangle("line",x+0.5,y+0.5,w-1,h-1,5,5)
  end
end
return M
