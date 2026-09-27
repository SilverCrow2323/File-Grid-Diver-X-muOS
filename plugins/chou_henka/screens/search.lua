-- screens/search.lua -- ricerca fuzzy su tutta la libreria.
local A = require("core.assets")
local D = require("ui.draw")
local Input = require("core.input_map")
local T = require("plugins.chou_henka.ui.theme")
local W_ = require("plugins.chou_henka.ui.widgets")
local Icons = require("plugins.chou_henka.ui.icons")
local Scroll = require("plugins.chou_henka.ui.scroll")
local LIB = require("plugins.chou_henka.core.library")

local M = {}
local W, H = 640, 480
local query = ""
local results = {}
local sel, scroll_y, t = 1, 0, 0
local TOP, ROW_H, PAD = 118, 26, 20
local KB = nil

local function col(c, a) love.graphics.setColor(c[1], c[2], c[3], a or 1) end
local function human(n)
  if not n or n <= 0 then return "0 B" end
  local u = {"B","KB","MB","GB","TB"}; local i = 1
  while n >= 1024 and i < #u do n = n/1024; i = i + 1 end
  if i == 1 then return string.format("%d %s", n, u[i]) end
  return string.format("%.1f %s", n, u[i])
end

local function run()
  results = LIB.search(query)
  table.sort(results, function(a, b)
    local an = (a.title or a.name or ""):lower()
    local bn = (b.title or b.name or ""):lower()
    return an < bn
  end)
  sel, scroll_y = 1, 0
end

function M.enter()
  t = 0
  if not KB then KB = require("ui.keyboard") end
  query = ""
  run()
end
function M.leave() end
function M.update(dt) t = t + dt end

local function open_kb()
  KB.open({
    title = "Search library",
    initial = query,
    multiline = false,
    on_accept = function(s)
      query = s or ""
      run()
    end,
  })
end

local function move(d)
  if #results == 0 then return end
  sel = sel + d
  if sel < 1 then sel = 1 end
  if sel > #results then sel = #results end
end

function M.pad(b)
  if KB and KB.is_open() then KB.pad(b); return false end
  if b == Input.B or b == Input.SELECT then return "back" end
  if b == Input.UP then move(-1)
  elseif b == Input.DOWN then move(1)
  elseif b == Input.L1 then sel = math.max(1, sel - 10)
  elseif b == Input.R1 then sel = math.min(#results, sel + 10)
  elseif b == Input.X then open_kb()
  elseif b == Input.A then
    local it = results[sel]
    if it then return "open", it end
  end
  return false
end
function M.hat(dir)
  if KB and KB.is_open() then KB.hat(dir); return end
  if dir == "up" then move(-1) elseif dir == "down" then move(1) end
end
function M.key(k)
  if KB and KB.is_open() then KB.key(k); return false end
  if k == "escape" then return "back" end
  if k == "up" then move(-1)
  elseif k == "down" then move(1)
  elseif k == "backspace" then
    query = query:sub(1, -2); run()
  elseif k == "return" or k == "space" then M.pad(Input.A)
  elseif k:len() == 1 then
    query = query .. k; run()
  end
  return false
end

function M.draw()
  local th = T.current()
  D.bg()
  col(th.accent, 0.05)
  for y = 30, H - 20, 20 do
    for x = 0, W, 20 do love.graphics.rectangle("fill", x, y, 1, 1) end
  end
  W_.header("CHOU HENKA - SEARCH", "// " .. #results .. " results")

  -- query bar
  local qy = 78
  col({0.030, 0.020, 0.045}, 0.95)
  love.graphics.rectangle("fill", PAD, qy, W - PAD*2, 26, 3, 3)
  col(th.accent_hi, 0.9)
  love.graphics.setLineWidth(1.4)
  love.graphics.rectangle("line", PAD + 0.5, qy + 0.5, W - PAD*2 - 1, 25, 3, 3)
  love.graphics.setLineWidth(1)

  Icons.draw("search", PAD + 16, qy + 13, 8, th.accent_hi, 1)
  love.graphics.setFont(A.font(A.FONT_MONO, 12))
  col({1,1,1}, 1)
  local shown = query
  if shown == "" then
    col(th.text_dim, 0.7)
    shown = "(press X to type, or start typing)"
  end
  love.graphics.print(shown, PAD + 32, qy + 7)

  -- risultati
  local vp_y = TOP
  local vp_h = H - 40 - vp_y
  if #results == 0 then
    love.graphics.setFont(A.font(A.FONT_BODY, 12))
    col(th.text_dim, 0.85)
    love.graphics.printf("(no results)", 0, vp_y + vp_h/2, W, "center")
    return
  end
  local total_h = #results * ROW_H
  scroll_y = Scroll.ensure((sel-1) * ROW_H, ROW_H, scroll_y, vp_h)
  scroll_y = Scroll.clamp(scroll_y, total_h, vp_h)

  love.graphics.setScissor(PAD, vp_y, W - PAD*2, vp_h)
  for i, it in ipairs(results) do
    local y = vp_y + (i - 1) * ROW_H - scroll_y
    if y + ROW_H > vp_y - 4 and y < vp_y + vp_h + 4 then
      local focused = (i == sel)
      if focused then
        col(th.accent, 0.20)
        love.graphics.rectangle("fill", PAD, y, W - PAD*2, ROW_H - 2, 2, 2)
      end
      Icons.draw(it.cat or "doc", PAD + 16, y + ROW_H/2 - 1, 8,
        th.text_dim, focused and 1 or 0.7)
      love.graphics.setFont(A.font(A.FONT_BODY, 11))
      col(focused and {1,1,1} or th.text, 1)
      local nm = it.title or it.name or "?"
      if #nm > 55 then nm = nm:sub(1, 54) .. "..." end
      love.graphics.print(nm, PAD + 32, y + 5)
      love.graphics.setFont(A.font(A.FONT_MONO, 9))
      col(th.text_dim, 0.75)
      love.graphics.printf(human(it.size), 0, y + 6, W - PAD - 8, "right")
    end
  end
  love.graphics.setScissor()
  Scroll.bar(W - 8, vp_y, vp_h, scroll_y, total_h, vp_h, th.accent)

  love.graphics.setFont(A.font(A.FONT_MONO, 9))
  col(th.text_dim, 0.7)
  love.graphics.printf("A: open  -  X: edit query  -  B: back", 0, H - 24, W, "center")
end

return M
