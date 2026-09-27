-- screens/addons.lua
local A = require("core.assets")
local D = require("ui.draw")
local Input = require("core.input_map")
local T = require("plugins.chou_henka.ui.theme")
local W_ = require("plugins.chou_henka.ui.widgets")
local ADD = require("plugins.chou_henka.core.addons")
local M = {}
local W, H = 640, 480
local items, sel, scroll, t = {}, 1, 0, 0
local function col(c,a) love.graphics.setColor(c[1],c[2],c[3],a or 1) end
function M.enter() ADD.scan(); items = ADD.list(); sel, scroll, t = 1, 0, 0 end
function M.leave() end
function M.update(dt) t = t + dt end
local function move(d)
  if #items == 0 then return end
  sel = sel + d
  if sel < 1 then sel = #items end
  if sel > #items then sel = 1 end
end
function M.pad(b)
  if b == Input.B or b == Input.SELECT then return "back" end
  if b == Input.UP then move(-1)
  elseif b == Input.DOWN then move(1)
  elseif b == Input.A then
    local it = items[sel]
    if it and it.installed then
      ADD.set_enabled(it.key, not ADD.enabled(it.key))
    end
  end
  return false
end
function M.hat(dir)
  if dir == "up" then move(-1) elseif dir == "down" then move(1) end
end
function M.key(k)
  if k == "escape" then return "back" end
  if k == "up" then move(-1)
  elseif k == "down" then move(1)
  elseif k == "return" or k == "space" then M.pad(Input.A) end
  return false
end
function M.draw()
  local th = T.current()
  D.bg()
  col(th.accent, 0.05)
  for y = 30, H - 20, 20 do for x = 0, W, 20 do
    love.graphics.rectangle("fill", x, y, 1, 1)
  end end
  W_.header("CHOU HENKA — ADDONS",
    "// extensions: libraries · themes · decoders")
  local y0, row_h = 100, 52
  for i, it in ipairs(items) do
    local y = y0 + (i - 1) * (row_h + 4) - scroll
    if y + row_h > y0 and y < H - 40 then
      local focused = (i == sel)
      local c = it.installed and th.ok or th.text_dim
      W_.card(20, y, W - 40, row_h, c, focused)
      love.graphics.setFont(A.font(A.FONT_BODY_BOLD, 13))
      col(focused and {1,1,1} or th.text, 1)
      love.graphics.print(it.label or it.key, 36, y + 8)
      love.graphics.setFont(A.font(A.FONT_BODY, 9))
      col(th.text_dim, 0.85)
      love.graphics.print(it.desc or "", 36, y + 26)
      local badge = it.installed
        and (ADD.enabled(it.key) and "ENABLED" or "DISABLED")
        or (it.status == "planned" and "PLANNED" or "AVAILABLE")
      love.graphics.setFont(A.font(A.FONT_MONO, 9))
      col(it.installed and (ADD.enabled(it.key) and th.ok or th.warn) or th.text_dim, 1)
      love.graphics.printf(badge, 0, y + 20, W - 40, "right")
    end
  end
  love.graphics.setFont(A.font(A.FONT_MONO, 9))
  col(th.text_dim, 0.7)
  love.graphics.printf("A: toggle  ·  B: back", 0, H - 24, W, "center")
end
return M
