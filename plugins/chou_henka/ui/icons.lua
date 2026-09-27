-- ui/icons.lua -- icone vettoriali per menu, tab, categorie.
local M = {}

local ALIAS = {
  audio = "music", other = "doc", plug = "addons",
  gear = "settings", arrow = "play", video_library = "video",
  theme_pack = "image", decoder_pack = "video",
  scraper = "search", subtitle_pack = "doc",
}

local function col(c, a) love.graphics.setColor(c[1], c[2], c[3], a or 1) end

function M.draw(kind, cx, cy, r, colour, alpha)
  kind = ALIAS[kind] or kind
  colour = colour or {1, 1, 1}
  col(colour, alpha or 1)
  love.graphics.setLineWidth(math.max(1.2, r * 0.16))
  local rr = r

  if kind == "music" then
    love.graphics.circle("line", cx - rr*0.35, cy + rr*0.4, rr*0.32)
    love.graphics.circle("line", cx + rr*0.35, cy + rr*0.4, rr*0.32)
    love.graphics.line(cx - rr*0.03, cy + rr*0.4, cx - rr*0.03, cy - rr*0.7)
    love.graphics.line(cx + rr*0.65, cy + rr*0.4, cx + rr*0.65, cy - rr*0.55)
    love.graphics.line(cx - rr*0.03, cy - rr*0.7, cx + rr*0.65, cy - rr*0.55)
  elseif kind == "video" then
    love.graphics.rectangle("line", cx - rr*0.8, cy - rr*0.6, rr*1.6, rr*1.2, 2, 2)
    love.graphics.polygon("fill", cx - rr*0.15, cy - rr*0.35, cx - rr*0.15, cy + rr*0.35, cx + rr*0.4, cy)
  elseif kind == "image" then
    love.graphics.rectangle("line", cx - rr*0.8, cy - rr*0.7, rr*1.6, rr*1.4, 2, 2)
    love.graphics.circle("line", cx + rr*0.35, cy - rr*0.3, rr*0.18)
    love.graphics.polygon("line", cx - rr*0.6, cy + rr*0.5, cx - rr*0.1, cy - rr*0.1, cx + rr*0.6, cy + rr*0.5)
  elseif kind == "comic" then
    love.graphics.rectangle("line", cx - rr*0.7, cy - rr*0.7, rr*0.6, rr*1.4, 2, 2)
    love.graphics.rectangle("line", cx + rr*0.1, cy - rr*0.7, rr*0.6, rr*1.4, 2, 2)
    love.graphics.line(cx - rr*0.5, cy - rr*0.4, cx - rr*0.2, cy - rr*0.4)
    love.graphics.line(cx + rr*0.3, cy - rr*0.4, cx + rr*0.5, cy - rr*0.4)
  elseif kind == "book" then
    love.graphics.rectangle("line", cx - rr*0.7, cy - rr*0.8, rr*1.4, rr*1.6, 2, 2)
    love.graphics.line(cx, cy - rr*0.8, cx, cy + rr*0.8)
  elseif kind == "doc" then
    love.graphics.rectangle("line", cx - rr*0.6, cy - rr*0.8, rr*1.2, rr*1.6, 2, 2)
    love.graphics.line(cx - rr*0.3, cy - rr*0.3, cx + rr*0.3, cy - rr*0.3)
    love.graphics.line(cx - rr*0.3, cy, cx + rr*0.3, cy)
    love.graphics.line(cx - rr*0.3, cy + rr*0.3, cx + rr*0.3, cy + rr*0.3)
  elseif kind == "home" then
    love.graphics.polygon("line",
      cx, cy - rr*0.8, cx + rr*0.9, cy,
      cx + rr*0.6, cy, cx + rr*0.6, cy + rr*0.7,
      cx - rr*0.6, cy + rr*0.7, cx - rr*0.6, cy, cx - rr*0.9, cy)
  elseif kind == "library" then
    love.graphics.rectangle("line", cx - rr*0.8, cy - rr*0.7, rr*0.5, rr*1.4, 1, 1)
    love.graphics.rectangle("line", cx - rr*0.2, cy - rr*0.7, rr*0.5, rr*1.4, 1, 1)
    love.graphics.rectangle("line", cx + rr*0.4, cy - rr*0.7, rr*0.5, rr*1.4, 1, 1)
  elseif kind == "settings" then
    for i = 0, 7 do
      local a = i * math.pi / 4
      love.graphics.line(cx + math.cos(a)*rr*0.55, cy + math.sin(a)*rr*0.55,
                         cx + math.cos(a)*rr*0.9,  cy + math.sin(a)*rr*0.9)
    end
    love.graphics.circle("line", cx, cy, rr*0.55)
    love.graphics.circle("line", cx, cy, rr*0.2)
  elseif kind == "addons" then
    love.graphics.rectangle("line", cx - rr*0.5, cy - rr*0.3, rr, rr*1.0, 2, 2)
    love.graphics.line(cx - rr*0.2, cy - rr*0.3, cx - rr*0.2, cy - rr*0.75)
    love.graphics.line(cx + rr*0.2, cy - rr*0.3, cx + rr*0.2, cy - rr*0.75)
  elseif kind == "search" then
    love.graphics.circle("line", cx - rr*0.15, cy - rr*0.15, rr*0.6)
    love.graphics.line(cx + rr*0.3, cy + rr*0.3, cx + rr*0.8, cy + rr*0.8)
  elseif kind == "star" then
    local pts = {}
    for i = 0, 9 do
      local a = -math.pi/2 + i * math.pi/5
      local rad = (i % 2 == 0) and rr*0.9 or rr*0.4
      pts[#pts+1] = cx + math.cos(a) * rad
      pts[#pts+1] = cy + math.sin(a) * rad
    end
    love.graphics.polygon("line", pts)
  elseif kind == "clock" then
    love.graphics.circle("line", cx, cy, rr*0.85)
    love.graphics.line(cx, cy, cx, cy - rr*0.5)
    love.graphics.line(cx, cy, cx + rr*0.4, cy + rr*0.15)
  elseif kind == "sources" or kind == "folder" then
    love.graphics.rectangle("line", cx - rr*0.8, cy - rr*0.4, rr*1.6, rr*1.0, 2, 2)
    love.graphics.rectangle("fill", cx - rr*0.8, cy - rr*0.75, rr*0.7, rr*0.4)
  elseif kind == "scan" then
    love.graphics.arc("line", "open", cx, cy, rr*0.8, -math.pi*0.5, math.pi*0.7)
    love.graphics.polygon("fill", cx + rr*0.2, cy - rr*0.8, cx + rr*0.7, cy - rr*0.5, cx + rr*0.3, cy - rr*0.3)
  elseif kind == "info" then
    love.graphics.circle("line", cx, cy, rr*0.85)
    love.graphics.line(cx, cy - rr*0.4, cx, cy + rr*0.5)
    love.graphics.circle("fill", cx, cy - rr*0.55, rr*0.1)
  elseif kind == "power" then
    love.graphics.arc("line", "open", cx, cy + rr*0.1, rr*0.7, -math.pi*0.75, -math.pi*0.25)
    love.graphics.line(cx, cy - rr*0.85, cx, cy - rr*0.15)
  elseif kind == "play" then
    love.graphics.polygon("fill", cx - rr*0.4, cy - rr*0.6, cx - rr*0.4, cy + rr*0.6, cx + rr*0.6, cy)
  elseif kind == "pause" then
    love.graphics.rectangle("fill", cx - rr*0.35, cy - rr*0.6, rr*0.25, rr*1.2)
    love.graphics.rectangle("fill", cx + rr*0.1, cy - rr*0.6, rr*0.25, rr*1.2)
  elseif kind == "plus" then
    love.graphics.line(cx - rr*0.7, cy, cx + rr*0.7, cy)
    love.graphics.line(cx, cy - rr*0.7, cx, cy + rr*0.7)
  else
    love.graphics.circle("line", cx, cy, rr*0.7)
  end
  love.graphics.setLineWidth(1)
end

return M
