-- screens/filex_home.lua -- File Xplorer landing: "Cockpit" dashboard.
--
-- Design principles:
--   * Volumes are the hero (up to 4 cards, always visible).
--   * Each card shows its LAST VISITED PATH (so you resume where you left).
--   * Recent files fill the middle (live list).
--   * Quick actions are pills at the bottom.
--   * Navigation is 3 rows: storage / recent / quick.

local A     = require("core.assets")
local State = require("core.state")
local Input = require("core.input_map")
local Frame = require("ui.frame")
local D     = require("ui.draw")
local sh    = require("core.sh")
local FS    = require("services.fs")
local FI    = require("ui.file_icons")
local Notify= require("ui.notify")
local BM    = require("services.bookmarks")

local S = {}
local W, H = 640, 480

-- Palette
local AMB = {0.94, 0.66, 0.35}
local CYA = {0.48, 0.80, 0.90}
local PUR = {0.70, 0.55, 0.92}
local GRN = {0.55, 0.85, 0.45}
local RED = {0.95, 0.30, 0.25}
local GRY = {0.45, 0.45, 0.50}

local function col(c, a) love.graphics.setColor(c[1], c[2], c[3], a or 1) end

-- Layout constants
local PAD = 8
local GAP = 6

local Y_STORAGE   = Frame.TOP_H + PAD
local H_STORAGE   = 110

local Y_RECENT_H  = Y_STORAGE + H_STORAGE + GAP
local H_RECENT_H  = 22

local Y_RECENT    = Y_RECENT_H + H_RECENT_H
local H_RECENT    = 200

local Y_QUICK     = Y_RECENT + H_RECENT + GAP
local H_QUICK     = 36

-- Helpers
local function human_gb(n)
  if not n or n <= 0 then return "0 G" end
  local g = n / (1024 * 1024 * 1024)
  if g >= 100 then return string.format("%.0fG", g) end
  if g >= 10 then return string.format("%.1fG", g) end
  return string.format("%.2fG", g)
end

local function bar_colour(pct)
  if pct < 0.25 then return GRN end
  if pct < 0.60 then return {0.95, 0.85, 0.20} end
  if pct < 0.80 then return {0.95, 0.55, 0.20} end
  return RED
end

local function relative_time(mt)
  if not mt or mt == 0 then return "" end
  local diff = os.time() - mt
  if diff < 0 then return "now" end
  if diff < 60 then return diff .. "s" end
  if diff < 3600 then return math.floor(diff / 60) .. " min" end
  if diff < 86400 then return math.floor(diff / 3600) .. " h" end
  if diff < 86400 * 7 then return math.floor(diff / 86400) .. " d" end
  return os.date("%d/%m", mt)
end

local function df_for(path)
  local out = sh.read("df -kP " .. sh.shq(path) .. " 2>/dev/null")
  if not out then return nil end
  local line = out:match("[^\n]+\n([^\n]+)")
  if not line then return nil end
  local t, u, f = line:match("%s(%d+)%s+(%d+)%s+(%d+)")
  if not t then return nil end
  return tonumber(t) * 1024, tonumber(u) * 1024, tonumber(f) * 1024
end

local function count_apps(path)
  if not FS.is_dir(path) then return 0 end
  local h = io.popen("ls -1d " .. sh.shq(path) .. "/*/ 2>/dev/null | wc -l")
  if not h then return 0 end
  local n = tonumber(h:read("*a") or "0") or 0
  h:close()
  return n
end

-- Truncate showing the HEAD (end...) -- good for filenames
local function trunc_head(font, s, maxw)
  if not s then return "" end
  if font:getWidth(s) <= maxw then return s end
  local out = s
  while #out > 1 and font:getWidth(out .. "…") > maxw do
    out = out:sub(1, -2)
  end
  return out .. "…"
end

-- Truncate showing the TAIL (...end) -- good for paths
local function trunc_tail(font, s, maxw)
  if not s then return "" end
  if font:getWidth(s) <= maxw then return s end
  local out = s
  while #out > 1 and font:getWidth("…" .. out) > maxw do
    out = out:sub(2)
  end
  return "…" .. out
end

local function strip_mount(full, mnt)
  if not full or not mnt then return full end
  if full == mnt then return "/" end
  if full:sub(1, #mnt + 1) == mnt .. "/" then
    local r = full:sub(#mnt + 2)
    if r == "" then return "/" end
    return r
  end
  return full
end

-- ============================================================
--  Data model
-- ============================================================
local STORAGES = {}
local RECENT   = {}
local QUICK    = {}
local MUOS_TOTAL = 0
local MUOS_ROOT  = nil

local function last_path_for(key)
  local ok, Store = pcall(require, "core.settings_store")
  if not ok or not Store then return nil end
  local v = Store.get("paths", "last_" .. key)
  if v and v ~= "" and FS.is_dir(v) then return v end
  return nil
end

local function rebuild_data()
  STORAGES = {}

  local function try_add(label, key, path, kind, colour)
    if not FS.is_dir(path) then return end
    local total, used, free = df_for(path)
    if not total or total <= 0 then return end
    STORAGES[#STORAGES + 1] = {
      label = label, key = key, path = path, kind = kind, colour = colour,
      total = total, used = used, free = free,
      last_path = last_path_for(key),
    }
  end

  try_add("SD1",  "SD1",  "/mnt/mmc",    "sd",   AMB)
  try_add("SD2",  "SD2",  "/mnt/sdcard", "sd",   CYA)
  try_add("USB",  "USB",  "/mnt/usb",    "usb",  PUR)
  try_add("ROOT", "ROOT", "/",           "root", GRN)

  -- Recent files: reverse chronological, deduped, up to 10 shown
  RECENT = {}
  local raw = BM.recent()
  local seen = {}
  for _, p in ipairs(raw) do
    if not seen[p] and sh.exists(p) then
      seen[p] = true
      local name = p:match("([^/]+)$") or p
      local parent = p:match("^(.*)/[^/]+$") or "/"
      local is_dir = FS.is_dir(p)
      local mt = 0
      if FS.stat then
        local st = FS.stat(p)
        if st and st.mtime then mt = st.mtime end
      end
      RECENT[#RECENT + 1] = {
        path = p, name = name, parent = parent,
        is_dir = is_dir, mtime = mt,
      }
      if #RECENT >= 10 then break end
    end
  end

  -- Quick pills
  local n_bm = #BM.bookmarks()
  local n_fv = #BM.favorites()

  -- muOS apps
  local n1 = count_apps("/mnt/mmc/MUOS/application")
  local n2 = count_apps("/mnt/sdcard/MUOS/application")
  MUOS_TOTAL = n1 + n2
  if n1 > 0 then MUOS_ROOT = "/mnt/mmc/MUOS/application"
  elseif n2 > 0 then MUOS_ROOT = "/mnt/sdcard/MUOS/application"
  else MUOS_ROOT = nil end

  QUICK = {
    { key = "home",      label = "Home",      colour = CYA },
    { key = "bookmarks", label = "Bookmarks", colour = AMB, badge = n_bm },
    { key = "favorites", label = "Favorites", colour = {0.95, 0.80, 0.30}, badge = n_fv },
    { key = "muos",      label = "muOS Apps", colour = GRN, badge = MUOS_TOTAL },
  }
end

-- ============================================================
--  State
-- ============================================================
local focus = {
  section     = "storage",   -- "storage" | "recent" | "quick"
  storage_idx = 1,
  recent_idx  = 1,
  quick_idx   = 1,
}
local sub_view   = nil
local sub_items  = {}
local sub_sel    = 1
local sub_scroll = 0
local t_global   = 0

local function clamp_focus()
  if #STORAGES == 0 then focus.storage_idx = 1
  elseif focus.storage_idx > #STORAGES then focus.storage_idx = #STORAGES
  elseif focus.storage_idx < 1 then focus.storage_idx = 1 end

  if #RECENT == 0 then focus.recent_idx = 1
  elseif focus.recent_idx > #RECENT then focus.recent_idx = #RECENT
  elseif focus.recent_idx < 1 then focus.recent_idx = 1 end

  if #QUICK == 0 then focus.quick_idx = 1
  elseif focus.quick_idx > #QUICK then focus.quick_idx = #QUICK
  elseif focus.quick_idx < 1 then focus.quick_idx = 1 end
end

-- ============================================================
--  Lifecycle
-- ============================================================
function S.enter()
  t_global = 0
  sub_view = nil
  sub_items = {}
  rebuild_data()
  if State.filex_focus then
    focus.section     = State.filex_focus.section or "storage"
    focus.storage_idx = State.filex_focus.storage_idx or 1
    focus.recent_idx  = State.filex_focus.recent_idx or 1
    focus.quick_idx   = State.filex_focus.quick_idx or 1
  end
  clamp_focus()
end

function S.leave()
  State.filex_focus = {
    section     = focus.section,
    storage_idx = focus.storage_idx,
    recent_idx  = focus.recent_idx,
    quick_idx   = focus.quick_idx,
  }
end

function S.update(dt)
  t_global = t_global + dt
  if State.filex_dirty then
    State.filex_dirty = nil
    rebuild_data()
    clamp_focus()
  end
end

-- ============================================================
--  Navigation
-- ============================================================
local function move_left_right(d)
  if focus.section == "storage" then
    local n = #STORAGES
    if n == 0 then return end
    focus.storage_idx = focus.storage_idx + d
    if focus.storage_idx < 1 then focus.storage_idx = n end
    if focus.storage_idx > n then focus.storage_idx = 1 end
  elseif focus.section == "quick" then
    local n = #QUICK
    if n == 0 then return end
    focus.quick_idx = focus.quick_idx + d
    if focus.quick_idx < 1 then focus.quick_idx = n end
    if focus.quick_idx > n then focus.quick_idx = 1 end
  end
end

local function move_up_down(d)
  if focus.section == "storage" then
    if d > 0 then
      focus.section = (#RECENT > 0) and "recent" or "quick"
    else
      focus.section = "quick"
    end
  elseif focus.section == "recent" then
    if d > 0 then
      if focus.recent_idx < #RECENT then
        focus.recent_idx = focus.recent_idx + 1
      else
        focus.section = "quick"
      end
    else
      if focus.recent_idx > 1 then
        focus.recent_idx = focus.recent_idx - 1
      else
        focus.section = "storage"
      end
    end
  elseif focus.section == "quick" then
    if d > 0 then
      focus.section = "storage"
    else
      if #RECENT > 0 then
        focus.section = "recent"
        focus.recent_idx = #RECENT
      else
        focus.section = "storage"
      end
    end
  end
  clamp_focus()
end

-- ============================================================
--  Sub-views
-- ============================================================
local function open_sub(view)
  local list
  if view == "bookmarks" then list = BM.bookmarks()
  elseif view == "favorites" then list = BM.favorites()
  else list = {} end
  sub_items = {}
  for _, p in ipairs(list) do
    if sh.exists(p) then
      sub_items[#sub_items + 1] = {
        path   = p,
        name   = p:match("([^/]+)$") or p,
        parent = p:match("^(.*)/[^/]+$") or "/",
        is_dir = FS.is_dir(p),
      }
    end
  end
  sub_view = view
  sub_sel = 1
  sub_scroll = 0
end

local function close_sub()
  sub_view = nil
  sub_items = {}
end

-- ============================================================
--  Activation
-- ============================================================
local function open_path_in_grid(p)
  if not p or p == "" then return end
  if not FS.is_dir(p) then
    Notify.show("warning", "not a directory: " .. p)
    return
  end
  State.filex_cwd = p
  State.go("grid")
end

local function open_file_entry(r)
  if not r then return end
  if r.is_dir then open_path_in_grid(r.path); return end

  local ext = FS.ext_of(r.name)
  local kind = FS.classify({ name = r.name, is_dir = false })

  if kind == "image" then
    State.selected_path = r.path
    State.selected_entry = r
    State.go("image_viewer")
  elseif kind == "text" and ext ~= "html" and ext ~= "htm" then
    State.selected_path = r.path
    State.selected_entry = r
    State.go("editor")
  elseif ext == "pdf" then
    local has = false
    do
      local ok, DE = pcall(require, "services.doc_engine")
      if ok and DE then
        if DE.pdf_available then has = DE.pdf_available() == true
        elseif DE.tools then has = DE.tools.pymupdf == true end
      end
    end
    if has then
      State.library_path = r.path
      State.go("gdx_library")
    else
      Notify.show("warning", "PDF support not installed")
    end
  elseif ext == "epub" or ext == "cbz" or ext == "cbr" or ext == "cb7" then
    State.library_path = r.path
    State.go("gdx_library")
  elseif kind == "audio" or kind == "video" then
    State.chou_henka_path = r.path
    State.go("chou_henka")
  else
    Notify.show("info", "no handler for " .. (ext ~= "" and ext or kind))
  end
end

local function activate_storage()
  local s = STORAGES[focus.storage_idx]
  if not s then return end
  open_path_in_grid(s.last_path or s.path)
end

local function activate_recent()
  open_file_entry(RECENT[focus.recent_idx])
end

local function activate_quick()
  local q = QUICK[focus.quick_idx]
  if not q then return end
  if q.key == "home" then
    open_path_in_grid(os.getenv("HOME") or "/tmp")
  elseif q.key == "bookmarks" then
    open_sub("bookmarks")
  elseif q.key == "favorites" then
    open_sub("favorites")
  elseif q.key == "muos" then
    if MUOS_ROOT then
      State.muos_apps_root = MUOS_ROOT
      State.go("muos_apps")
    else
      Notify.show("warning", "no muOS apps found")
    end
  end
end

local function activate()
  if sub_view then
    local it = sub_items[sub_sel]
    if it then open_file_entry(it) end
    return
  end
  if     focus.section == "storage" then activate_storage()
  elseif focus.section == "recent"  then activate_recent()
  elseif focus.section == "quick"   then activate_quick() end
end

local function remove_current_sub()
  if not sub_view then return end
  local it = sub_items[sub_sel]
  if not it then return end
  if sub_view == "bookmarks" then
    BM.remove_bookmark(it.path)
  elseif sub_view == "favorites" then
    BM.toggle_favorite(it.path)
  end
  open_sub(sub_view)
  if sub_sel > #sub_items then sub_sel = math.max(1, #sub_items) end
end

-- ============================================================
--  Input
-- ============================================================
local function back()
  if sub_view then close_sub(); return end
  State.go("mainmenu")
end

function S.pad(b)
  if sub_view then
    if     b == Input.UP   then sub_sel = math.max(1, sub_sel - 1)
    elseif b == Input.DOWN then sub_sel = math.min(#sub_items, sub_sel + 1)
    elseif b == Input.L1   then sub_sel = math.max(1, sub_sel - 6)
    elseif b == Input.R1   then sub_sel = math.min(#sub_items, sub_sel + 6)
    elseif b == Input.A    then activate()
    elseif b == Input.X    then remove_current_sub()
    elseif b == Input.B or b == Input.SELECT then close_sub() end
    return
  end

  if     b == Input.UP    then move_up_down(-1)
  elseif b == Input.DOWN  then move_up_down( 1)
  elseif b == Input.LEFT  then move_left_right(-1)
  elseif b == Input.RIGHT then move_left_right( 1)
  elseif b == Input.A     then activate()
  elseif b == Input.B or b == Input.SELECT then back() end
end

function S.hat(d)
  if sub_view then
    if     d == "up"   then sub_sel = math.max(1, sub_sel - 1)
    elseif d == "down" then sub_sel = math.min(#sub_items, sub_sel + 1) end
    return
  end
  if     d == "up"    then move_up_down(-1)
  elseif d == "down"  then move_up_down( 1)
  elseif d == "left"  then move_left_right(-1)
  elseif d == "right" then move_left_right( 1) end
end

function S.key(k)
  if sub_view then
    if     k == "up"   then sub_sel = math.max(1, sub_sel - 1)
    elseif k == "down" then sub_sel = math.min(#sub_items, sub_sel + 1)
    elseif k == "return" or k == "space" then activate()
    elseif k == "x"    then remove_current_sub()
    elseif k == "escape" or k == "backspace" then close_sub() end
    return
  end
  if     k == "up"    then move_up_down(-1)
  elseif k == "down"  then move_up_down( 1)
  elseif k == "left"  then move_left_right(-1)
  elseif k == "right" then move_left_right( 1)
  elseif k == "return" or k == "space" then activate()
  elseif k == "escape" or k == "backspace" then back() end
end

-- ============================================================
--  Icons
-- ============================================================
local function draw_storage_glyph(kind, cx, cy, r, c, a)
  col(c, a or 1)
  love.graphics.setLineWidth(1.6)
  if kind == "sd" then
    local cut = r * 0.28
    love.graphics.polygon("line",
      cx - r*0.55, cy - r*0.75,
      cx + r*0.55 - cut, cy - r*0.75,
      cx + r*0.55, cy - r*0.75 + cut,
      cx + r*0.55, cy + r*0.75,
      cx - r*0.55, cy + r*0.75)
    love.graphics.line(cx - r*0.55, cy - r*0.35, cx + r*0.55, cy - r*0.35)
    love.graphics.rectangle("fill",
      cx - r*0.30, cy + r*0.10, r*0.6, r*0.35, 1, 1)
  elseif kind == "usb" then
    love.graphics.rectangle("line", cx - r*0.30, cy - r*0.75, r*0.6, r*0.6, 1, 1)
    love.graphics.rectangle("line", cx - r*0.55, cy - r*0.15, r*1.1, r*0.85, 1, 1)
    love.graphics.rectangle("fill", cx - r*0.08, cy + r*0.30, r*0.16, r*0.40, 1, 1)
  elseif kind == "root" then
    love.graphics.circle("line", cx, cy, r*0.80)
    love.graphics.line(cx, cy - r*0.80, cx, cy + r*0.80)
    love.graphics.line(cx - r*0.80, cy, cx + r*0.80, cy)
    love.graphics.circle("fill", cx, cy, r*0.22)
  end
  love.graphics.setLineWidth(1)
end

-- ============================================================
--  Storage card
-- ============================================================
local function draw_storage_card(x, y, w, h, s, focused)
  local acc = s.colour

  if focused then
    col({acc[1]*0.16, acc[2]*0.16, acc[3]*0.16}, 0.98)
    love.graphics.rectangle("fill", x, y, w, h, 5, 5)
    col(acc, 0.95)
    love.graphics.setLineWidth(1.8)
    love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, 5, 5)
    love.graphics.setLineWidth(1)
    D.corner_ticks(x + 8, y + 8, w - 16, h - 16, 12, acc, 0.95)
    local pulse = 0.6 + 0.4 * math.sin(t_global * 3)
    col(acc, 0.7 + 0.3 * pulse)
    love.graphics.rectangle("fill", x, y + 12, 3, h - 24)
    D.glow(x + w/2, y + h/2, w * 0.85, acc, 0.35)
  else
    col({0.024, 0.022, 0.030}, 0.92)
    love.graphics.rectangle("fill", x, y, w, h, 5, 5)
    col(acc, 0.28)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, 5, 5)
  end

  local icx, icy, ir = x + 24, y + 24, 14
  col({acc[1]*0.22, acc[2]*0.22, acc[3]*0.22}, 0.95)
  love.graphics.circle("fill", icx, icy, ir)
  col(acc, focused and 0.95 or 0.55)
  love.graphics.setLineWidth(focused and 1.5 or 1)
  love.graphics.circle("line", icx, icy, ir)
  love.graphics.setLineWidth(1)
  draw_storage_glyph(s.kind, icx, icy, ir * 0.6, acc, focused and 1 or 0.75)

  love.graphics.setFont(A.font(A.FONT_BODY_BOLD, focused and 15 or 14))
  col(focused and {1,1,1} or State.theme.text, 1)
  love.graphics.print(s.label, x + 46, y + 10)

  love.graphics.setFont(A.font(A.FONT_MONO, 8))
  col(State.theme.text_dim, 0.75)
  love.graphics.print(s.path, x + 46, y + 32)

  local bar_x, bar_y = x + 10, y + 52
  local bar_w, bar_h = w - 20, 6
  local pct = (s.total > 0) and (s.used / s.total) or 0
  local bcol = bar_colour(pct)
  col({0.06, 0.07, 0.09}, 1)
  love.graphics.rectangle("fill", bar_x, bar_y, bar_w, bar_h, 3, 3)
  col(bcol, 0.95)
  love.graphics.rectangle("fill", bar_x + 1, bar_y + 1,
    (bar_w - 2) * pct, bar_h - 2, 2, 2)
  col(bcol, 0.45)
  love.graphics.rectangle("line", bar_x + 0.5, bar_y + 0.5,
    bar_w - 1, bar_h - 1, 3, 3)

  love.graphics.setFont(A.font(A.FONT_MONO, 10))
  col(bcol, 1)
  love.graphics.print(human_gb(s.free) .. " free", x + 10, y + 64)
  love.graphics.setFont(A.font(A.FONT_MONO, 9))
  col(State.theme.text_dim, 0.8)
  love.graphics.printf(string.format("%d%%  of %s",
    math.floor(pct * 100 + 0.5), human_gb(s.total)),
    x, y + 66, w - 10, "right")

  love.graphics.setFont(A.font(A.FONT_MONO, 9))
  if s.last_path and s.last_path ~= "" then
    local lp = strip_mount(s.last_path, s.path)
    col(State.theme.text_dim, 0.55)
    love.graphics.print(">", x + 10, y + 88)
    col(acc, focused and 0.95 or 0.6)
    local f = love.graphics.getFont()
    love.graphics.print(trunc_tail(f, lp, w - 26), x + 20, y + 88)
  else
    col(State.theme.text_dim, 0.35)
    love.graphics.print("> (root)", x + 10, y + 88)
  end
end

-- ============================================================
--  Recent list
-- ============================================================
local function draw_recent_header(y)
  love.graphics.setFont(A.font(A.FONT_MONO, 10))
  col(CYA, 0.9)
  love.graphics.print("RECENT FILES", PAD + 4, y + 4)
  col(CYA, 0.3)
  love.graphics.rectangle("fill", PAD + 4, y + 18, W - 2 * PAD - 8, 1)
  love.graphics.setFont(A.font(A.FONT_MONO, 9))
  col(State.theme.text_dim, 0.7)
  love.graphics.printf(#RECENT .. " items", 0, y + 4, W - PAD - 4, "right")
end

local function draw_recent_item(x, y, w, r, focused)
  local acc = CYA
  if focused then
    col({acc[1]*0.16, acc[2]*0.16, acc[3]*0.16}, 0.95)
    love.graphics.rectangle("fill", x, y, w, 22, 3, 3)
    col(acc, 0.9)
    love.graphics.setLineWidth(1.2)
    love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, 21, 3, 3)
    love.graphics.setLineWidth(1)
    col(acc, 1)
    love.graphics.rectangle("fill", x, y + 4, 3, 14)
  end

  FI.draw(FI.get(r, r.parent), x + 16, y + 11, 7, focused and 1 or 0.72)

  local f = A.font(focused and A.FONT_BODY_BOLD or A.FONT_BODY, 11)
  love.graphics.setFont(f)
  col(focused and {1,1,1} or State.theme.text, 1)
  love.graphics.print(trunc_head(f, r.name, w - 130), x + 32, y + 5)

  love.graphics.setFont(A.font(A.FONT_MONO, 9))
  col(State.theme.text_dim, focused and 0.9 or 0.65)
  love.graphics.printf(relative_time(r.mtime), x, y + 6, w - 12, "right")
end

local function draw_recent_empty(y, h)
  love.graphics.setFont(A.font(A.FONT_BODY, 11))
  col(State.theme.text_dim, 0.55)
  love.graphics.printf(
    "No recent files yet.\nOpen something and it will show up here.",
    PAD, y + h/2 - 16, W - 2 * PAD, "center")
end

-- ============================================================
--  Quick pills
-- ============================================================
local function draw_pill(x, y, w, h, q, focused)
  local acc = q.colour
  if focused then
    col({acc[1]*0.20, acc[2]*0.20, acc[3]*0.20}, 0.98)
    love.graphics.rectangle("fill", x, y, w, h, h/2, h/2)
    col(acc, 0.95)
    love.graphics.setLineWidth(1.5)
    love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, h/2, h/2)
    love.graphics.setLineWidth(1)
    local pulse = 0.6 + 0.4 * math.sin(t_global * 4)
    D.glow(x + w/2, y + h/2, w * 0.7, acc, 0.3 + 0.2 * pulse)
  else
    col({0.028, 0.026, 0.032}, 0.9)
    love.graphics.rectangle("fill", x, y, w, h, h/2, h/2)
    col(acc, 0.32)
    love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, h/2, h/2)
  end

  local has_badge = q.badge and q.badge > 0
  local label_x = x
  local label_w = w
  if has_badge then
    label_x = x + 8
    label_w = w - 40
  end

  love.graphics.setFont(A.font(focused and A.FONT_BODY_BOLD or A.FONT_BODY, 12))
  col(focused and {1,1,1} or State.theme.text, 1)
  love.graphics.printf(q.label, label_x, y + h/2 - 7, label_w, "center")

  if has_badge then
    local f = A.font(A.FONT_MONO, 9)
    love.graphics.setFont(f)
    local txt = tostring(q.badge)
    local bw = math.max(20, f:getWidth(txt) + 12)
    col({acc[1]*0.35, acc[2]*0.35, acc[3]*0.35}, 1)
    love.graphics.rectangle("fill", x + w - bw - 6, y + h/2 - 8, bw, 16, 8, 8)
    col({1,1,1}, 1)
    love.graphics.printf(txt, x + w - bw - 6, y + h/2 - 5, bw, "center")
  end
end

-- ============================================================
--  Sub-view (bookmarks / favorites)
-- ============================================================
local function draw_sub_view()
  local title = (sub_view == "bookmarks" and "BOOKMARKS")
             or (sub_view == "favorites" and "FAVORITES")
             or "LIST"
  local acc = (sub_view == "favorites") and {0.95, 0.80, 0.30} or AMB

  love.graphics.setFont(A.font(A.FONT_TITLE, 16))
  col(acc, 1)
  love.graphics.printf(title, 0, Frame.TOP_H + 12, W, "center")

  love.graphics.setFont(A.font(A.FONT_MONO, 9))
  col(acc, 0.7)
  love.graphics.printf(
    #sub_items .. " items  ·  A open  ·  X remove  ·  B back",
    0, Frame.TOP_H + 36, W, "center")

  if #sub_items == 0 then
    love.graphics.setFont(A.font(A.FONT_BODY, 12))
    col(State.theme.text_dim, 0.7)
    love.graphics.printf("empty", 0, H/2, W, "center")
    return
  end

  local row_h = 26
  local vp_y = Frame.TOP_H + 60
  local vp_h = H - Frame.BOTTOM_H - vp_y - 4
  local vis = math.max(1, math.floor(vp_h / row_h))
  local first = math.max(1, sub_sel - math.floor(vis / 2))
  local last = math.min(#sub_items, first + vis - 1)

  love.graphics.setScissor(PAD, vp_y, W - 2 * PAD, vp_h)
  for i = first, last do
    local it = sub_items[i]
    local ry = vp_y + (i - first) * row_h
    local focused = (i == sub_sel)
    if focused then
      col(acc, 0.18)
      love.graphics.rectangle("fill", PAD, ry, W - 2 * PAD, row_h - 2, 3, 3)
      col(acc, 0.9)
      love.graphics.rectangle("line", PAD + 0.5, ry + 0.5,
        W - 2 * PAD - 1, row_h - 3, 3, 3)
      love.graphics.rectangle("fill", PAD, ry + 4, 3, row_h - 10)
    end

    FI.draw(FI.get(it, it.parent), PAD + 16, ry + row_h/2 - 1, 7,
      focused and 1 or 0.75)

    love.graphics.setFont(A.font(A.FONT_BODY_BOLD, 11))
    col(focused and {1,1,1} or State.theme.text, 1)
    local f = love.graphics.getFont()
    love.graphics.print(trunc_head(f, it.name, W - 2 * PAD - 240),
      PAD + 32, ry + 4)

    love.graphics.setFont(A.font(A.FONT_MONO, 8))
    col(State.theme.text_dim, 0.65)
    love.graphics.printf(trunc_tail(f, it.parent, 200),
      PAD, ry + 6, W - 2 * PAD - 12, "right")
  end
  love.graphics.setScissor()
end

-- ============================================================
--  Backdrop
-- ============================================================
local function draw_backdrop()
  D.bg()
  local th = State.theme
  col(th.grid_faint, 0.07)
  for gy = Frame.TOP_H, H - Frame.BOTTOM_H, 16 do
    for gx = 0, W, 16 do
      love.graphics.rectangle("fill", gx, gy, 1, 1)
    end
  end
  D.corner_ticks(PAD, Frame.TOP_H + 4, W - 2 * PAD,
    H - Frame.TOP_H - Frame.BOTTOM_H - 8, 16, CYA, 0.22)
end

-- ============================================================
--  Main draw
-- ============================================================
function S.draw()
  draw_backdrop()

  if sub_view then
    draw_sub_view()
    Frame.draw_top("FGD", "grid")
    Frame.draw_bottom({
      { key = "up", label = "Move" },
      { key = "a",  label = "Open" },
      { key = "x",  label = "Remove" },
      { key = "b",  label = "Back" },
    })
    D.scanlines(W, H, 0.06)
    return
  end

  -- ═══ Storage row ═══
  do
    local n = #STORAGES
    if n > 0 then
      local total_w = W - 2 * PAD - (n - 1) * GAP
      local cw = math.floor(total_w / n)
      for i = 1, n do
        local w_this = (i == n) and (W - PAD - (PAD + (i - 1) * (cw + GAP))) or cw
        local x = PAD + (i - 1) * (cw + GAP)
        local focused = (focus.section == "storage" and focus.storage_idx == i)
        draw_storage_card(x, Y_STORAGE, w_this, H_STORAGE, STORAGES[i], focused)
      end
    end
  end

  -- ═══ Recent header ═══
  draw_recent_header(Y_RECENT_H)

  -- ═══ Recent list ═══
  do
    local vp_y = Y_RECENT
    local vp_h = H_RECENT
    love.graphics.setScissor(PAD, vp_y, W - 2 * PAD, vp_h)

    if #RECENT == 0 then
      draw_recent_empty(vp_y, vp_h)
    else
      local row_h = 24
      local max_visible = math.floor(vp_h / row_h)
      local first = 1
      if focus.section == "recent" and focus.recent_idx > max_visible then
        first = focus.recent_idx - max_visible + 1
      end
      local last = math.min(#RECENT, first + max_visible - 1)
      for i = first, last do
        local y = vp_y + (i - first) * row_h
        local focused = (focus.section == "recent" and focus.recent_idx == i)
        draw_recent_item(PAD, y, W - 2 * PAD, RECENT[i], focused)
      end
    end
    love.graphics.setScissor()
  end

  -- ═══ Quick pills ═══
  do
    local n = #QUICK
    if n > 0 then
      local total_w = W - 2 * PAD - (n - 1) * GAP
      local pw = math.floor(total_w / n)
      for i = 1, n do
        local w_this = (i == n) and (W - PAD - (PAD + (i - 1) * (pw + GAP))) or pw
        local x = PAD + (i - 1) * (pw + GAP)
        local focused = (focus.section == "quick" and focus.quick_idx == i)
        draw_pill(x, Y_QUICK, w_this, H_QUICK, QUICK[i], focused)
      end
    end
  end

  -- ═══ Chrome ═══
  Frame.draw_top("FGD", "grid")
  Frame.draw_bottom({
    { key = "up",  label = "Section" },
    { key = "l/r", label = "Move" },
    { key = "a",   label = "Open" },
    { key = "b",   label = "Back" },
  })
  D.scanlines(W, H, 0.06)
  D.vignette(W, H, 0.55)
end

return S
