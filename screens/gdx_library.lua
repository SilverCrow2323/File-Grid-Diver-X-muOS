-- screens/gdx_library.lua -- GD-X Library reader + browse mode.
-- Open with a file: read it. Open without: browse all books/comics.
local A     = require("core.assets")
local State = require("core.state")
local Input = require("core.input_map")
local Frame = require("ui.frame")
local D     = require("ui.draw")
local Notify= require("ui.notify")
local Modal = require("ui.modal")
local Doc   = require("services.doc_engine")
local ExtImg= require("core.external_image")
local sh    = require("core.sh")
local BM    = require("services.bookmarks")

local S = {}
local W, H = 640, 480

local acc = {0.70, 0.55, 0.92}

-- Reader state
local doc        = nil
local doc_path   = nil
local page       = 1
local total      = 1
local scroll     = 0
local zoom       = 1.0
local pan_x      = 0
local pan_y      = 0
local t_enter    = 0
local status     = ""
local cache_img  = {}
local cache_lru  = {}
local CACHE_MAX  = 5
local epub_blocks = nil
local epub_toc    = nil
local toc_open    = false
local toc_sel     = 1
local reader_theme = "dark"   -- "dark" | "amber" | "light"
local THEMES = {
  dark  = { bg = {0.020, 0.018, 0.026}, text = {0.95, 0.95, 0.95}, dim = {0.60, 0.60, 0.65} },
  amber = { bg = {0.070, 0.045, 0.020}, text = {1.00, 0.85, 0.55}, dim = {0.80, 0.65, 0.40} },
  light = { bg = {0.92, 0.92, 0.88},    text = {0.10, 0.10, 0.12}, dim = {0.40, 0.40, 0.45} },
}

-- Browse state
local mode       = "reader"     -- "reader" | "browse"
local browse_items  = {}        -- { path=, name=, kind=, size=, cover= }
local browse_sel    = 1
local browse_scroll = 0
local browse_loaded = false

local function col(c, a) love.graphics.setColor(c[1], c[2], c[3], a or 1) end
local function basename(p) return (p or ""):match("([^/]+)$") or p or "?" end

-- ============================================================
--  Browse mode: scan folders for readable media
-- ============================================================
local SCAN_ROOTS = {
  "/mnt/mmc/Books", "/mnt/mmc/Documents", "/mnt/mmc/Comics",
  "/mnt/sdcard/Books", "/mnt/sdcard/Documents", "/mnt/sdcard/Comics",
  "/mnt/mmc/MUOS/Documents", "/mnt/mmc/downloads",
  os.getenv("HOME") .. "/Books",
  os.getenv("HOME") .. "/Documents",
}

local function clear_browse()
  browse_items = {}
  browse_sel = 1
  browse_scroll = 0
  browse_loaded = false
end

local function kind_of(path)
  local ext = (path:match("%.([^.]+)$") or ""):lower()
  if ext == "pdf" then return "PDF"
  elseif ext == "epub" then return "EPUB"
  elseif ext == "cbz" or ext == "cbr" or ext == "cb7" then return "COMIC"
  end
  return nil
end

local function try_cover(path, kind)
  local tmp = "/tmp/fgd_cov_" ..
    tostring(os.time()) .. "_" .. tostring(math.random(1000, 9999)) .. ".png"
  if kind == "COMIC" then
    -- Extract first image from the archive
    local ext = (path:match("%.([^.]+)$") or ""):lower()
    if ext == "cbz" or ext == "cb7" then
      sh.exec("unzip -o -q " .. sh.shq(path) .. " -d /tmp/fgd_cbz_cov/ 2>/dev/null")
      local h = io.popen("find /tmp/fgd_cbz_cov -type f \\( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \\) 2>/dev/null | sort | head -1")
      if h then
        local first = h:read("*l")
        h:close()
        if first and first ~= "" then
          local img = ExtImg.load(first)
          os.execute("rm -rf /tmp/fgd_cbz_cov")
          return img
        end
      end
    elseif ext == "cbr" then
      sh.exec("mkdir -p /tmp/fgd_cbr_cov && unrar x -o+ " .. sh.shq(path) ..
        " /tmp/fgd_cbr_cov/ 2>/dev/null")
      local h = io.popen("find /tmp/fgd_cbr_cov -type f \\( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \\) 2>/dev/null | sort | head -1")
      if h then
        local first = h:read("*l")
        h:close()
        if first and first ~= "" then
          local img = ExtImg.load(first)
          os.execute("rm -rf /tmp/fgd_cbr_cov")
          return img
        end
      end
    end
  elseif kind == "PDF" then
    -- Try mutool if available
    if sh.exec("command -v mutool >/dev/null 2>&1") == 0 then
      sh.exec("mutool draw -o " .. sh.shq(tmp) .. " -r 40 " .. sh.shq(path) .. " 1 2>/dev/null")
      if sh.exists(tmp) then
        local img = ExtImg.load(tmp)
        os.remove(tmp)
        return img
      end
    end
  end
  return nil
end

local function load_browse()
  clear_browse()
  browse_loaded = true
  local seen = {}
  for _, root in ipairs(SCAN_ROOTS) do
    if sh.is_dir(root) then
      local h = io.popen("find " .. sh.shq(root) ..
        " -maxdepth 3 -type f \\( -iname '*.pdf' -o -iname '*.epub' -o -iname '*.cbz' -o -iname '*.cbr' -o -iname '*.cb7' \\) 2>/dev/null | sort")
      if h then
        for line in h:lines() do
          if line ~= "" and not seen[line] then
            seen[line] = true
            local kind = kind_of(line)
            if kind then
              browse_items[#browse_items + 1] = {
                path = line,
                name = basename(line),
                kind = kind,
                cover = nil,   -- lazy load on focus
              }
            end
          end
        end
        h:close()
      end
    end
  end
  table.sort(browse_items, function(a, b) return a.name:lower() < b.name:lower() end)
end

-- ============================================================
--  Reader: PDF/EPUB/CBZ
-- ============================================================
local function clear_cache()
  cache_img = {}
  cache_lru = {}
end

local function evict_if_needed()
  local n = 0
  for _ in pairs(cache_img) do n = n + 1 end
  while n > CACHE_MAX do
    local oldest_k, oldest_t = nil, math.huge
    for k, t in pairs(cache_lru) do
      if t < oldest_t then oldest_t = t; oldest_k = k end
    end
    if not oldest_k then break end
    cache_img[oldest_k] = nil
    cache_lru[oldest_k] = nil
    n = n - 1
  end
end

local function load_pdf_page(p)
  if cache_img[p] then
    cache_lru[p] = love.timer.getTime()
    return cache_img[p]
  end
  status = "rendering page " .. p .. "..."
  local png = Doc.pdf_page(doc, p, 96)
  status = ""
  if not png then return nil end
  local img = ExtImg.load(png)
  if img then
    cache_img[p] = img
    cache_lru[p] = love.timer.getTime()
    evict_if_needed()
  end
  return img
end

local function load_cbz_page(p)
  if p < 1 or p > #doc.images then return nil end
  if cache_img[p] then
    cache_lru[p] = love.timer.getTime()
    return cache_img[p]
  end
  local path = Doc.cbz_image(doc, p)
  local img = path and ExtImg.load(path)
  if img then
    cache_img[p] = img
    cache_lru[p] = love.timer.getTime()
    evict_if_needed()
  end
  return img
end

local function load_epub_page(p)
  epub_blocks = Doc.epub_page(doc, p) or {}
  scroll = 0
end

local function goto_page(p)
  p = math.max(1, math.min(total, p))
  page = p
  scroll = 0
  pan_x, pan_y = 0, 0
  zoom = 1.0
  if doc.kind == "epub" then load_epub_page(p)
  elseif doc.kind == "pdf" then load_pdf_page(p)
  elseif doc.kind == "cbz" then load_cbz_page(p) end
end

local function open_reader(path)
  clear_cache()
  scroll = 0; zoom = 1.0; pan_x, pan_y = 0, 0
  page = 1
  epub_blocks = nil

  local d, err = Doc.open(path)
  if not d then
    Notify.show("error", err or "cannot open")
    return false
  end
  doc = d
  doc_path = path
  if doc.kind == "pdf" then total = doc.pages
  elseif doc.kind == "epub" then total = #doc.spine
  elseif doc.kind == "cbz" then total = #doc.images end
  goto_page(1)
  mode = "reader"
  return true
end

-- ============================================================
--  Lifecycle
-- ============================================================
function S.enter()
  t_enter = 0
  clear_cache()
  epub_blocks = nil
  -- Load persisted reader theme
  do
    local ok, Store = pcall(require, "core.settings_store")
    if ok then
      local saved = Store.get("reader", "theme")
      if saved and THEMES[saved] then reader_theme = saved end
    end
  end
  -- Load persisted reader theme
  do
    local ok, Store = pcall(require, "core.settings_store")
    if ok then
      local saved = Store.get("reader", "theme")
      if saved and THEMES[saved] then reader_theme = saved end
    end
  end

  local path = State.library_path
  State.library_path = nil

  if path and path ~= "" then
    if open_reader(path) then
      -- Load TOC for EPUB
      if doc and doc.kind == "epub" then
        epub_toc = Doc.epub_toc(doc) or {}
      end
      -- Restore bookmark
      local bm = BM.reader_get(path)
      if bm and bm.page then goto_page(bm.page) end
      return
    end
  end

  -- No file: browse mode
  mode = "browse"
  load_browse()
  browse_sel = 1
  browse_scroll = 0
end

function S.leave()
  -- Save bookmark for the current file
  if doc_path and page and total > 0 then
    BM.reader_set(doc_path, page, scroll)
  end
  clear_cache()
  epub_blocks = nil
  epub_toc = nil
  toc_open = false
end

function S.update(dt)
  t_enter = t_enter + dt
  -- Auto-save bookmark every 5s
  S._bm_t = (S._bm_t or 0) + dt
  if S._bm_t > 5 and doc_path and page and total > 0 then
    S._bm_t = 0
    BM.reader_set(doc_path, page, scroll)
  end
  -- Lazy-load cover for focused browse item
  if mode == "browse" and browse_items[browse_sel] then
    local it = browse_items[browse_sel]
    if not it.cover and not it._tried then
      it._tried = true
      it.cover = try_cover(it.path, it.kind)
    end
  end
end

-- ============================================================
--  Input
-- ============================================================
local function reader_pad(b)
  if Modal.is_open() then
    if b == Input.A then Modal.accept()
    elseif b == Input.B then Modal.cancel() end
    return
  end

  -- TOC open: up/down naviga, A salta, B chiude
  if toc_open then
    if     b == Input.UP   then toc_sel = math.max(1, toc_sel - 1)
    elseif b == Input.DOWN then toc_sel = math.min(#epub_toc, toc_sel + 1)
    elseif b == Input.A then
      local item = epub_toc[toc_sel]
      if item and item.spine_idx then goto_page(item.spine_idx) end
      toc_open = false
    elseif b == Input.B or b == Input.SELECT then toc_open = false end
    return
  end

  if     b == Input.B or b == Input.SELECT then
    if State._lib_from_browse then
      State._lib_from_browse = nil
      mode = "browse"
      doc = nil
      doc_path = nil
    else
      State.back()
    end
  elseif b == Input.L1 then goto_page(page - 1)
  elseif b == Input.R1 then goto_page(page + 1)
  elseif b == Input.L2 then zoom = math.max(0.4, zoom - 0.10)
  elseif b == Input.R2 then zoom = math.min(3.0, zoom + 0.10)
  elseif b == Input.X  then
    -- Cycle reader theme and persist
    local cycle = { dark = "amber", amber = "light", light = "dark" }
    reader_theme = cycle[reader_theme] or "dark"
    do
      local ok, Store = pcall(require, "core.settings_store")
      if ok then
        Store.set("reader", "theme", reader_theme)
        Store.save()
      end
    end
    Notify.show("info", "reader theme: " .. reader_theme)
  elseif b == Input.Y  then
    -- Toggle TOC (EPUB only)
    if doc and doc.kind == "epub" and epub_toc and #epub_toc > 0 then
      toc_open = not toc_open
      toc_sel = 1
    else
      goto_page(total)
    end
  elseif b == Input.A  then
    local KB = require("ui.keyboard")
    KB.open({
      title = "Go to page (1.." .. total .. ")",
      initial = tostring(page),
      multiline = false,
      on_accept = function(t)
        local n = tonumber(t)
        if n then goto_page(n) end
      end,
    })
  end
end

local function browse_pad(b)
  if Modal.is_open() then
    if b == Input.A then Modal.accept()
    elseif b == Input.B then Modal.cancel() end
    return
  end
  local n = #browse_items
  if n == 0 then
    if b == Input.B or b == Input.SELECT then State.back() end
    return
  end
  if b == Input.B or b == Input.SELECT then State.back()
  elseif b == Input.UP   then browse_sel = math.max(1, browse_sel - 1)
  elseif b == Input.DOWN then browse_sel = math.min(n, browse_sel + 1)
  elseif b == Input.A    then
    local it = browse_items[browse_sel]
    if it then
      State._lib_from_browse = true
      open_reader(it.path)
    end
  end
end

function S.pad(b)
  if mode == "browse" then browse_pad(b) else reader_pad(b) end
end

function S.hat(dir)
  if Modal.is_open() then return end
  if mode == "browse" then
    local n = #browse_items
    if n == 0 then return end
    if     dir == "up"   then browse_sel = math.max(1, browse_sel - 1)
    elseif dir == "down" then browse_sel = math.min(n, browse_sel + 1) end
    return
  end
  if doc and doc.kind == "epub" then
    if     dir == "up"   then scroll = scroll - 24
    elseif dir == "down" then scroll = scroll + 24 end
  elseif doc and (doc.kind == "pdf" or doc.kind == "cbz") then
    if     dir == "up"    then pan_y = pan_y + 12
    elseif dir == "down"  then pan_y = pan_y - 12
    elseif dir == "left"  then pan_x = pan_x + 12
    elseif dir == "right" then pan_x = pan_x - 12 end
  end
end

function S.key(k)
  local KB = require("ui.keyboard")
  if KB.is_open() then KB.key(k); return end
  if Modal.is_open() then
    if k == "return" then Modal.accept()
    elseif k == "escape" then Modal.cancel() end
    return
  end
  if mode == "browse" then
    if k == "up"   then S.hat("up")
    elseif k == "down" then S.hat("down")
    elseif k == "return" or k == "space" then S.pad(Input.A)
    elseif k == "escape" or k == "backspace" then S.pad(Input.B) end
    return
  end
  -- Reader
  if     k == "escape" or k == "backspace" then S.pad(Input.B)
  elseif k == "left"  or k == "pageup"   then goto_page(page - 1)
  elseif k == "right" or k == "pagedown" then goto_page(page + 1)
  elseif k == "up"    then scroll = scroll - 30
  elseif k == "down"  then scroll = scroll + 30
  elseif k == "="     then zoom = math.min(3.0, zoom + 0.1)
  elseif k == "-"     then zoom = math.max(0.4, zoom - 0.1)
  elseif k == "home"  then goto_page(1)
  elseif k == "end"   then goto_page(total) end
end

-- ============================================================
--  Drawing: browse mode
-- ============================================================
local function draw_browse()
  local title = "GD-X LIBRARY"
  love.graphics.setFont(A.font(A.FONT_TITLE, 22))
  col(acc, 1)
  love.graphics.printf(title, 0, Frame.TOP_H + 14, W, "center")

  love.graphics.setFont(A.font(A.FONT_MONO, 10))
  col(acc, 0.7)
  love.graphics.printf(#browse_items .. " items  --  A opens  --  B back",
    0, Frame.TOP_H + 44, W, "center")

  local vp_y = Frame.TOP_H + 68
  local vp_h = H - Frame.BOTTOM_H - vp_y - 4

  if #browse_items == 0 then
    col(State.theme.text_dim, 0.8)
    love.graphics.setFont(A.font(A.FONT_BODY, 12))
    love.graphics.printf(
      "no books, comics or PDFs found.\n\nScanned folders:\n" ..
      "/mnt/mmc/Books  ·  /mnt/mmc/Documents  ·  /mnt/mmc/Comics\n" ..
      "/mnt/sdcard/Books  ·  /mnt/sdcard/Documents  ·  /mnt/sdcard/Comics",
      W/2 - 250, vp_y + vp_h/2 - 60, 500, "center")
    return
  end

  -- Grid: 4 columns
  local cols = 4
  local cw = (W - 40 - (cols - 1) * 10) / cols
  local ch = 150
  local rows_visible = math.max(1, math.floor(vp_h / (ch + 8)))
  local per_page = cols * rows_visible

  -- Keep selection visible
  local sel_row = math.floor((browse_sel - 1) / cols)
  local top_row = math.floor(browse_scroll / cols)
  if sel_row < top_row then
    browse_scroll = sel_row * cols
  elseif sel_row >= top_row + rows_visible then
    browse_scroll = (sel_row - rows_visible + 1) * cols
  end
  browse_scroll = math.max(0, math.min(browse_scroll, math.max(0, #browse_items - per_page)))

  love.graphics.setScissor(0, vp_y, W, vp_h)
  for i = browse_scroll + 1, math.min(#browse_items, browse_scroll + per_page) do
    local idx = i - browse_scroll - 1
    local gx = idx % cols
    local gy = math.floor(idx / cols)
    local x = 20 + gx * (cw + 10)
    local y = vp_y + gy * (ch + 8)
    local it = browse_items[i]
    local focused = (i == browse_sel)

    -- Card
    if focused then
      col(acc, 0.20)
      love.graphics.rectangle("fill", x, y, cw, ch, 4, 4)
      col(acc, 0.95)
      love.graphics.setLineWidth(2)
    else
      col({0.030, 0.026, 0.040}, 0.9)
      love.graphics.rectangle("fill", x, y, cw, ch, 4, 4)
      col(acc, 0.35)
      love.graphics.setLineWidth(1)
    end
    love.graphics.rectangle("line", x + 0.5, y + 0.5, cw - 1, ch - 1, 4, 4)
    love.graphics.setLineWidth(1)

    -- Cover
    local cover_area_h = ch - 34
    if it.cover then
      local iw, ih = it.cover:getDimensions()
      local sc = math.min((cw - 12) / iw, (cover_area_h - 8) / ih)
      local dw, dh = iw * sc, ih * sc
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(it.cover,
        x + (cw - dw) / 2, y + 4 + (cover_area_h - dh) / 2, 0, sc, sc)
      love.graphics.setColor(1, 1, 1, 1)
    else
      -- Placeholder
      local cx = x + cw / 2
      local cy = y + cover_area_h / 2
      col(acc, 0.25)
      love.graphics.setLineWidth(2)
      love.graphics.rectangle("line", cx - 22, cy - 30, 44, 60, 3, 3)
      love.graphics.line(cx - 22, cy - 10, cx + 22, cy - 10)
      love.graphics.line(cx - 15, cy + 5, cx + 15, cy + 5)
      love.graphics.line(cx - 15, cy + 15, cx + 8, cy + 15)
      love.graphics.setLineWidth(1)
    end

    -- Name
    love.graphics.setFont(A.font(A.FONT_BODY, 9))
    col(focused and {1,1,1} or State.theme.text, 1)
    local name = it.name
    if #name > 22 then name = name:sub(1, 21) .. "…" end
    love.graphics.printf(name, x + 4, y + ch - 28, cw - 8, "center")

    -- Kind badge
    love.graphics.setFont(A.font(A.FONT_MONO, 8))
    col(acc, 0.85)
    love.graphics.printf("[" .. it.kind .. "]", x + 4, y + ch - 14, cw - 8, "center")
  end
  love.graphics.setScissor()

  -- Scrollbar
  if #browse_items > per_page then
    local track_h = vp_h - 8
    local thumb_h = math.max(24, track_h * (per_page / #browse_items))
    local denom = math.max(1, #browse_items - per_page)
    local thumb_y = vp_y + 4 + (track_h - thumb_h) * (browse_scroll / denom)
    col(acc, 0.55)
    love.graphics.rectangle("fill", W - 6, thumb_y, 3, thumb_h, 1, 1)
  end
end

-- ============================================================
--  Drawing: reader mode
-- ============================================================
local function draw_header_reader()
  local x, y = 20, Frame.TOP_H + 4
  local w = W - 40
  local h = 34
  col({0.030, 0.020, 0.045}, 0.95)
  love.graphics.rectangle("fill", x, y, w, h, 4, 4)
  col(acc, 0.9)
  love.graphics.setLineWidth(1.4)
  love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, 4, 4)
  love.graphics.setLineWidth(1)

  love.graphics.setFont(A.font(A.FONT_TITLE, 13))
  col(acc, 1)
  love.graphics.print("GD-X LIBRARY", x + 12, y + 4)

  love.graphics.setFont(A.font(A.FONT_BODY_BOLD, 12))
  col({1,1,1}, 1)
  local title = basename(doc_path or "?")
  if #title > 42 then title = title:sub(1, 41) .. "…" end
  love.graphics.print(title, x + 140, y + 4)

  love.graphics.setFont(A.font(A.FONT_MONO, 11))
  col(acc, 0.9)
  love.graphics.printf("page " .. page .. " / " .. total,
    x, y + 5, w - 12, "right")
end

local function draw_pdf_or_cbz()
  local img = cache_img[page]
  if not img then
    col(State.theme.text_dim, 0.8)
    love.graphics.setFont(A.font(A.FONT_BODY, 12))
    local msg = (doc.kind == "pdf") and "rendering..." or "(no image)"
    love.graphics.printf(msg, 0, H/2, W, "center")
    return
  end
  local iw, ih = img:getDimensions()
  local avail_w = W - 40
  local avail_h = H - Frame.TOP_H - Frame.BOTTOM_H - 50
  local base_scale = math.min(avail_w / iw, avail_h / ih)
  local sc = base_scale * zoom
  local dw, dh = iw * sc, ih * sc
  local cx = W / 2 + pan_x
  local cy = Frame.TOP_H + 42 + (avail_h / 2) + pan_y
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(img, cx - dw/2, cy - dh/2, 0, sc, sc)
  love.graphics.setColor(1, 1, 1, 1)
end

local function draw_epub()
  local blocks = epub_blocks or {}
  local x = 30
  local y_top = Frame.TOP_H + 48 + (-scroll)
  local w = W - 60
  local y = y_top
  local th = State.theme
  local theme = THEMES[reader_theme] or THEMES.dark
  local theme = THEMES[reader_theme] or THEMES.dark

  local function font_for(kind)
    if kind == "h1" then return A.font(A.FONT_TITLE, 20), 28
    elseif kind == "h2" then return A.font(A.FONT_TITLE, 17), 24
    elseif kind == "h3" then return A.font(A.FONT_TITLE, 14), 20
    elseif kind == "h4" then return A.font(A.FONT_BODY_BOLD, 13), 18
    elseif kind == "pre" then return A.font(A.FONT_MONO, 11), 14
    elseif kind == "li" then return A.font(A.FONT_BODY, 12), 18
    else return A.font(A.FONT_BODY, 12), 18 end
  end

  love.graphics.setScissor(0, Frame.TOP_H + 42, W, H - Frame.TOP_H - Frame.BOTTOM_H - 46)
  for _, blk in ipairs(blocks) do
    if blk.kind == "hr" then
      col(acc, 0.5)
      love.graphics.rectangle("fill", x, y + 6, w, 1)
      y = y + 14
    elseif blk.kind == "img" then
      y = y + 8
      col(th.text_dim, 0.8)
      love.graphics.setFont(A.font(A.FONT_MONO, 10))
      love.graphics.print("[image] " .. (blk.alt or blk.src or ""), x, y)
      y = y + 14
    else
      local f, lh = font_for(blk.kind)
      love.graphics.setFont(f)
      local line = {}
      for _, r in ipairs(blk.runs) do line[#line+1] = r.text end
      local txt = table.concat(line)
      if txt ~= "" then
        if blk.kind == "li" then
          col(acc, 1)
          love.graphics.print("•", x, y)
          txt = "  " .. txt
        end
        col(theme.text, 1)
        love.graphics.printf(txt, x, y, w, "left")
        y = y + lh * (1 + math.floor(f:getWidth(txt) / w))
      end
    end
    if y > H + 200 then break end
  end
  love.graphics.setScissor()
end

-- ============================================================
--  Main draw
-- ============================================================
local function draw_toc_overlay()
  if not toc_open then return end
  -- Dim
  love.graphics.setColor(0, 0, 0, 0.80)
  love.graphics.rectangle("fill", 0, 0, W, H)

  local x = 40
  local y = 40
  local w = W - 80
  local h = H - 80
  col({0.030, 0.020, 0.045}, 0.98)
  love.graphics.rectangle("fill", x, y, w, h, 5, 5)
  col(acc, 0.9)
  love.graphics.setLineWidth(1.6)
  love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, 5, 5)
  love.graphics.setLineWidth(1)
  D.corner_ticks(x + 8, y + 8, w - 16, h - 16, 12, acc, 0.9)

  love.graphics.setFont(A.font(A.FONT_TITLE, 16))
  col(acc, 1)
  love.graphics.print("TABLE OF CONTENTS", x + 20, y + 14)

  col(acc, 0.3)
  love.graphics.rectangle("fill", x + 20, y + 36, w - 40, 1)

  love.graphics.setFont(A.font(A.FONT_BODY, 12))
  local row_h = 22
  local vis = math.floor((h - 60) / row_h)
  local first = math.max(1, toc_sel - vis + 3)

  for i = first, math.min(#epub_toc, first + vis - 1) do
    local item = epub_toc[i]
    local ry = y + 46 + (i - first) * row_h
    local focused = (i == toc_sel)
    if focused then
      col(acc, 0.20)
      love.graphics.rectangle("fill", x + 14, ry - 2, w - 28, row_h - 2, 3, 3)
      col(acc, 0.9)
      love.graphics.rectangle("line", x + 14.5, ry - 1.5, w - 29, row_h - 3, 3, 3)
    end
    col(focused and {1, 1, 1} or State.theme.text, 1)
    local title = item.title or "?"
    if #title > 50 then title = title:sub(1, 49) .. "." end
    love.graphics.print(title, x + 24, ry + 2)
  end

  -- Scrollbar
  if #epub_toc > vis then
    local track_h = h - 60
    local thumb_h = math.max(20, track_h * (vis / #epub_toc))
    local max_s = math.max(1, #epub_toc - vis)
    local start = math.max(0, toc_sel - vis + 2)
    local thumb_y = y + 46 + (track_h - thumb_h) * (start / max_s)
    col(acc, 0.6)
    love.graphics.rectangle("fill", x + w - 10, thumb_y, 3, thumb_h, 1, 1)
  end
end

local function draw_toc_overlay()
  if not toc_open then return end
  -- Dim
  love.graphics.setColor(0, 0, 0, 0.80)
  love.graphics.rectangle("fill", 0, 0, W, H)

  local x = 40
  local y = 40
  local w = W - 80
  local h = H - 80
  col({0.030, 0.020, 0.045}, 0.98)
  love.graphics.rectangle("fill", x, y, w, h, 5, 5)
  col(acc, 0.9)
  love.graphics.setLineWidth(1.6)
  love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, 5, 5)
  love.graphics.setLineWidth(1)
  D.corner_ticks(x + 8, y + 8, w - 16, h - 16, 12, acc, 0.9)

  love.graphics.setFont(A.font(A.FONT_TITLE, 16))
  col(acc, 1)
  love.graphics.print("TABLE OF CONTENTS", x + 20, y + 14)

  col(acc, 0.3)
  love.graphics.rectangle("fill", x + 20, y + 36, w - 40, 1)

  love.graphics.setFont(A.font(A.FONT_BODY, 12))
  local row_h = 22
  local vis = math.floor((h - 60) / row_h)
  local first = math.max(1, toc_sel - vis + 3)

  for i = first, math.min(#epub_toc, first + vis - 1) do
    local item = epub_toc[i]
    local ry = y + 46 + (i - first) * row_h
    local focused = (i == toc_sel)
    if focused then
      col(acc, 0.20)
      love.graphics.rectangle("fill", x + 14, ry - 2, w - 28, row_h - 2, 3, 3)
      col(acc, 0.9)
      love.graphics.rectangle("line", x + 14.5, ry - 1.5, w - 29, row_h - 3, 3, 3)
    end
    col(focused and {1, 1, 1} or State.theme.text, 1)
    local title = item.title or "?"
    if #title > 50 then title = title:sub(1, 49) .. "." end
    love.graphics.print(title, x + 24, ry + 2)
  end

  -- Scrollbar
  if #epub_toc > vis then
    local track_h = h - 60
    local thumb_h = math.max(20, track_h * (vis / #epub_toc))
    local max_s = math.max(1, #epub_toc - vis)
    local start = math.max(0, toc_sel - vis + 2)
    local thumb_y = y + 46 + (track_h - thumb_h) * (start / max_s)
    col(acc, 0.6)
    love.graphics.rectangle("fill", x + w - 10, thumb_y, 3, thumb_h, 1, 1)
  end
end

function S.draw()
  D.bg()
  col(acc, 0.06)
  for gy = Frame.TOP_H, H - Frame.BOTTOM_H, 18 do
    for gx = 0, W, 18 do love.graphics.rectangle("fill", gx, gy, 1, 1) end
  end

  if mode == "browse" then
    draw_browse()
  else
    draw_header_reader()
    if doc then
      if doc.kind == "pdf" or doc.kind == "cbz" then draw_pdf_or_cbz()
      elseif doc.kind == "epub" then draw_epub() end
    end
    if status ~= "" then
      col(acc, 0.9)
      love.graphics.setFont(A.font(A.FONT_MONO, 10))
      love.graphics.printf(status, 0, H - Frame.BOTTOM_H - 18, W, "center")
    end
  end

  local hints
  if mode == "browse" then
    hints = {
      { key = "up",   label = "Move" },
      { key = "a",    label = "Open" },
      { key = "b",    label = "Back" },
    }
  else
    hints = {
      { key = "l1",  label = "Prev" },
      { key = "r1",  label = "Next" },
      { key = "y",   label = "TOC" },
      { key = "x",   label = "Theme" },
      { key = "b",   label = "Exit" },
    }
  end

  Frame.draw_top("FGD", "grid")
  Frame.draw_bottom(hints)
  Modal.draw()
  draw_toc_overlay()
  D.scanlines(W, H, 0.06)
end

return S
