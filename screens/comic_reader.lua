-- screens/comic_reader.lua -- Comic Reader+ with manga mode.
local A     = require("core.assets")
local State = require("core.state")
local Input = require("core.input_map")
local Frame = require("ui.frame")
local D     = require("ui.draw")
local Notify= require("ui.notify")
local ExtImg= require("core.external_image")
local Doc   = require("services.doc_engine")
local sh    = require("core.sh")
local JSON  = require("core.json")

local S = {}
local W, H = 640, 480
local acc = {0.95, 0.75, 0.35}

local doc       = nil
local doc_path  = nil
local page      = 1
local total     = 1
local manga     = false       -- right-to-left
local spread    = false       -- double-page
local zoom      = 1.0
local pan_x     = 0
local pan_y     = 0
local t_enter   = 0
local cache     = {}
local cache_lru = {}
local CACHE_MAX = 5
local show_help = false
local show_bookmarks = false
local bm_sel = 1

local BM_FILE = "data/comic_bookmarks.json"
local bookmarks = {}

local function col(c, a) love.graphics.setColor(c[1], c[2], c[3], a or 1) end
local function basename(p) return (p or ""):match("([^/]+)$") or p or "?" end

local function load_bookmarks()
  local f = io.open(BM_FILE, "r")
  if not f then bookmarks = {}; return end
  local c = f:read("*a"); f:close()
  local ok, d = pcall(JSON.decode, c)
  if ok and type(d) == "table" then bookmarks = d else bookmarks = {} end
end

local function save_bookmarks()
  os.execute("mkdir -p data")
  local f = io.open(BM_FILE, "w")
  if not f then return end
  f:write(JSON.encode(bookmarks)); f:close()
end

local function bookmark_key() return doc_path or "?" end

local function toggle_bookmark()
  local k = bookmark_key()
  bookmarks[k] = bookmarks[k] or {}
  -- toggle current page
  local has = false
  for i, p in ipairs(bookmarks[k]) do
    if p == page then table.remove(bookmarks[k], i); has = true; break end
  end
  if not has then table.insert(bookmarks[k], 1, page) end
  save_bookmarks()
  Notify.show("info", has and ("bookmark removed p." .. page)
                        or ("bookmarked p." .. page))
end

local function is_bookmarked()
  local k = bookmark_key()
  if not bookmarks[k] then return false end
  for _, p in ipairs(bookmarks[k]) do if p == page then return true end end
  return false
end

local function evict()
  local n = 0
  for _ in pairs(cache) do n = n + 1 end
  while n > CACHE_MAX do
    local oldest_k, oldest_t = nil, math.huge
    for k, t in pairs(cache_lru) do
      if t < oldest_t then oldest_t = t; oldest_k = k end
    end
    if not oldest_k then break end
    cache[oldest_k] = nil; cache_lru[oldest_k] = nil; n = n - 1
  end
end

local function load_page(p)
  if p < 1 or p > total then return nil end
  if cache[p] then cache_lru[p] = love.timer.getTime(); return cache[p] end
  local path = Doc.cbz_image(doc, p)
  local img = path and ExtImg.load(path)
  if img then
    cache[p] = img; cache_lru[p] = love.timer.getTime(); evict()
  end
  return img
end

local function goto_page(p)
  p = math.max(1, math.min(total, p))
  page = p
  pan_x, pan_y = 0, 0
  zoom = 1.0
  load_page(p)
  if spread then load_page(p + 1) end
end

local function next_page()
  local step = spread and 2 or 1
  -- In manga mode, physical right arrow goes to previous (lower index)
  local dir = manga and -1 or 1
  goto_page(page + step * dir)
end

local function prev_page()
  local step = spread and 2 or 1
  local dir = manga and -1 or 1
  goto_page(page - step * dir)
end

function S.enter()
  t_enter = 0
  cache = {}; cache_lru = {}
  manga = false; spread = false
  zoom = 1.0; pan_x, pan_y = 0, 0
  load_bookmarks()

  doc_path = State.comic_path
  State.comic_path = nil
  if not doc_path then
    Notify.show("warning", "no comic file")
    State.back(); return
  end

  local d, err = Doc.open(doc_path)
  if not d then
    Notify.show("error", err or "cannot open")
    State.back(); return
  end
  doc = d
  total = #doc.images
  -- resume from last bookmark if any
  local k = bookmark_key()
  if bookmarks[k] and #bookmarks[k] > 0 then
    page = bookmarks[k][1]
  else
    page = 1
  end
  goto_page(page)
end
function S.leave() cache = {}; cache_lru = {} end
function S.update(dt) t_enter = t_enter + dt end

function S.pad(b)
  if show_help then
    if b == Input.B or b == Input.A or b == Input.SELECT then show_help = false end
    return
  end
  if show_bookmarks then
    local list = bookmarks[bookmark_key()] or {}
    if     b == Input.UP   then bm_sel = math.max(1, bm_sel - 1)
    elseif b == Input.DOWN then bm_sel = math.min(#list, bm_sel + 1)
    elseif b == Input.A then
      local pg = list[bm_sel]
      if pg then goto_page(pg) end
      show_bookmarks = false
    elseif b == Input.X then
      local pg = list[bm_sel]
      if pg then
        -- Remove bookmark
        for i, p in ipairs(list) do
          if p == pg then table.remove(list, i); break end
        end
        save_bookmarks()
        if bm_sel > #list then bm_sel = math.max(1, #list) end
        Notify.show("info", "bookmark removed")
      end
    elseif b == Input.B or b == Input.SELECT then show_bookmarks = false end
    return
  end
  if     b == Input.B or b == Input.SELECT then State.back()
  elseif b == Input.L1 then prev_page()
  elseif b == Input.R1 then next_page()
  elseif b == Input.L2 then zoom = math.max(0.4, zoom - 0.10)
  elseif b == Input.R2 then zoom = math.min(3.0, zoom + 0.10)
  elseif b == Input.A  then
    -- In manga mode, A skips forward
    local dir = manga and -1 or 1
    goto_page(page + (spread and 2 or 1) * dir)
  elseif b == Input.X  then
    manga = not manga
    Notify.show("info", manga and "manga mode ON" or "manga mode OFF")
  elseif b == Input.Y  then
    spread = not spread
    Notify.show("info", spread and "double page ON" or "double page OFF")
    goto_page(page)
  elseif b == Input.LEFT  then next_page()  -- in RTL mode this is "forward"
  elseif b == Input.RIGHT then prev_page()
  elseif b == Input.UP    then pan_y = pan_y + 12
  elseif b == Input.DOWN  then pan_y = pan_y - 12
  elseif b == Input.START then toggle_bookmark()
  elseif b == Input.SELECT then
    show_bookmarks = true
    bm_sel = 1
  end
end
function S.hat(dir)
  if     dir == "left"  then next_page()
  elseif dir == "right" then prev_page()
  elseif dir == "up"    then pan_y = pan_y + 12
  elseif dir == "down"  then pan_y = pan_y - 12 end
end
function S.key(k)
  if show_help then
    if k == "escape" or k == "return" then show_help = false end
    return
  end
  if show_bookmarks then
    if k == "escape" or k == "backspace" then show_bookmarks = false end
    return
  end
  if show_bookmarks then
    if k == "escape" or k == "backspace" then show_bookmarks = false end
    return
  end
  if     k == "escape" or k == "backspace" then State.back()
  elseif k == "left"  then next_page()
  elseif k == "right" then prev_page()
  elseif k == "a"     then toggle_bookmark()
  elseif k == "m"     then manga = not manga end
end

function S.draw()
  local th = State.theme
  D.bg()

  if not doc then return end

  -- Header strip
  love.graphics.setColor(0.03, 0.025, 0.015, 0.95)
  love.graphics.rectangle("fill", 0, Frame.TOP_H, W, 24)
  col(acc, 0.9)
  love.graphics.rectangle("fill", 0, Frame.TOP_H + 23, W, 1)

  love.graphics.setFont(A.font(A.FONT_MONO, 11))
  col(acc, 1)
  love.graphics.print(basename(doc_path), 12, Frame.TOP_H + 6)

  local tag = ""
  if manga then tag = tag .. "[MANGA]" end
  if spread then tag = tag .. "[2P]" end
  if is_bookmarked() then tag = tag .. "[*]" end
  if tag ~= "" then
    col(acc, 0.8)
    love.graphics.printf(tag, 0, Frame.TOP_H + 6, W - 12, "right")
  end

  love.graphics.setFont(A.font(A.FONT_MONO, 12))
  col(acc, 1)
  love.graphics.printf(string.format("%d / %d", page, total),
    0, Frame.TOP_H + 6, W - 12, "right")

  -- Image area
  local avail_y = Frame.TOP_H + 28
  local avail_h = H - Frame.BOTTOM_H - avail_y - 4

  if spread then
    -- Two-page spread: left page and right page side by side
    local img1 = cache[page]
    local img2 = cache[page + 1]
    local half_w = (W - 8) / 2

    local function draw_half(img, hx, hw)
      if not img then return end
      local iw, ih = img:getDimensions()
      local sc = math.min(hw / iw, avail_h / ih)
      local dw, dh = iw * sc, ih * sc
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(img, hx + (hw - dw) / 2,
        avail_y + (avail_h - dh) / 2, 0, sc, sc)
      love.graphics.setColor(1, 1, 1, 1)
    end

    if manga then
      -- Manga: right page is lower index, left is higher
      draw_half(img2, 4, half_w)
      draw_half(img1, 4 + half_w, half_w)
    else
      draw_half(img1, 4, half_w)
      draw_half(img2, 4 + half_w, half_w)
    end
  else
    local img = cache[page]
    if img then
      local iw, ih = img:getDimensions()
      local sc = math.min((W - 16) / iw, avail_h / ih) * zoom
      local dw, dh = iw * sc, ih * sc
      local cx = W / 2 + pan_x
      local cy = avail_y + avail_h / 2 + pan_y
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(img, cx - dw/2, cy - dh/2, 0, sc, sc)
      love.graphics.setColor(1, 1, 1, 1)
    end
  end

  -- Page dots at the bottom
  love.graphics.setFont(A.font(A.FONT_MONO, 9))
  col(acc, 0.7)
  local dots_y = H - Frame.BOTTOM_H - 14
  local start = math.max(1, page - 8)
  local stop  = math.min(total, page + 8)
  local dots_str = ""
  for i = start, stop do
    if i == page then dots_str = dots_str .. "[O]"
    else dots_str = dots_str .. " o " end
  end
  love.graphics.printf(dots_str, 0, dots_y, W, "center")

  Frame.draw_top("FGD", "plugins")
  Frame.draw_bottom({
    { key = "l1",  label = "Prev" },
    { key = "r1",  label = "Next" },
    { key = "x",   label = "Manga" },
    { key = "y",   label = "2-Page" },
    { key = "start",label = "Bookmark" },
    { key = "select",label = "Bookmarks" },
    { key = "b",   label = "Back" },
  })

  -- Bookmark list overlay
  if show_bookmarks then
    love.graphics.setColor(0, 0, 0, 0.80)
    love.graphics.rectangle("fill", 0, 0, W, H)
    local x, y = 60, 50
    local w, h = W - 120, H - 100
    col({0.030, 0.020, 0.020}, 0.98)
    love.graphics.rectangle("fill", x, y, w, h, 5, 5)
    col(acc, 0.9)
    love.graphics.setLineWidth(1.6)
    love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, 5, 5)
    love.graphics.setLineWidth(1)
    D.corner_ticks(x + 8, y + 8, w - 16, h - 16, 12, acc, 0.9)

    love.graphics.setFont(A.font(A.FONT_TITLE, 16))
    col(acc, 1)
    love.graphics.print("BOOKMARKS", x + 20, y + 14)

    local list = bookmarks[bookmark_key()] or {}
    if #list == 0 then
      love.graphics.setFont(A.font(A.FONT_BODY, 12))
      love.graphics.setColor(1, 1, 1, 0.7)
      love.graphics.printf("no bookmarks yet\n\npress START to bookmark a page",
        x, y + h/2 - 20, w, "center")
    else
      local row_h = 24
      for i, pg in ipairs(list) do
        local ry = y + 42 + (i - 1) * row_h
        if ry + row_h > y + h - 8 then break end
        local focused = (i == bm_sel)
        if focused then
          col(acc, 0.20)
          love.graphics.rectangle("fill", x + 14, ry - 2, w - 28, row_h - 2, 3, 3)
          col(acc, 0.9)
          love.graphics.rectangle("line", x + 14.5, ry - 1.5, w - 29, row_h - 3, 3, 3)
        end
        love.graphics.setFont(A.font(A.FONT_MONO, 12))
        love.graphics.setColor(1, 1, 1, focused and 1 or 0.85)
        love.graphics.print("page " .. pg, x + 30, ry + 4)
        love.graphics.setFont(A.font(A.FONT_MONO, 9))
        col(acc, 0.7)
        love.graphics.printf("A open  X delete", 0, ry + 6, x + w - 20, "right")
      end
    end
    love.graphics.setFont(A.font(A.FONT_MONO, 9))
    col(acc, 0.7)
    love.graphics.printf("B close", x, y + h - 16, w, "center")
  end

  D.scanlines(W, H, 0.06)
end

return S
