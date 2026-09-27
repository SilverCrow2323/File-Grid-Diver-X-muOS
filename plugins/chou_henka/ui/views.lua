-- ui/views.lua -- renderer per view Kodi-style con poster e fanart reali.
local A       = require("core.assets")
local D       = require("ui.draw")
local Icons   = require("plugins.chou_henka.ui.icons")
local Poster  = require("plugins.chou_henka.ui.poster")
local Scroll  = require("plugins.chou_henka.ui.scroll")
local T       = require("plugins.chou_henka.ui.theme")
local WS      = require("plugins.chou_henka.core.watchstate")

local M = {}
local function col(c, a) love.graphics.setColor(c[1], c[2], c[3], a or 1) end
local function human(n)
  if not n or n <= 0 then return "0 B" end
  local u = {"B","KB","MB","GB","TB"}; local i = 1
  while n >= 1024 and i < #u do n = n/1024; i = i + 1 end
  if i == 1 then return string.format("%d %s", n, u[i]) end
  return string.format("%.1f %s", n, u[i])
end

-- Disegna un poster (o fallback icona) in una cella
local function draw_poster(it, x, y, w, h, accent, focused)
  local img = Poster.get(it.poster)
  if not img then img = Poster.get(it.thumb) end
  if img then
    local iw, ih = img:getDimensions()
    -- aspect fill: riempi tutta la cella, taglia
    local sc = math.max(w / iw, h / ih)
    local dw, dh = iw * sc, ih * sc
    local ox = (w - dw) / 2
    local oy = (h - dh) / 2
    love.graphics.setScissor(x, y, w, h)
    love.graphics.setColor(1, 1, 1, focused and 1 or 0.88)
    love.graphics.draw(img, x + ox, y + oy, 0, sc, sc)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setScissor()
  else
    -- fallback: sfondo + icona categoria
    col({accent[1]*0.14, accent[2]*0.14, accent[3]*0.14}, 1)
    love.graphics.rectangle("fill", x, y, w, h, 3, 3)
    Icons.draw(it.cat or "doc", x + w/2, y + h/2, math.min(w, h) * 0.22,
      accent, focused and 0.9 or 0.6)
  end
  -- overlay watch marker
  if WS.is_watched(it.path) then
    col({0.30, 0.90, 0.45}, 0.9)
    love.graphics.rectangle("fill", x + 2, y + 2, 14, 10, 2, 2)
    love.graphics.setFont(A.font(A.FONT_MONO, 8))
    col({0.05, 0.10, 0.05}, 1)
    love.graphics.print("W", x + 5, y + 3)
  end
  -- badge resume
  local rs = WS.get_resume(it.path)
  if rs then
    local bw = 26
    col({0.48, 0.80, 0.90}, 0.9)
    love.graphics.rectangle("fill", x + w - bw - 2, y + 2, bw, 10, 2, 2)
    love.graphics.setFont(A.font(A.FONT_MONO, 7))
    col({0.05, 0.10, 0.15}, 1)
    love.graphics.printf(string.format("%d%%", math.floor((rs.pct or 0) * 100)),
      x + w - bw - 2, y + 3, bw, "center")
  end
end

local function draw_star(x, y, filled, accent)
  -- piccola stella
  col(accent, filled and 1 or 0.4)
  local pts = {}
  local rr = 6
  for i = 0, 9 do
    local a = -math.pi/2 + i * math.pi/5
    local rad = (i % 2 == 0) and rr or rr * 0.45
    pts[#pts+1] = x + math.cos(a) * rad
    pts[#pts+1] = y + math.sin(a) * rad
  end
  if filled then
    love.graphics.polygon("fill", pts)
  else
    love.graphics.polygon("line", pts)
  end
end

-- ── LIST ─────────────────────────────────────────────────────
function M.draw_list(items, x, y, w, h, sel, scroll, accent)
  local row_h = 26
  local total_h = #items * row_h
  scroll = Scroll.ensure((sel - 1) * row_h, row_h, scroll, h)
  scroll = Scroll.clamp(scroll, total_h, h)
  love.graphics.setScissor(x, y, w, h)
  for i, it in ipairs(items) do
    local ry = y + (i - 1) * row_h - scroll
    if ry + row_h > y - 4 and ry < y + h + 4 then
      local focused = (i == sel)
      if focused then
        col(accent, 0.20)
        love.graphics.rectangle("fill", x, ry, w, row_h - 2, 2, 2)
      end
      Icons.draw(it.cat or "doc", x + 16, ry + row_h/2 - 1, 8,
        T.current().text_dim, focused and 1 or 0.7)
      love.graphics.setFont(A.font(A.FONT_BODY, 11))
      col(focused and {1,1,1} or T.current().text, 1)
      local nm = it.title or it.name or "?"
      if WS.is_watched(it.path) then nm = "[W] " .. nm end
      if #nm > 55 then nm = nm:sub(1, 54) .. "..." end
      love.graphics.print(nm, x + 32, ry + 5)
      love.graphics.setFont(A.font(A.FONT_MONO, 9))
      col(T.current().text_dim, 0.75)
      love.graphics.printf(human(it.size), 0, ry + 6, x + w - 8, "right")
    end
  end
  love.graphics.setScissor()
  Scroll.bar(x + w + 6, y, h, scroll, total_h, h, accent)
  return scroll
end

-- ── WIDELIST (thumb a sinistra) ──────────────────────────────
function M.draw_widelist(items, x, y, w, h, sel, scroll, accent)
  local row_h = 64
  local thumb_w, thumb_h = 100, 56
  local total_h = #items * row_h
  scroll = Scroll.ensure((sel - 1) * row_h, row_h, scroll, h)
  scroll = Scroll.clamp(scroll, total_h, h)
  love.graphics.setScissor(x, y, w, h)
  for i, it in ipairs(items) do
    local ry = y + (i - 1) * row_h - scroll
    if ry + row_h > y - 4 and ry < y + h + 4 then
      local focused = (i == sel)
      if focused then
        col(accent, 0.20)
        love.graphics.rectangle("fill", x, ry, w, row_h - 2, 3, 3)
      end
      draw_poster(it, x + 4, ry + 4, thumb_w, thumb_h, accent, focused)
      local tx = x + thumb_w + 12
      love.graphics.setFont(A.font(A.FONT_BODY_BOLD, 12))
      col(focused and {1,1,1} or T.current().text, 1)
      local nm = it.title or it.name or "?"
      if #nm > 46 then nm = nm:sub(1, 45) .. "..." end
      love.graphics.print(nm, tx, ry + 8)
      love.graphics.setFont(A.font(A.FONT_MONO, 9))
      col(T.current().text_dim, 0.85)
      local meta = {}
      if it.year then meta[#meta+1] = it.year end
      if it.rating then meta[#meta+1] = string.format("%.1f", it.rating) end
      meta[#meta+1] = human(it.size)
      love.graphics.print(table.concat(meta, "  -  "), tx, ry + 28)
      if it.plot and it.plot ~= "" then
        love.graphics.setFont(A.font(A.FONT_BODY, 9))
        col(T.current().text_dim, 0.7)
        local plot = it.plot:gsub("\n", " ")
        if #plot > 60 then plot = plot:sub(1, 59) .. "..." end
        love.graphics.print(plot, tx, ry + 44)
      end
    end
  end
  love.graphics.setScissor()
  Scroll.bar(x + w + 6, y, h, scroll, total_h, h, accent)
  return scroll
end

-- ── POSTER (2:3) ─────────────────────────────────────────────
local function draw_grid_generic(items, x, y, w, h, sel, scroll, accent,
                                 cell_w, cell_h, label_lines, show_plot)
  local gap = 8
  local cols = math.max(1, math.floor((w + gap) / (cell_w + gap)))
  local rows = math.ceil(#items / cols)
  local row_h = cell_h + gap + (label_lines or 1) * 12
  local total_h = rows * row_h
  local sel_row = math.floor((sel - 1) / cols)
  scroll = Scroll.ensure(sel_row * row_h, row_h, scroll, h)
  scroll = Scroll.clamp(scroll, total_h, h)
  love.graphics.setScissor(x, y, w, h)
  for i, it in ipairs(items) do
    local idx = i - 1
    local gx = idx % cols
    local gy = math.floor(idx / cols)
    local cx = x + gx * (cell_w + gap)
    local cy = y + gy * row_h - scroll
    if cy + row_h > y - 8 and cy < y + h + 8 then
      local focused = (i == sel)
      draw_poster(it, cx, cy, cell_w, cell_h, accent, focused)
      if focused then
        col(accent, 0.95)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", cx - 1.5, cy - 1.5,
          cell_w + 3, cell_h + 3, 3, 3)
        love.graphics.setLineWidth(1)
      end
      -- label
      love.graphics.setFont(A.font(A.FONT_BODY, 9))
      col(focused and {1,1,1} or T.current().text, 1)
      local nm = it.title or it.name or "?"
      local max_chars = math.floor(cell_w / 6)
      if #nm > max_chars then nm = nm:sub(1, max_chars - 1) .. "..." end
      love.graphics.printf(nm, cx, cy + cell_h + 2, cell_w, "center")
      if label_lines and label_lines >= 2 then
        local sub = {}
        if it.year then sub[#sub+1] = tostring(it.year) end
        if it.rating then sub[#sub+1] = string.format("%.1f", it.rating) end
        if #sub > 0 then
          love.graphics.setFont(A.font(A.FONT_MONO, 8))
          col(T.current().text_dim, 0.8)
          love.graphics.printf(table.concat(sub, " - "),
            cx, cy + cell_h + 14, cell_w, "center")
        end
      end
    end
  end
  love.graphics.setScissor()
  Scroll.bar(x + w + 6, y, h, scroll, total_h, h, accent)
  return scroll
end

function M.draw_poster(items, x, y, w, h, sel, scroll, accent)
  return draw_grid_generic(items, x, y, w, h, sel, scroll, accent,
    76, 110, 2, false)
end

function M.draw_wall(items, x, y, w, h, sel, scroll, accent)
  return draw_grid_generic(items, x, y, w, h, sel, scroll, accent,
    120, 76, 1, false)
end

-- ── FANART: background + griglia piccola ─────────────────────
function M.draw_fanart(items, x, y, w, h, sel, scroll, accent)
  -- sfondo fanart dell'item selezionato
  local cur = items[sel]
  if cur then
    local bg = Poster.get(cur.fanart) or Poster.get(cur.poster)
    if bg then
      local iw, ih = bg:getDimensions()
      local sc = math.max(w / iw, h / ih)
      local dw, dh = iw * sc, ih * sc
      love.graphics.setScissor(x, y, w, h)
      love.graphics.setColor(1, 1, 1, 0.35)
      love.graphics.draw(bg, x + (w - dw) / 2, y + (h - dh) / 2, 0, sc, sc)
      love.graphics.setColor(0, 0, 0, 0.55)
      love.graphics.rectangle("fill", x, y, w, h)
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.setScissor()
    end
  end
  return draw_grid_generic(items, x, y, w, h, sel, scroll, accent,
    150, 84, 1, false)
end

-- ── INFOWALL: poster + info estese ───────────────────────────
function M.draw_infowall(items, x, y, w, h, sel, scroll, accent)
  local gap = 8
  local cell_w, cell_h = 130, 150
  local cols = math.max(1, math.floor((w + gap) / (cell_w + gap)))
  local rows = math.ceil(#items / cols)
  local row_h = cell_h + gap
  local total_h = rows * row_h
  local sel_row = math.floor((sel - 1) / cols)
  scroll = Scroll.ensure(sel_row * row_h, row_h, scroll, h)
  scroll = Scroll.clamp(scroll, total_h, h)
  love.graphics.setScissor(x, y, w, h)
  for i, it in ipairs(items) do
    local idx = i - 1
    local gx = idx % cols
    local gy = math.floor(idx / cols)
    local cx = x + gx * (cell_w + gap)
    local cy = y + gy * row_h - scroll
    if cy + row_h > y - 8 and cy < y + h + 8 then
      local focused = (i == sel)
      local p_w = cell_w - 40
      local p_h = 96
      draw_poster(it, cx + 2, cy + 2, p_w, p_h, accent, focused)
      -- info a destra
      local tx = cx + p_w + 8
      local tw = cell_w - p_w - 10
      love.graphics.setFont(A.font(A.FONT_BODY_BOLD, 10))
      col(focused and {1,1,1} or T.current().text, 1)
      local nm = it.title or it.name or "?"
      love.graphics.printf(nm, tx, cy + 4, tw, "left")
      love.graphics.setFont(A.font(A.FONT_MONO, 8))
      col(T.current().text_dim, 0.85)
      if it.year then love.graphics.print(it.year, tx, cy + 30) end
      if it.rating then
        col(accent, 1)
        love.graphics.print(string.format("%.1f", it.rating), tx, cy + 44)
        draw_star(tx + tw - 8, cy + 48, true, accent)
      end
      col(T.current().text_dim, 0.7)
      love.graphics.print(human(it.size), tx, cy + 60)
      if focused then
        col(accent, 0.9)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", cx - 1.5, cy - 1.5,
          cell_w + 3, cell_h + 3, 3, 3)
        love.graphics.setLineWidth(1)
      end
      -- plot sotto
      if it.plot and it.plot ~= "" then
        love.graphics.setFont(A.font(A.FONT_BODY, 8))
        col(T.current().text_dim, 0.7)
        local plot = it.plot:gsub("\n", " ")
        if #plot > 42 then plot = plot:sub(1, 41) .. "..." end
        love.graphics.printf(plot, cx + 2, cy + p_h + 6, cell_w - 4, "left")
      end
    end
  end
  love.graphics.setScissor()
  Scroll.bar(x + w + 6, y, h, scroll, total_h, h, accent)
  return scroll
end

return M
