-- screens/library.lua -- view Kodi con poster/fanart reali.
local A       = require("core.assets")
local D       = require("ui.draw")
local Input   = require("core.input_map")
local T       = require("plugins.chou_henka.ui.theme")
local W_      = require("plugins.chou_henka.ui.widgets")
local Icons   = require("plugins.chou_henka.ui.icons")
local Views   = require("plugins.chou_henka.ui.views")
local Poster  = require("plugins.chou_henka.ui.poster")
local LIB     = require("plugins.chou_henka.core.library")
local WS      = require("plugins.chou_henka.core.watchstate")
local CFG     = require("plugins.chou_henka.core.config")

local M = {}
local W, H = 640, 480

local category = "all"
local items = {}
local sel, scroll, sort_key, t = 1, 0, "name", 0

local VIEWS = { "list", "poster", "wall", "fanart", "infowall", "widelist" }
local STATE_FILTERS = { "all", "unwatched", "watched", "favorites", "resume" }
local view_idx, state_filter = 1, 1

local TOP, PAD = 100, 16

local function col(c,a) love.graphics.setColor(c[1],c[2],c[3],a or 1) end

local function current_view()
  local v = CFG.get("ui","view") or "list"
  for _, x in ipairs(VIEWS) do if x == v then return v end end
  return "list"
end

local function refresh()
  items = LIB.filter(category, "")
  items = LIB.filter_state(items, STATE_FILTERS[state_filter])
  table.sort(items, function(a, b)
    local an = (a.title or a.name or ""):lower()
    local bn = (b.title or b.name or ""):lower()
    if sort_key == "name" then return an < bn end
    if sort_key == "size" then return (a.size or 0) > (b.size or 0) end
    if sort_key == "date" then return (a.mtime or 0) > (b.mtime or 0) end
    if sort_key == "type" then return (a.ext or "") < (b.ext or "") end
    return an < bn
  end)
  if sel > #items then sel = math.max(1, #items) end
end

function M.set_category(cat) category = cat or "all"; sel = 1; scroll = 0; refresh() end
function M.set_state(s)
  for i, v in ipairs(STATE_FILTERS) do if v == s then state_filter = i; break end end
  sel, scroll = 1, 0; refresh()
end

function M.enter()
  refresh(); t = 0
  for i, v in ipairs(VIEWS) do if v == current_view() then view_idx = i end end
end
function M.leave() end
function M.update(dt) t = t + dt end

local function move(d)
  if #items == 0 then return end
  sel = sel + d
  if sel < 1 then sel = #items end
  if sel > #items then sel = 1 end
end

local function cycle_view(d)
  view_idx = view_idx + d
  if view_idx < 1 then view_idx = #VIEWS end
  if view_idx > #VIEWS then view_idx = 1 end
  CFG.set("ui", "view", VIEWS[view_idx]); CFG.save()
  sel, scroll = 1, 0
end

local function cycle_state()
  state_filter = state_filter + 1
  if state_filter > #STATE_FILTERS then state_filter = 1 end
  sel, scroll = 1, 0
  refresh()
end

local function cycle_sort()
  local order = { "name", "size", "date", "type" }
  local i = 1; for k, v in ipairs(order) do if v == sort_key then i = k end end
  sort_key = order[i % #order + 1]
  refresh()
end

local function toggle_watched()
  if #items == 0 then return end
  local it = items[sel]
  WS.toggle_watched(it.path)
  local N = require("ui.notify")
  N.show("info", WS.is_watched(it.path) and "marked watched" or "marked unwatched")
end

local function toggle_favorite()
  if #items == 0 then return end
  local it = items[sel]
  WS.toggle_favorite(it.path)
  local N = require("ui.notify")
  N.show("info", WS.is_favorite(it.path) and "starred" or "unstarred")
end

function M.pad(b)
  if b == Input.B or b == Input.SELECT then return "back" end
  if b == Input.UP then move(-1)
  elseif b == Input.DOWN then move(1)
  elseif b == Input.LEFT then cycle_view(-1)
  elseif b == Input.RIGHT then cycle_view(1)
  elseif b == Input.L1 then sel = math.max(1, sel - 10)
  elseif b == Input.R1 then sel = math.min(#items, sel + 10)
  elseif b == Input.L2 then cycle_sort()
  elseif b == Input.R2 then cycle_state()
  elseif b == Input.X then toggle_watched()
  elseif b == Input.Y then toggle_favorite()
  elseif b == Input.A then
    local it = items[sel]
    if it then return "open", it end
  end
  return false
end
function M.hat(dir)
  if dir == "up" then move(-1)
  elseif dir == "down" then move(1)
  elseif dir == "left" then cycle_view(-1)
  elseif dir == "right" then cycle_view(1) end
end
function M.key(k)
  if k == "up" then move(-1)
  elseif k == "down" then move(1)
  elseif k == "left" then cycle_view(-1)
  elseif k == "right" then cycle_view(1)
  elseif k == "q" then cycle_state()
  elseif k == "e" then cycle_sort()
  elseif k == "x" then toggle_watched()
  elseif k == "y" then toggle_favorite()
  elseif k == "return" or k == "space" then
    local it = items[sel]; if it then return "open", it end
  elseif k == "escape" then return "back" end
  return false
end

local function draw_empty()
  local th = T.current()
  love.graphics.setFont(A.font(A.FONT_BODY, 12))
  col(th.text_dim, 0.85)
  love.graphics.printf("(no items - press L2/R2 to change filter, or scan library)",
    0, TOP + (H - 140)/2, W, "center")
end

function M.draw()
  local th = T.current()
  D.bg()
  col(th.accent, 0.05)
  for y = 30, H - 20, 20 do
    for x = 0, W, 20 do love.graphics.rectangle("fill", x, y, 1, 1) end
  end
  local cats = LIB.categories
  local title = (cats[category] and cats[category].label) or "LIBRARY"
  local layout = VIEWS[view_idx]
  W_.header("CHOU HENKA - " .. title:upper(),
    "// " .. #items .. " items  -  " .. STATE_FILTERS[state_filter] ..
    "  -  sort: " .. sort_key .. "  -  view: " .. layout)

  if #items == 0 then draw_empty() return end

  local vp_y = TOP
  local vp_h = H - 40 - vp_y
  local w = W - PAD * 2

  local fn = ({
    list     = Views.draw_list,
    poster   = Views.draw_poster,
    wall     = Views.draw_wall,
    fanart   = Views.draw_fanart,
    infowall = Views.draw_infowall,
    widelist = Views.draw_widelist,
  })[layout] or Views.draw_list

  scroll = fn(items, PAD, vp_y, w, vp_h, sel, scroll, th.accent)

  love.graphics.setFont(A.font(A.FONT_MONO, 9))
  col(th.text_dim, 0.7)
  love.graphics.printf("A: open  -  X: watched  -  Y: star  -  L2: sort  -  R2: filter  -  L/R: view",
    0, H - 24, W, "center")
end

return M
