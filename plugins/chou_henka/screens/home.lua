-- screens/home.lua -- home scrollabile, icone dedicate.
local A = require("core.assets")
local D = require("ui.draw")
local Input = require("core.input_map")
local T = require("plugins.chou_henka.ui.theme")
local W_ = require("plugins.chou_henka.ui.widgets")
local Icons = require("plugins.chou_henka.ui.icons")
local Scroll = require("plugins.chou_henka.ui.scroll")
local LIB = require("plugins.chou_henka.core.library")
local WS  = require("plugins.chou_henka.core.watchstate")
local CFG = require("plugins.chou_henka.core.config")

local M = {}
local W, H = 640, 480
local sel, scroll_y, t = 1, 0, 0
local TILES = {}
local ROW_H = 68
local PAD = 24
local TOP = 100

local function col(c,a) love.graphics.setColor(c[1],c[2],c[3],a or 1) end

local function build_tiles()
  local tt = {}
  for _, k in ipairs(LIB.enabled_categories()) do
    local cat = LIB.categories[k]
    tt[#tt+1] = {
      key = k, label = cat.label:upper(),
      sub = (k=="audio" and "Tracks - Albums" or
             k=="video" and "Movies - Series" or
             k=="image" and "Photos - Artwork" or
             k=="comic" and "CBZ - CBR - CB7" or
             k=="book"  and "ePub - PDF" or
             k=="doc"   and "Office - Text" or "Misc"),
      colour = cat.colour, icon = k,
    }
  end
  local n_recent = #WS.list_recent(20)
  local n_resume = #WS.list_resume(20)
  tt[#tt+1] = { key="recent",    label="CONTINUE WATCHING", sub=n_resume .. " items",   colour={0.55,0.85,0.95}, icon="clock" }
  local n_fav = #WS.list_favorites()
  tt[#tt+1] = { key="favorites", label="FAVORITES", sub=n_fav .. " starred",        colour={0.95,0.80,0.30}, icon="star" }
  tt[#tt+1] = { key="search",    label="SEARCH",    sub="Find anything",            colour={0.48,0.80,0.90}, icon="search" }
  tt[#tt+1] = { key="all",       label="LIBRARY",   sub="Everything",               colour={0.95,0.40,0.85}, icon="library" }
  tt[#tt+1] = { key="addons",    label="ADDONS",    sub="Extensions & themes",      colour={0.55,0.85,0.95}, icon="addons" }
  tt[#tt+1] = { key="settings",  label="SETTINGS",  sub="Theme - Engine - Sources", colour={0.85,0.85,0.85}, icon="settings" }
  return tt
end

function M.enter() TILES = build_tiles(); sel = 1; scroll_y = 0; t = 0 end
function M.leave() end
function M.update(dt) t = t + dt end

local function move(d)
  sel = sel + d
  if sel < 1 then sel = #TILES end
  if sel > #TILES then sel = 1 end
end

function M.pad(b)
  if b == Input.UP then move(-1); return true
  elseif b == Input.DOWN then move(1); return true
  elseif b == Input.A then return "activate", TILES[sel] end
  return false
end
function M.hat(dir)
  if dir == "up" then move(-1)
  elseif dir == "down" then move(1) end
end
function M.key(k)
  if k == "up" then move(-1)
  elseif k == "down" then move(1)
  elseif k == "return" or k == "space" then return "activate", TILES[sel] end
  return false
end

function M.draw()
  local th = T.current()
  D.bg()
  col(th.accent, 0.05)
  for y = 30, H - 20, 20 do
    for x = 0, W, 20 do love.graphics.rectangle("fill", x, y, 1, 1) end
  end
  W_.header("CHOU HENKA MEDIA CENTER", "// mini media hub")

  local stats = LIB.count_by_cat()
  local total = 0
  for _, n in pairs(stats) do total = total + n end
  local scanned = LIB.scanned_at()
  local when = scanned > 0 and os.date("%m-%d %H:%M", scanned) or "never"
  love.graphics.setFont(A.font(A.FONT_MONO, 9))
  col(th.text_dim, 0.85)
  love.graphics.printf(total .. " media  -  last scan " .. when, 0, 76, W, "center")

  local vp_y = TOP
  local vp_h = H - 40 - vp_y
  local total_h = #TILES * (ROW_H + 6)
  scroll_y = Scroll.ensure((sel - 1) * (ROW_H + 6), ROW_H, scroll_y, vp_h)
  scroll_y = Scroll.clamp(scroll_y, total_h, vp_h)

  love.graphics.setScissor(PAD, vp_y, W - PAD*2, vp_h)
  for i, tile in ipairs(TILES) do
    local y = vp_y + (i - 1) * (ROW_H + 6) - scroll_y
    if y + ROW_H > vp_y - 4 and y < vp_y + vp_h + 4 then
      local focused = (i == sel)
      W_.card(PAD, y, W - PAD*2, ROW_H, tile.colour, focused)

      local icx, icy = PAD + 40, y + ROW_H/2
      col({tile.colour[1]*0.2, tile.colour[2]*0.2, tile.colour[3]*0.2}, 0.95)
      love.graphics.circle("fill", icx, icy, 22)
      Icons.draw(tile.icon, icx, icy, 13, tile.colour, 1)

      love.graphics.setFont(A.font(A.FONT_BODY_BOLD, 14))
      col(focused and {1,1,1} or tile.colour, 1)
      love.graphics.print(tile.label, PAD + 76, y + 12)

      love.graphics.setFont(A.font(A.FONT_MONO, 9))
      col(th.text_dim, 0.85)
      love.graphics.print(tile.sub, PAD + 76, y + 34)

      if tile.key ~= "settings" and tile.key ~= "addons" and tile.key ~= "search" then
        local n = (tile.key == "all") and total or (stats[tile.key] or 0)
        love.graphics.setFont(A.font(A.FONT_TITLE, 18))
        col(tile.colour, focused and 1 or 0.75)
        love.graphics.printf(tostring(n), PAD, y + ROW_H/2 - 12, W - PAD*2 - 20, "right")
      end
    end
  end
  love.graphics.setScissor()

  Scroll.bar(W - 8, vp_y, vp_h, scroll_y, total_h, vp_h, th.accent)

  love.graphics.setFont(A.font(A.FONT_MONO, 9))
  col(th.text_dim, 0.7)
  love.graphics.printf("A: open  -  B: back", 0, H - 24, W, "center")
end

return M
