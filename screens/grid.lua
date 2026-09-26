-- screens/grid.lua -- File-GD X file manager, redesigned.
-- 4 views (list, grid, compact, details), preview pane (R2),
-- breadcrumb path bar, working archive/checksum/symlink/batch-rename,
-- filter cycle in context menu, dual pane.
local A     = require("core.assets")
local State = require("core.state")
local Input = require("core.input_map")
local Frame = require("ui.frame")
local D     = require("ui.draw")
local FI    = require("ui.file_icons")
local CM    = require("ui.context_menu")
local FS    = require("services.fs")
local Store = require("core.settings_store")
local Notify= require("ui.notify")
local KB    = require("ui.keyboard")
local Modal = require("ui.modal")
local CB    = require("core.clipboard")
local sh    = require("core.sh")
local Ops   = require("services.operations")
local Archive = require("services.archive")
local CS    = require("services.checksum")
local Prop  = require("ui.properties")
local ExtImg= require("core.external_image")

local S = {}
local W, H = 640, 480

local PAD_L, PAD_R = 8, 8
local GAP = 6

local VIEWS = { "list", "grid", "compact", "details" }
local FILTERS = { "all", "dirs", "files", "image", "audio", "video", "text", "archive", "rom" }
local SORT_KEYS = { "name", "size", "date", "type" }

local function col(c, a) love.graphics.setColor(c[1], c[2], c[3], a or 1) end

-- ============================================================
--  Pane
-- ============================================================
local function make_pane(cwd)
  return {
    cwd = cwd,
    filtered = {},
    sel = 1,
    scroll_row = 0,     -- first visible row index (0-based)
    page = 1,
    filter = "all",
    sort_key = "name",
    dirs_first = true,
    sort_asc = true,
    view = "list",
    marks = {},
    error = nil,
    total_size = 0,
  }
end

S.panes   = { make_pane(os.getenv("HOME") or "/tmp"), make_pane("/") }
S.active  = 1
S.dual    = false
S.mode    = "list"
S.side_open = 0
S.panel_sel = 1
S.t_enter = 0
S.preview = false
S.preview_cache = nil
S.preview_path = nil

local function ap() return S.panes[S.active] end
local function op() return S.panes[S.active == 1 and 2 or 1] end

-- ============================================================
--  Helpers
-- ============================================================
local function is_hidden(n)
  if not n or n == "" then return false end
  if n == ".." or n == "." then return false end
  return n:sub(1,1) == "."
end

local function parent_of(path)
  if not path or path == "" or path == "/" then return "/" end
  path = path:gsub("/+$", "")
  if path == "" then return "/" end
  local p = path:match("^(.*)/[^/]+$")
  if not p or p == "" then return "/" end
  return p
end

local function basename(p) return (p or ""):match("([^/]+)$") or p or "" end

local function short_date(mt)
  if not mt or mt == 0 then return "--" end
  return os.date("%m-%d %H:%M", mt)
end

local function truncate(font, s, maxw)
  if not s then return "" end
  if font:getWidth(s) <= maxw then return s end
  local out = s
  while #out > 1 and font:getWidth(out .. ".") > maxw do out = out:sub(1,-2) end
  return out .. "."
end

local function free_space_of(path)
  local out = sh.read("df -kP " .. sh.shq(path) .. " 2>/dev/null")
  if not out then return nil end
  local line = out:match("[^\n]+\n([^\n]+)")
  if not line then return nil end
  local total, used, free = line:match("%s(%d+)%s+(%d+)%s+(%d+)")
  if not total then return nil end
  return tonumber(total)*1024, tonumber(used)*1024, tonumber(free)*1024
end

-- ============================================================
--  Pagination
-- ============================================================
local function pane_rows_per_page(p, w, h)
  if p.view == "grid" then
    local cols = S.dual and 3 or 4
    local cw = (w - 12) / cols
    local ch = 92
    local rows = math.max(1, math.floor((h - 22) / ch))
    return cols * rows, cols
  elseif p.view == "compact" then
    local cols = 3
    local ch = 20
    local rows = math.max(1, math.floor((h - 22) / ch))
    return cols * rows, cols
  elseif p.view == "details" then
    return math.max(1, math.floor((h - 22) / 56)), 1
  else
    return math.max(1, math.floor((h - 22) / 22)), 1
  end
end

local function pane_pages(p, w, h)
  local per = pane_rows_per_page(p, w, h)
  return math.max(1, math.ceil(#p.filtered / per))
end

-- ============================================================
--  Reload
-- ============================================================
local function pane_reload(p)
  p.error = nil
  local ok, entries = pcall(FS.list, p.cwd)
  if not ok or type(entries) ~= "table" then
    p.error = "cannot read " .. tostring(p.cwd)
    p.filtered = {}
    p.total_size = 0
    return
  end

  if not Store.get("general","show_hidden") then
    local keep = {}
    for _, e in ipairs(entries) do
      if not is_hidden(e.name) then keep[#keep+1] = e end
    end
    entries = keep
  end

  if p.cwd ~= "/" then
    table.insert(entries, 1, {
      path = parent_of(p.cwd), name = "..",
      is_dir = true, size = 0, mtime = 0, is_parent = true,
    })
  end

  FS.sort(entries, p.sort_key, p.dirs_first)
  if not p.sort_asc then
    local pin, rest = nil, {}
    for _, e in ipairs(entries) do
      if e.is_parent then pin = e else rest[#rest+1] = e end
    end
    local rev = {}
    for i = #rest, 1, -1 do rev[#rev+1] = rest[i] end
    entries = {}
    if pin then entries[1] = pin end
    for _, e in ipairs(rev) do entries[#entries+1] = e end
  end

  p.filtered = FS.filter(entries, p.filter)
  p.total_size = 0
  for _, e in ipairs(p.filtered) do
    if not e.is_dir then p.total_size = p.total_size + (e.size or 0) end
  end

  if #p.filtered == 0 then
    p.sel, p.scroll_row = 1, 0
  else
    if p.sel < 1 then p.sel = 1 end
    if p.sel > #p.filtered then p.sel = #p.filtered end
    p.scroll_row = math.max(0, math.min(p.scroll_row or 0, #p.filtered - 1))
  end
end

local function pane_navigate(p, path)
  if not path or path == "" then return end
  if not FS.is_dir(path) then
    Notify.show("warning", "Not a directory: " .. path)
    return
  end
  p.cwd = path
  p.sel, p.scroll_row = 1, 0
  p.marks = {}
  pane_reload(p)
end

-- ============================================================
--  Selection
-- ============================================================
local function pane_selected_paths(p)
  local out = {}
  if next(p.marks) then
    for path in pairs(p.marks) do out[#out+1] = path end
  else
    local e = p.filtered[p.sel]
    if e and not e.is_parent then out[1] = e.path end
  end
  return out
end

local function pane_toggle_mark(p)
  local e = p.filtered[p.sel]
  if not e or e.is_parent then return end
  p.marks[e.path] = (not p.marks[e.path]) or nil
  if p.sel + 1 <= #p.filtered then p.sel = p.sel + 1 end
end

-- ============================================================
--  Preview
-- ============================================================
local function clear_preview()
  S.preview_cache = nil
  S.preview_path = nil
end

local function load_preview(path)
  if S.preview_path == path then return end
  S.preview_path = path
  S.preview_cache = nil
  if not path then return end

  if not FS.is_dir(path) then
    local kind = FS.classify({ name = basename(path) })
    if kind == "image" then
      local img = ExtImg.load(path)
      if img then
        S.preview_cache = { kind = "image", img = img }
      else
        S.preview_cache = { kind = "error", text = "cannot load image" }
      end
    elseif kind == "text" then
      local f = io.open(path, "r")
      if f then
        local lines = {}
        for i = 1, 30 do
          local line = f:read("*l")
          if not line then break end
          lines[#lines+1] = line
        end
        f:close()
        S.preview_cache = { kind = "text", lines = lines }
      else
        S.preview_cache = { kind = "error", text = "cannot read file" }
      end
    else
      S.preview_cache = { kind = "info" }
    end
  else
    local entries = FS.list(path)
    local n, sz = 0, 0
    for _, e in ipairs(entries or {}) do
      n = n + 1
      if not e.is_dir then sz = sz + (e.size or 0) end
    end
    S.preview_cache = { kind = "dir", count = n, size = sz }
  end
end

-- ============================================================
--  File operations
-- ============================================================
local function do_copy()
  local paths = pane_selected_paths(ap())
  if #paths == 0 then Notify.show("warning", "nothing selected"); return end
  CB.set(paths, "copy")
  Notify.show("info", #paths .. " copied")
  ap().marks = {}
end

local function do_cut()
  local paths = pane_selected_paths(ap())
  if #paths == 0 then Notify.show("warning", "nothing selected"); return end
  CB.set(paths, "cut")
  Notify.show("info", #paths .. " cut")
  ap().marks = {}
end

local function do_paste()
  if not CB.has() then Notify.show("warning", "clipboard empty"); return end
  local items, mode = CB.get()
  local dst = ap().cwd
  local n = 0
  local move_pairs, copy_dsts = {}, {}
  for _, src in ipairs(items) do
    if FS.exists(src) then
      local target = dst .. "/" .. basename(src)
      if FS.exists(target) and target ~= src then
        local base, ext = target:match("^(.*)(%.[^%.]+)$")
        if not base then base, ext = target, "" end
        local k = 1
        repeat target = base .. "_" .. k .. ext; k = k + 1
        until not FS.exists(target) or k > 999
      end
      local ok = (mode == "cut") and FS.mv(src, target) or FS.cp(src, target)
      if ok then
        n = n + 1
        if mode == "cut" then move_pairs[#move_pairs+1] = { from = src, to = target }
        else copy_dsts[#copy_dsts+1] = target end
      end
    end
  end
  if mode == "cut" then CB.clear(); Ops.move_batch(move_pairs)
  elseif mode == "copy" then Ops.copy_batch(copy_dsts) end
  Notify.show("success", n .. " pasted")
  pane_reload(ap())
  if S.dual then pane_reload(op()) end
end

local function do_rename()
  local p = ap()
  local e = p.filtered[p.sel]
  if not e or e.is_parent then return end
  KB.open({
    title = "Rename", initial = e.name,
    on_accept = function(name)
      if not name or name == "" or name == e.name then return end
      local dst = p.cwd .. "/" .. name
      if FS.exists(dst) then Notify.show("warning", "already exists"); return end
      if sh.exec("mv " .. sh.shq(e.path) .. " " .. sh.shq(dst)) == 0 then
        Ops.rename(e.path, dst)
        Notify.show("success", "renamed"); pane_reload(p)
      else Notify.show("error", "rename failed") end
    end,
  })
end

local function do_delete()
  local paths = pane_selected_paths(ap())
  if #paths == 0 then Notify.show("warning", "nothing selected"); return end
  local use_trash = Store.get("dev", "use_trash") ~= false
  local msg = use_trash
    and ("Move " .. #paths .. " item(s) to trash?")
    or  ("Delete " .. #paths .. " item(s)? This cannot be undone.")
  Modal.show("Delete", msg, {
    accept_label = use_trash and "TRASH" or "DELETE",
    on_accept = function()
      if use_trash then
        local Trash = require("services.trash")
        local n = 0
        for _, pp in ipairs(paths) do
          local ok, stored = Trash.move(pp)
          if ok then Ops.trash(pp, stored); n = n + 1 end
        end
        Notify.show("warning", n .. " moved to trash")
      else
        for _, pp in ipairs(paths) do FS.rm(pp) end
        Notify.show("warning", #paths .. " deleted")
      end
      ap().marks = {}
      pane_reload(ap())
    end,
  })
end

local function do_mkdir()
  KB.open({ title = "New folder name", initial = "NewFolder",
    on_accept = function(name)
      if not name or name == "" then return end
      if FS.mkdir(ap().cwd .. "/" .. name) then
        Ops.mkdir(ap().cwd .. "/" .. name)
        Notify.show("success", "created " .. name); pane_reload(ap())
      else Notify.show("error", "mkdir failed") end
    end,
  })
end

local function do_touch()
  KB.open({ title = "New file name", initial = "untitled.txt",
    on_accept = function(name)
      if not name or name == "" then return end
      local f = io.open(ap().cwd .. "/" .. name, "w")
      if f then f:write(""); f:close()
        Ops.touch(ap().cwd .. "/" .. name)
        Notify.show("success", "created " .. name); pane_reload(ap())
      else Notify.show("error", "touch failed") end
    end,
  })
end

local function do_compress(kind)
  local paths = pane_selected_paths(ap())
  if #paths == 0 then Notify.show("warning", "nothing selected"); return end
  local dir = ap().cwd
  local out_name = basename(paths[1])
  if #paths > 1 then out_name = "archive_" .. os.date("%Y%m%d_%H%M%S") end
  local ext = (kind == "zip") and ".zip" or ".tar.gz"
  local out = dir .. "/" .. out_name .. ext
  local ok, err
  if kind == "zip" then ok, err = Archive.create_zip(paths, out, dir)
  else ok, err = Archive.create_targz(paths, out, dir) end
  if ok then Notify.show("success", "created " .. basename(out))
  else Notify.show("error", err or "compress failed") end
  pane_reload(ap())
end

local function do_extract(own_folder)
  local p = ap()
  local e = p.filtered[p.sel]
  if not e then return end
  local ok, err
  if own_folder then ok, err = Archive.extract_into_folder(e.path)
  else ok, err = Archive.extract_here(e.path) end
  if ok then Notify.show("success", "extracted")
  else Notify.show("error", err or "extract failed") end
  pane_reload(p)
end

local function do_checksum(algo)
  local p = ap()
  local e = p.filtered[p.sel]
  if not e or e.is_dir then return end
  local h, err = CS.compute(e.path, algo or "md5")
  if h then
    Modal.show((algo or "md5"):upper() .. ": " .. e.name, h,
      { accept_label = "OK", hide_cancel = true })
  else
    Notify.show("error", err or "checksum failed")
  end
end

local function do_symlink()
  local p = ap()
  local e = p.filtered[p.sel]
  if not e or e.is_parent then return end
  KB.open({ title = "Symlink name", initial = e.name .. "_link",
    on_accept = function(name)
      if not name or name == "" then return end
      local dst = p.cwd .. "/" .. name
      if FS.exists(dst) then Notify.show("warning", "already exists"); return end
      if sh.exec("ln -s " .. sh.shq(e.path) .. " " .. sh.shq(dst)) == 0 then
        Notify.show("success", "symlink created"); pane_reload(p)
      else Notify.show("error", "symlink failed") end
    end,
  })
end

local function do_chmod(mode)
  local paths = pane_selected_paths(ap())
  if #paths == 0 then return end
  local n = 0
  for _, pp in ipairs(paths) do
    if sh.exec("chmod " .. mode .. " " .. sh.shq(pp)) == 0 then n = n + 1 end
  end
  Notify.show("info", "chmod " .. mode .. " on " .. n .. " item(s)")
  pane_reload(ap())
end

local function do_batch_rename()
  local p = ap()
  local paths = pane_selected_paths(p)
  if #paths < 2 then Notify.show("warning", "select at least 2 items"); return end
  KB.open({ title = "Pattern ({name} {ext} {n} {nn} {nnn} {lower} {upper})",
    initial = "{name}_{nn}{ext}",
    on_accept = function(pattern)
      if not pattern or pattern == "" then return end
      local BR = require("ui.batchrename")
      local plan = BR.plan(paths, pattern)
      -- Show preview
      local lines = { "Preview (first 6):", "" }
      for i = 1, math.min(6, #plan) do
        lines[#lines+1] = basename(plan[i].old) .. " -> " .. plan[i].newname
      end
      if #plan > 6 then lines[#lines+1] = "... and " .. (#plan - 6) .. " more" end
      Modal.show("Batch rename", table.concat(lines, "\n"),
        { accept_label = "APPLY", cancel_label = "CANCEL",
          on_accept = function()
            local n = BR.apply(plan)
            Notify.show("success", n .. " renamed")
            Ops.batch_rename(plan)
            p.marks = {}
            pane_reload(p)
          end })
    end,
  })
end

local function do_new_archive_extract_choice()
  local p = ap()
  local e = p.filtered[p.sel]
  if not e then return end
  if not Archive.is_archive(e.path) then
    Notify.show("warning", "not an archive"); return
  end
  -- Open the dedicated Archive Rt screen
  State.archive_path = e.path
  State.go("archive_rt")
end

local function open_file()
  local p = ap()
  local e = p.filtered[p.sel]
  if not e then return end
  if e.is_parent or e.is_dir then pane_navigate(p, e.path); return end
  local kind = FS.classify(e)
  -- FGDX_RECENT_TRACK: registra il file tra i recenti
  pcall(function()
    local BM = require("services.bookmarks")
    if BM and BM.add_recent then BM.add_recent(e.path) end
  end)

  -- Check if the extender that handles this kind is disabled
  local PR = require("services.plugin_registry")
  local ext = FS.ext_of(e.name)
  local function disabled_for(plugin_key, ...)
    if not PR.is_disabled(plugin_key) then return false end
    for _, x in ipairs({...}) do
      if x == ext then return true end
    end
    return false
  end

  if disabled_for("archive_extender", "rar", "iso", "img", "dmg") then
    Notify.show("warning", "Archive Extender is disabled (enable it in FGD-X Plugins)")
    return
  end
  if disabled_for("office_reader", "docx", "xlsx", "pptx") then
    Notify.show("warning", "Office Reader is disabled (enable it in FGD-X Plugins)")
    return
  end
  -- Web View disabled => HTML opens directly in the editor (silent fallback)
  local web_view_disabled = disabled_for("web_view", "html", "htm")
  if disabled_for("chou_henka", "mp3", "ogg", "oga", "wav", "flac", "opus", "m4a", "aac",
      "wma", "ape", "alac", "mp4", "mkv", "avi", "webm", "mov", "mpg", "mpeg",
      "m4v", "flv", "wmv", "3gp", "ogv", "ts", "m2ts", "vob") then
    Notify.show("warning", "Chou Henka is disabled (enable it in FGD-X Plugins)")
    return
  end
  -- Font Preview
  if ext == "ttf" or ext == "otf" or ext == "woff" or ext == "woff2" then
    State.font_preview_path = e.path
    State.go("font_preview")
    return
  end
  -- Font Preview
  if ext == "ttf" or ext == "otf" or ext == "woff" or ext == "woff2" then
    State.font_preview_path = e.path
    State.go("font_preview")
    return
  end
  if kind == "image" then
    State.selected_path, State.selected_entry = e.path, e
    State.go("image_viewer")
  elseif kind == "text" and ext ~= "html" and ext ~= "htm" then
    State.selected_path, State.selected_entry = e.path, e
    State.go("editor")
  elseif kind == "archive" then
    do_new_archive_extract_choice()
  elseif FS.ext_of(e.name) == "pdf" then
    -- Usa lo STESSO check di doc_engine.lua: cosi' se il plugin dice
    -- READY, il PDF si apre davvero (e non salta fuori la finestrella).
    local has = false
    do
      local ok, DE = pcall(require, "services.doc_engine")
      if ok and DE then
        if DE.pdf_available then has = DE.pdf_available() == true
        elseif DE.tools then has = DE.tools.pymupdf == true end
      end
    end
    if has then
      State.library_path = e.path
      State.go("gdx_library")
    else
      Modal.show("PDF Support required",
        "Opening PDF files requires the PDF Support plugin\n" ..
        "(PyMuPDF, ~20 MB download).\n\nInstall it now?",
        { accept_label = "INSTALL", cancel_label = "CANCEL",
          accept_color = {0.70, 0.55, 0.92},
          on_accept = function()
            State.go("plugins")
          end })
    end
  elseif FS.ext_of(e.name) == "epub"
      or FS.ext_of(e.name) == "cbz" or FS.ext_of(e.name) == "cbr"
      or FS.ext_of(e.name) == "cb7" then
    State.library_path = e.path
    State.go("gdx_library")
  elseif FS.ext_of(e.name) == "html" or FS.ext_of(e.name) == "htm" then
    if web_view_disabled then
      State.selected_path, State.selected_entry = e.path, e
      State.go("editor")
    else
      Modal.show("Open HTML",
        e.name .. "\n\nWeb Preview or Source Code?",
        { accept_label = "PREVIEW", cancel_label = "SOURCE",
          accept_color = {0.30, 0.85, 0.95},
          cancel_color = {0.55, 0.55, 0.60},
          on_accept = function()
            State.net_sphere_path = e.path
            State.go("net_sphere")
          end,
          on_cancel = function()
            State.selected_path, State.selected_entry = e.path, e
            State.go("editor")
          end })
    end
  elseif FS.ext_of(e.name) == "docx" or FS.ext_of(e.name) == "xlsx"
      or FS.ext_of(e.name) == "pptx" then
    State.office_path = e.path
    State.go("office_rt")
  elseif FS.ext_of(e.name) == "iso" or FS.ext_of(e.name) == "img"
      or FS.ext_of(e.name) == "dmg" then
    State.archive_path = e.path
    State.go("archive_rt")
  elseif FS.ext_of(e.name) == "docx" or FS.ext_of(e.name) == "xlsx"
      or FS.ext_of(e.name) == "pptx" then
    State.office_path = e.path
    State.go("office_rt")

  elseif kind == "audio" or kind == "video" then
    State.chou_henka_path = e.path
    State.go("chou_henka")
  else
    Notify.show("info", "no handler for " .. basename(e.path or "?"))
  end
end

local function go_up()
  local p = ap()
  if p.cwd == "/" then State.go("filex_home")
  else pane_navigate(p, parent_of(p.cwd)) end
end

-- ============================================================
--  Sorting / filtering / view
-- ============================================================
local function cycle_view(delta)
  local p = ap()
  local i = 1
  for k, v in ipairs(VIEWS) do if v == p.view then i = k end end
  i = ((i - 1 + delta) % #VIEWS + #VIEWS) % #VIEWS + 1
  p.view = VIEWS[i]
  Store.set("general","view", p.view); Store.save()
  p.scroll_row = 0
  pane_reload(p)
  Notify.show("info", "view: " .. p.view)
end

local function cycle_filter(delta)
  local p = ap()
  local i = 1
  for k, v in ipairs(FILTERS) do if v == p.filter then i = k end end
  i = ((i - 1 + delta) % #FILTERS + #FILTERS) % #FILTERS + 1
  p.filter = FILTERS[i]
  p.sel, p.page, p.scroll_row = 1, 1, 0
  pane_reload(p)
  Notify.show("info", "filter: " .. p.filter)
end

local function cycle_sort(delta)
  local p = ap()
  local i = 1
  for k, v in ipairs(SORT_KEYS) do if v == p.sort_key then i = k end end
  i = ((i - 1 + delta) % #SORT_KEYS + #SORT_KEYS) % #SORT_KEYS + 1
  p.sort_key = SORT_KEYS[i]
  Store.set("sort","key", p.sort_key); Store.save()
  pane_reload(p)
  Notify.show("info", "sort: " .. p.sort_key)
end

local function toggle_sort_order()
  local p = ap()
  p.sort_asc = not p.sort_asc
  pane_reload(p)
  Notify.show("info", p.sort_asc and "ascending" or "descending")
end

-- ============================================================
--  Movement
-- ============================================================
local function pane_move(p, dx, dy, pane_w, pane_h)
  if #p.filtered == 0 then return end
  local per, cols = pane_rows_per_page(p, pane_w, pane_h)
  local row  = math.floor((p.sel - 1) / cols)   -- 0-based current row
  local colc = (p.sel - 1) % cols              -- 0-based current col

  if dy == 1 then
    row = row + 1
  elseif dy == -1 then
    row = row - 1
  end
  if dx == 1 and cols > 1 then
    colc = colc + 1
    if colc >= cols then colc = cols - 1 end
  elseif dx == -1 and cols > 1 then
    colc = colc - 1
    if colc < 0 then colc = 0 end
  end

  local n_rows = math.ceil(#p.filtered / cols)
  if row < 0 then row = 0 end
  if row >= n_rows then row = n_rows - 1 end

  p.sel = row * cols + colc + 1
  if p.sel > #p.filtered then p.sel = #p.filtered end

  -- Smooth scroll: keep cursor 3 rows from bottom and 1 from top
  local MARGIN_BOTTOM = 3
  local MARGIN_TOP    = 1
  local vis_rows      = math.max(1, math.floor(per / cols))
  local last_visible  = p.scroll_row + vis_rows - 1 - MARGIN_BOTTOM
  local first_visible = p.scroll_row + MARGIN_TOP

  if row > last_visible then
    p.scroll_row = row - vis_rows + 1 + MARGIN_BOTTOM
  elseif row < first_visible then
    p.scroll_row = math.max(0, row - MARGIN_TOP)
  end
  p.scroll_row = math.max(0, math.min(p.scroll_row, n_rows - vis_rows))
  if p.scroll_row < 0 then p.scroll_row = 0 end
end

local function flip_page(delta, pane_w, pane_h)
  local p = ap()
  if #p.filtered == 0 then return end
  local per, cols = pane_rows_per_page(p, pane_w, pane_h)
  local vis_rows = math.max(1, math.floor(per / cols))
  local n_rows   = math.ceil(#p.filtered / cols)
  local step     = vis_rows - 1
  local new_row  = p.scroll_row + delta * step
  if new_row < 0 then new_row = 0 end
  if new_row > n_rows - vis_rows then new_row = math.max(0, n_rows - vis_rows) end
  p.scroll_row = new_row
  local new_sel_row = math.max(p.scroll_row + 1, math.min(p.scroll_row + vis_rows, n_rows))
  p.sel = (new_sel_row - 1) * cols + 1
  if p.sel > #p.filtered then p.sel = #p.filtered end
end

-- ============================================================
--  Panel
-- ============================================================
local function panel_rows()
  local rows = {}
  local home = os.getenv("HOME") or "/tmp"

  -- ==== NAVIGATE ====
  rows[#rows+1] = { kind = "header", label = "NAVIGATE" }
  if FS.is_dir(home) then
    rows[#rows+1] = { kind = "action", icon = "home", label = "Home",
      group = 1, act = function() pane_navigate(ap(), home) end }
  end
  if FS.is_dir("/") then
    rows[#rows+1] = { kind = "action", icon = "root", label = "Root /",
      group = 1, act = function() pane_navigate(ap(), "/") end }
  end
  rows[#rows+1] = { kind = "action", icon = "menu", label = "Main menu",
    group = 1, act = function() State.go("mainmenu") end }

  -- ==== VOLUMES ====
  local vol_rows = {}
  local function add_vol(label, path, icon)
    if FS.is_dir(path) then
      vol_rows[#vol_rows+1] = { kind = "action", icon = icon, label = label,
        group = 2, act = function() pane_navigate(ap(), path) end }
    end
  end
  add_vol("SD1",  "/mnt/mmc",   "sd")
  add_vol("SD2",  "/mnt/sdcard","sd")
  add_vol("USB",  "/mnt/usb",   "usb")
  add_vol("Temp", "/tmp",       "temp")
  if #vol_rows > 0 then
    rows[#rows+1] = { kind = "header", label = "VOLUMES" }
    for _, r in ipairs(vol_rows) do rows[#rows+1] = r end
  end

  -- ==== FILES ====
  rows[#rows+1] = { kind = "header", label = "FILES" }
  rows[#rows+1] = { kind = "action", icon = "folder_plus", label = "New folder",
    group = 3, act = do_mkdir }
  rows[#rows+1] = { kind = "action", icon = "file_plus", label = "New file",
    group = 3, act = do_touch }
  rows[#rows+1] = { kind = "action", icon = "pencil", label = "Rename",
    group = 3, act = do_rename }
  rows[#rows+1] = { kind = "action", icon = "trash", label = "Delete",
    group = 3, act = do_delete, danger = true }

  -- ==== TOOLS ====
  rows[#rows+1] = { kind = "header", label = "TOOLS" }
  rows[#rows+1] = { kind = "action", icon = "disk", label = "Storage",
    group = 4, act = function() State.go("storage") end }

  rows[#rows+1] = { kind="action", icon = "chip", label = "System cockpit",

    group = 4, act = function()

      State.system_section = 1

      State.go("device")

    end }

  rows[#rows+1] = { kind="action", icon = "disk", label = "Disk tools",

    group = 4, act = function()

      State.system_section = 3

      State.go("device")

    end }rows[#rows+1] = { kind = "action", icon = "gear", label = "Settings",
    group = 4, act = function() State.go("settings") end }
  rows[#rows+1] = { kind = "action", icon = "help", label = "Help",
    group = 4, act = function() State.go("help") end }

  -- ==== OPTIONS ====
  rows[#rows+1] = { kind = "header", label = "OPTIONS" }
  rows[#rows+1] = { kind = "toggle", icon = "eye", label = "Hidden files",
    group = 5, state = Store.get("general","show_hidden") == true,
    act = function()
      local v = not Store.get("general","show_hidden")
      Store.set("general","show_hidden", v); Store.save()
      pane_reload(S.panes[1]); pane_reload(S.panes[2])
    end }
  rows[#rows+1] = { kind = "toggle", icon = "columns", label = "Dual panel",
    group = 5, state = S.dual,
    act = function()
      S.dual = not S.dual
      Store.set("general","dual", S.dual); Store.save()
    end }
  rows[#rows+1] = { kind = "toggle", icon = "panel", label = "Preview pane",
    group = 5, state = S.preview,
    act = function() S.preview = not S.preview end }

  -- ==== SESSION ====
  rows[#rows+1] = { kind = "header", label = "SESSION" }
  rows[#rows+1] = { kind = "action", icon = "power",
    label = "Close application", group = 6, danger = true,
    act = function()
      Modal.show("Close application", "Quit File-GD X?",
        { accept_label = "QUIT", cancel_label = "CANCEL",
          on_accept = function() love.event.quit() end })
    end }

  return rows
end

local function panel_move(delta)
  local rows = panel_rows()
  local n = #rows
  local i = S.panel_sel
  local t = 0
  repeat
    i = i + delta
    if i < 1 then i = n end
    if i > n then i = 1 end
    t = t + 1
  until (rows[i] and rows[i].kind ~= "header" and rows[i].kind ~= "sep")
     or t > n
  S.panel_sel = i
end

local function panel_jump_group(dir)
  local rows = panel_rows()
  local cur = rows[S.panel_sel]
  if not cur then return end
  local cur_g = cur.group or 1
  local target = cur_g + dir
  local min_g, max_g = 99, 0
  for _, r in ipairs(rows) do
    if r.group then
      if r.group < min_g then min_g = r.group end
      if r.group > max_g then max_g = r.group end
    end
  end
  if target < min_g then target = max_g end
  if target > max_g then target = min_g end
  for i, r in ipairs(rows) do
    if r.group == target and r.kind ~= "header" and r.kind ~= "sep" then
      S.panel_sel = i; return
    end
  end
end

local function panel_activate()
  local rows = panel_rows()
  local r = rows[S.panel_sel]
  if r and r.act then r.act() end
end

local function panel_move(delta)
  local rows = panel_rows()
  local n = #rows
  local i = S.panel_sel
  local t = 0
  repeat
    i = i + delta
    if i < 1 then i = n end
    if i > n then i = 1 end
    t = t + 1
  until (rows[i].kind ~= "sep") or t > n
  S.panel_sel = i
end

local function panel_jump_group(dir)
  local rows = panel_rows()
  local cur = rows[S.panel_sel]
  if not cur then return end
  local cur_g = cur.group or 1
  local target = cur_g + dir
  local min_g, max_g = 99, 0
  for _, r in ipairs(rows) do
    if r.group then
      if r.group < min_g then min_g = r.group end
      if r.group > max_g then max_g = r.group end
    end
  end
  if target < min_g then target = max_g end
  if target > max_g then target = min_g end
  for i, r in ipairs(rows) do
    if r.group == target and r.kind ~= "sep" then S.panel_sel = i; return end
  end
end

local function panel_activate()
  local rows = panel_rows()
  local r = rows[S.panel_sel]
  if r and r.act then r.act() end
end

-- ============================================================
--  Context menu
-- ============================================================
local function open_context_menu()
  local p = ap()
  local e = p.filtered[p.sel]
  if not e then return end
  local px, py = pane_rect(S.active)
  local x, y = px + 40, py + 60

  local kind = FS.classify(e)
  local is_archive = Archive.is_archive(e.path)

  local items = {
    { label = "Undo last", btn = "l2",
      act = function()
        local ok, label = Ops.undo_last()
        if ok then Notify.show("success", "undone: " .. label)
        else Notify.show("warning", tostring(label)) end
        pane_reload(ap()); pane_reload(op())
      end },
    { sep = true },
    { label = "Open",       btn = "a", act = open_file },
    { label = "Copy",       btn = "y", act = do_copy },
    { label = "Cut",        btn = "x", act = do_cut },
    { label = "Paste",      btn = "x", act = do_paste },
    { sep = true },
    { label = "Rename",     btn = "l1", act = do_rename },
    { label = "Batch rename", btn = "l2", act = do_batch_rename },
    { label = "Delete",     btn = "b",  act = do_delete },
    { label = "Mark",       btn = "select", act = function() pane_toggle_mark(p) end },
    { sep = true },
    { label = "New folder", btn = "r1", act = do_mkdir },
    { label = "New file",   btn = "r2", act = do_touch },
    { sep = true },
    { label = "Properties", btn = "y",
      act = function()
        Prop.show(e.path, e)
      end },
    { label = "Add to bookmarks", btn = "bk",
      act = function()
        local BM = require("services.bookmarks")
        BM.add_bookmark(p.cwd)
        Notify.show("success", "bookmark added")
      end },
    { label = "Toggle favorite", btn = "fav",
      act = function()
        local BM = require("services.bookmarks")
        local added = BM.toggle_favorite(e.path)
        Notify.show("info", added and "starred" or "unstarred")
      end },
    { label = "Checksum MD5", btn = "start",
      act = function() do_checksum("md5") end },
    { label = "Open in Hex Viewer", btn = "hex",
      act = function()
        State.hex_path = e.path
        State.go("hex_viewer")
      end },
  }

  if e.is_dir then
    items[#items+1] = { label = "Compress to .zip", btn = "z",
      act = function() do_compress("zip") end }
    items[#items+1] = { label = "Compress to .tar.gz", btn = "t",
      act = function() do_compress("targz") end }
  end
  if is_archive then
    items[#items+1] = { label = "Open with Archive:Rt", btn = "u",
      act = function()
        State.archive_path = e.path
        State.go("archive_rt")
      end }
  end
  items[#items+1] = { label = "Symlink", btn = "l",
    act = do_symlink }
  items[#items+1] = { label = "chmod +x", btn = "c",
    act = function() do_chmod("+x") end }
  items[#items+1] = { label = "chmod -x", btn = "c",
    act = function() do_chmod("-x") end }
  items[#items+1] = { sep = true }
  items[#items+1] = { label = "Filter: " .. p.filter, btn = "f",
    act = function() cycle_filter(1) end }

  -- Hide Hex Viewer entry if the plugin is disabled
  do
    local PR_h = require("services.plugin_registry")
    if PR_h.is_disabled("hex_viewer") then
      for i = #items, 1, -1 do
        if items[i].label == "Open in Hex Viewer" then
          table.remove(items, i)
        end
      end
    end
  end

  CM.open({ x = x, y = y, title = basename(e.name or ""), items = items })
end

-- ============================================================
--  Lifecycle
-- ============================================================
function S.enter()
  S.t_enter = 0
  S.panel_scroll = S.panel_scroll or 0
  S.dual    = Store.get("general","dual") == true
  S.mode    = "list"
  S.side_open = 0
  S.panel_sel = 1
  S.panel_scroll = 0
  S.active  = 1
  clear_preview()

  -- If filex_home set a target cwd, honour it
  if State.filex_cwd then
    local target = State.filex_cwd
    State.filex_cwd = nil
    if FS.is_dir(target) then
      S.panes[1].cwd = target
    end
  end

  local saved = Store.get("general","view") or "list"
  local view = "list"
  for _, v in ipairs(VIEWS) do if v == saved then view = v end end

  for _, p in ipairs(S.panes) do
    p.view       = view
    p.sort_asc   = Store.get("general","sort_asc") ~= false
    p.dirs_first = Store.get("sort","folders_first") ~= false
    p.filter     = "all"
    p.sort_key   = Store.get("sort","key") or "name"
    p.marks = {}
    p.scroll_row = p.scroll_row or 0
    if not FS.is_dir(p.cwd) then p.cwd = os.getenv("HOME") or "/tmp" end
  end
  if not FS.is_dir(S.panes[2].cwd) then S.panes[2].cwd = "/" end

  if State._returning and State.grid_state then
    local st = State.grid_state
    S.active = st.active or 1
    S.dual   = st.dual or S.dual
    S.preview = st.preview or false
    for i = 1, 2 do
      if st.panes and st.panes[i] then
        S.panes[i].cwd = st.panes[i].cwd or S.panes[i].cwd
        S.panes[i].sel = st.panes[i].sel or 1
        S.panes[i].page = st.panes[i].page or 1
        S.panes[i].view = st.panes[i].view or S.panes[i].view
        S.panes[i].filter = st.panes[i].filter or "all"
        S.panes[i].sort_key = st.panes[i].sort_key or "name"
        S.panes[i].sort_asc = st.panes[i].sort_asc
        S.panes[i].marks = st.panes[i].marks or {}
      end
    end
  end

  pane_reload(S.panes[1]); pane_reload(S.panes[2])
end

function S.leave()
  State.grid_state = {
    active = S.active,
    dual = S.dual,
    preview = S.preview,
    panes = {
      { cwd = S.panes[1].cwd, sel = S.panes[1].sel, page = S.panes[1].page,
        view = S.panes[1].view, filter = S.panes[1].filter,
        sort_key = S.panes[1].sort_key, sort_asc = S.panes[1].sort_asc,
        marks = S.panes[1].marks },
      { cwd = S.panes[2].cwd, sel = S.panes[2].sel, page = S.panes[2].page,
        view = S.panes[2].view, filter = S.panes[2].filter,
        sort_key = S.panes[2].sort_key, sort_asc = S.panes[2].sort_asc,
        marks = S.panes[2].marks },
    },
  }
  -- FGDX_LASTPATH_SAVE: memorizza l'ultimo percorso per storage
  do
    local cwd = S.panes[1].cwd or ""
    local storages = {
      { key = "last_SD1",  prefix = "/mnt/mmc"   },
      { key = "last_SD2",  prefix = "/mnt/sdcard"},
      { key = "last_USB",  prefix = "/mnt/usb"   },
      { key = "last_ROOT", prefix = "/"          },
    }
    local best_key, best_len = nil, -1
    for _, st in ipairs(storages) do
      local pre = st.prefix
      if pre == "/" then
        if cwd:sub(1, 1) == "/" and 0 > best_len then
          best_key, best_len = st.key, 0
        end
      elseif cwd == pre or cwd:sub(1, #pre + 1) == pre .. "/" then
        if #pre > best_len then best_key, best_len = st.key, #pre end
      end
    end
    if best_key then
      local ok, Store = pcall(require, "core.settings_store")
      if ok and Store then
        Store.set("paths", best_key, cwd)
        Store.save()
      end
    end
  end
end

function S.update(dt)
  S.t_enter = S.t_enter + dt
  KB.update(dt)
  CM.update(dt)
  local target = (S.mode == "panel") and 1 or 0
  S.side_open = S.side_open + (target - S.side_open) * math.min(1, dt * 10)

  -- Update preview if cursor moved
  local p = ap()
  local e = p.filtered[p.sel]
  if e and not e.is_parent then load_preview(e.path) else clear_preview() end
end

-- ============================================================
--  Input
-- ============================================================
local function notify_pane_switch()
  local n = S.active
  Notify.show("info", "pane " .. n .. " active")
  local ok, SFX = pcall(require, "core.audio")
  if ok then SFX.play("nav2") end
end

function S.pad(b)
  if KB.is_open() then KB.pad(b); return end
  if CM.pad(b) then return end
  if Modal.is_open() then
    if b == Input.A then Modal.accept()
    elseif b == Input.B then Modal.cancel() end
    return
  end

  if S.mode == "panel" then
    if     b == Input.UP    then panel_move(-1)
    elseif b == Input.DOWN  then panel_move( 1)
    elseif b == Input.LEFT  then panel_jump_group(-1)
    elseif b == Input.RIGHT then panel_jump_group( 1)
    elseif b == Input.A     then panel_activate()
    elseif b == Input.B or b == Input.SELECT then S.mode = "list" end
    return
  end

  local px, py, pw, ph = pane_rect(S.active)

  if     b == Input.A     then open_file()
  elseif b == Input.B     then go_up()
  elseif b == Input.X     then open_context_menu()
  elseif b == Input.Y     then cycle_sort(1)
  elseif b == Input.L1    then
    if S.dual then
      S.active = 1
      notify_pane_switch()
    else
      flip_page(-1, pw, ph)
    end
  elseif b == Input.R1    then
    if S.dual then
      S.active = 2
      notify_pane_switch()
    else
      flip_page( 1, pw, ph)
    end
  elseif b == Input.L2    then cycle_view(-1)
  elseif b == Input.R2    then
    S.preview = not S.preview
    Notify.show("info", "preview: " .. tostring(S.preview))
  elseif b == Input.SELECT then pane_toggle_mark(ap())
  elseif b == Input.START then
    if S.mode == "panel" then
      S.mode = "list"
    else
      S.mode = "panel"
      S.panel_sel = 1
      S.panel_scroll = 0
    end
  end
end

function S.hat(dir)
  if CM.hat(dir) then return end
  local px, py, pw, ph = pane_rect(S.active)
  if S.mode == "panel" then
    if     dir == "up"    then panel_move(-1)
    elseif dir == "down"  then panel_move( 1)
    elseif dir == "left"  then panel_jump_group(-1)
    elseif dir == "right" then panel_jump_group( 1) end
    return
  end
  local p = ap()
  if     dir == "up"    then pane_move(p, 0, -1, pw, ph)
  elseif dir == "down"  then pane_move(p, 0,  1, pw, ph)
  elseif dir == "left"  then pane_move(p, -1, 0, pw, ph)
  elseif dir == "right" then pane_move(p,  1, 0, pw, ph)
  end
end

function S.key(k)
  if KB.is_open() then KB.key(k); return end
  if CM.key(k) then return end
  if Modal.is_open() then
    if k == "return" then Modal.accept()
    elseif k == "escape" then Modal.cancel() end
    return
  end
  local px, py, pw, ph = pane_rect(S.active)
  if S.mode == "panel" then
    if     k == "up"    then panel_move(-1)
    elseif k == "down"  then panel_move( 1)
    elseif k == "left"  then panel_jump_group(-1)
    elseif k == "right" then panel_jump_group( 1)
    elseif k == "return" or k == "space" then panel_activate()
    elseif k == "escape" or k == "backspace" then S.mode = "list" end
    return
  end
  if     k == "up"    then pane_move(ap(), 0, -1, pw, ph)
  elseif k == "down"  then pane_move(ap(), 0,  1, pw, ph)
  elseif k == "left"  then
    if S.dual then S.active = 1
    else
      local p = ap()
      p.sel = math.max(1, p.sel - 5)
      local per = pane_rows_per_page(p, pw, ph)
      p.page = math.max(1, math.ceil(p.sel / per))
    end
  elseif k == "right" then
    if S.dual then S.active = 2
    else
      local p = ap()
      p.sel = math.min(#p.filtered, p.sel + 5)
      local per = pane_rows_per_page(p, pw, ph)
      p.page = math.max(1, math.ceil(p.sel / per))
    end
  elseif k == "pageup"   then flip_page(-1, pw, ph)
  elseif k == "pagedown" then flip_page( 1, pw, ph)
  elseif k == "return" then open_file()
  elseif k == "backspace" then go_up()
  elseif k == "escape" then State.go("mainmenu")
  elseif k == "x" then open_context_menu()
  elseif k == "y" then cycle_sort(1)
  elseif k == "o" then toggle_sort_order()
  elseif k == "v" then cycle_view(1)
  elseif k == "f" then cycle_filter(1)
  elseif k == "space" then pane_toggle_mark(ap())
  elseif k == "tab" then
    if S.dual then S.active = (S.active == 1) and 2 or 1
    else flip_page(1, pw, ph) end
  end
end

-- ============================================================
--  Rect
-- ============================================================
local SIDE_W = 260
function pane_rect(i)
  local shift = S.side_open > 0.01 and SIDE_W * S.side_open or 0
  local preview_w = S.preview and 180 or 0
  local y = Frame.TOP_H + 4
  local h = H - Frame.TOP_H - Frame.BOTTOM_H - 8
  local x0 = PAD_L + shift
  if not S.dual then
    return x0, y, W - x0 - PAD_R - preview_w, h
  end
  local total = W - x0 - PAD_R - GAP - preview_w
  local w = math.floor(total / 2)
  if i == 1 then return x0, y, w, h
  else return x0 + w + GAP, y, w, h end
end

-- ============================================================
--  Drawing: breadcrumb
-- ============================================================
local function draw_breadcrumb(p, x, y, w, focused)
  local th = State.theme
  local acc = focused and th.amber_hi or th.amber_lo
  col({0.018, 0.016, 0.014}, 1)
  love.graphics.rectangle("fill", x, y, w, 22)
  col(acc, focused and 0.9 or 0.35)
  love.graphics.rectangle("fill", x, y + 21, w, 1)

  -- Split path into chunks
  local chunks = {}
  local parts = {}
  local path = p.cwd
  if path == "/" then parts = { "/" } else
    for seg in path:gmatch("[^/]+") do parts[#parts+1] = seg end
    if path:sub(1,1) == "/" then table.insert(parts, 1, "/") end
  end

  local f = A.font(A.FONT_MONO, 10)
  love.graphics.setFont(f)
  local cx = x + 6
  local avail = w - 12
  for i, seg in ipairs(parts) do
    local label = seg
    if i > 1 and seg ~= "/" then label = seg end
    local tw = f:getWidth(label) + 10
    if cx + tw > x + w - 6 then
      -- Overflow: show "..."
      col(th.text_dim, 0.7)
      love.graphics.print("...", cx, y + 6)
      break
    end
    local last = (i == #parts)
    if last then
      col(acc, 0.20)
      love.graphics.rectangle("fill", cx, y + 3, tw, 16, 3, 3)
      col(acc, 0.85)
      love.graphics.rectangle("line", cx + 0.5, y + 3.5, tw - 1, 15, 3, 3)
      col(focused and {1,1,1} or th.text_bright, 1)
    else
      col(th.text_dim, 0.85)
    end
    love.graphics.print(label, cx + 5, y + 6)
    cx = cx + tw + 2
    if i < #parts then
      col(acc, 0.35)
      love.graphics.print("/", cx - 1, y + 6)
      cx = cx + 6
    end
  end
end

-- ============================================================
--  Drawing: free space mini bar
-- ============================================================
local function draw_free_bar(x, y, w, path)
  local total, used, free = free_space_of(path)
  if not total or total <= 0 then return end
  local pct = used / total
  local c = pct > 0.9 and {0.95,0.28,0.22}
        or (pct > 0.7 and {0.95,0.72,0.25} or {0.35,0.85,0.40})
  col({0.06, 0.07, 0.09}, 1)
  love.graphics.rectangle("fill", x, y, w, 6, 3, 3)
  col(c, 0.85)
  love.graphics.rectangle("fill", x + 1, y + 1, (w - 2) * (1 - pct), 4, 2, 2)
end

-- ============================================================
--  Drawing: preview pane
-- ============================================================
local function draw_preview(x, y, w, h)
  local th = State.theme
  col({0.020, 0.018, 0.016}, 0.95)
  love.graphics.rectangle("fill", x, y, w, h, 3, 3)
  col(th.amber_lo, 0.55)
  love.graphics.setLineWidth(1)
  love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, 3, 3)

  love.graphics.setFont(A.font(A.FONT_MONO, 10))
  col(th.amber_hi, 1)
  love.graphics.print("PREVIEW", x + 8, y + 6)
  col(th.amber_lo, 0.4)
  love.graphics.rectangle("fill", x + 8, y + 20, w - 16, 1)

  local c = S.preview_cache
  if not c then
    col(th.text_dim, 0.7)
    love.graphics.setFont(A.font(A.FONT_BODY, 10))
    love.graphics.printf("(no selection)", x, y + h/2 - 8, w, "center")
    return
  end

  if c.kind == "image" then
    local iw, ih = c.img:getDimensions()
    local maxw = w - 16
    local maxh = h - 40
    local sc = math.min(maxw / iw, maxh / ih)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(c.img, x + (w - iw*sc)/2, y + 28 + (maxh - ih*sc)/2,
      0, sc, sc)
  elseif c.kind == "text" then
    love.graphics.setFont(A.font(A.FONT_MONO, 9))
    col(th.text, 0.9)
    local ly = y + 26
    for i, line in ipairs(c.lines) do
      if ly > y + h - 6 then break end
      love.graphics.print(line:sub(1, 40), x + 6, ly)
      ly = ly + 10
    end
  elseif c.kind == "dir" then
    love.graphics.setFont(A.font(A.FONT_MONO, 10))
    col(th.text_dim, 0.85)
    love.graphics.print("Folder", x + 8, y + 28)
    col({0.94, 0.66, 0.35}, 1)
    love.graphics.print(tostring(c.count) .. " items", x + 8, y + 44)
    col({0.48, 0.80, 0.90}, 1)
    love.graphics.print(FS.human_size(c.size), x + 8, y + 60)
  elseif c.kind == "error" then
    col({0.95,0.35,0.30}, 0.85)
    love.graphics.setFont(A.font(A.FONT_BODY, 10))
    love.graphics.printf(c.text or "error", x + 8, y + 40, w - 16, "center")
  else
    col(th.text_dim, 0.7)
    love.graphics.setFont(A.font(A.FONT_BODY, 10))
    love.graphics.printf("(no preview)", x, y + h/2, w, "center")
  end
end

-- ============================================================
--  Drawing: list view
-- ============================================================
local function draw_list_view(p, x, y, w, h, focused_pane)
  local th = State.theme
  local row_h = 22
  local per = math.max(1, math.floor((h - 22) / row_h))
  local first = p.scroll_row + 1
  local last  = math.min(#p.filtered, first + per - 1)

  -- Column headers
  love.graphics.setFont(A.font(A.FONT_MONO, 9))
  col(th.text_dim, 0.75)
  love.graphics.print("NAME", x + 26, y + 2)
  love.graphics.printf("SIZE", x, y + 2, w - 150, "right")
  love.graphics.printf("DATE", x, y + 2, w - 60, "right")
  love.graphics.printf("TYPE", x, y + 2, w - 6, "right")

  local name_font = A.font(A.FONT_BODY, 11)
  local name_bold = A.font(A.FONT_BODY_BOLD, 11)
  local meta_font = A.font(A.FONT_MONO, 9)

  local cy0 = y + 16
  for idx = first, last do
    local e = p.filtered[idx]
    local slot = idx - first
    local ry = cy0 + slot * row_h
    local focused = focused_pane and (idx == p.sel)
    local marked  = p.marks[e.path]

    if focused then
      col(th.amber_hi, 0.16)
      love.graphics.rectangle("fill", x, ry, w, row_h - 1, 2, 2)
      col(th.amber_hi, 0.85)
      love.graphics.rectangle("fill", x, ry, 3, row_h - 1)
      love.graphics.setLineWidth(1.2)
      love.graphics.rectangle("line", x + 0.5, ry + 0.5, w - 1, row_h - 2, 2, 2)
      love.graphics.setLineWidth(1)
    elseif marked then
      col(th.cyan_hi, 0.10)
      love.graphics.rectangle("fill", x, ry, w, row_h - 1, 2, 2)
      col(th.cyan_hi, 0.7)
      love.graphics.rectangle("fill", x, ry, 2, row_h - 1)
    end

    FI.draw(FI.get(e, p.cwd), x + 14, ry + row_h/2 - 1, 8, focused and 1 or 0.78)

    love.graphics.setFont(focused and name_bold or name_font)
    col(focused and th.text_bright or th.text, 1)
    local nm = truncate(love.graphics.getFont(), e.name or "", w - 150)
    if marked then nm = "* " .. nm end
    love.graphics.print(nm, x + 26, ry + row_h/2 - 6)

    love.graphics.setFont(meta_font)
    col(focused and th.amber_hi or th.text_dim, 1)
    love.graphics.printf(e.is_dir and "<DIR>" or FS.human_size(e.size or 0),
      x, ry + row_h/2 - 5, w - 150, "right")
    col(th.text_dim, 0.85)
    love.graphics.printf(short_date(e.mtime), x, ry + row_h/2 - 5, w - 60, "right")
    local ext = FS.ext_of(e.name):upper()
    col(th.cyan_hi, 0.85)
    love.graphics.printf(e.is_parent and "parent"
      or (e.is_dir and "DIR" or (ext ~= "" and ext or "FILE")),
      x, ry + row_h/2 - 5, w - 6, "right")
  end
end

-- ============================================================
--  Drawing: grid view
-- ============================================================
local function draw_grid_view(p, x, y, w, h, focused_pane)
  local th = State.theme
  local cols = S.dual and 3 or 4
  local cw = (w - (cols - 1) * 4) / cols
  local ch = 92
  local rows = math.max(1, math.floor((h - 20) / ch))
  local per = cols * rows
  local first = p.scroll_row * cols + 1
  local last  = math.min(#p.filtered, first + per - 1)

  for idx = first, last do
    local e = p.filtered[idx]
    local slot = idx - first
    local gx, gy = slot % cols, math.floor(slot / cols)
    local cx = x + gx * (cw + 4)
    local cy = y + 20 + gy * ch
    local focused = focused_pane and (idx == p.sel)
    local marked = p.marks[e.path]

    if focused then
      col(th.amber_hi, 0.18)
      love.graphics.rectangle("fill", cx, cy, cw, ch - 4, 4, 4)
      col(th.amber_hi, 0.95)
      love.graphics.setLineWidth(1.8)
      love.graphics.rectangle("line", cx + 0.5, cy + 0.5, cw - 1, ch - 5, 4, 4)
      love.graphics.setLineWidth(1)
      D.glow(cx + cw/2, cy + ch/2, cw * 0.7, th.amber_hi, 0.35)
    elseif marked then
      col(th.cyan_hi, 0.20)
      love.graphics.rectangle("fill", cx, cy, cw, ch - 4, 4, 4)
      col(th.cyan_hi, 0.85)
      love.graphics.rectangle("line", cx + 0.5, cy + 0.5, cw - 1, ch - 5, 4, 4)
    else
      col({0.030, 0.026, 0.022}, 0.9)
      love.graphics.rectangle("fill", cx, cy, cw, ch - 4, 4, 4)
      col(th.amber_lo, 0.55)
      love.graphics.rectangle("line", cx + 0.5, cy + 0.5, cw - 1, ch - 5, 4, 4)
    end

    FI.draw(FI.get(e, p.cwd), cx + cw/2, cy + 34, 22, focused and 1 or 0.85)

    love.graphics.setFont(A.font(focused and A.FONT_BODY_BOLD or A.FONT_BODY, 10))
    col(focused and th.text_bright or th.text, 1)
    love.graphics.printf(truncate(love.graphics.getFont(), e.name or "", cw - 8),
      cx + 4, cy + 62, cw - 8, "center")
  end
end

-- ============================================================
--  Drawing: compact view
-- ============================================================
local function draw_compact_view(p, x, y, w, h, focused_pane)
  local th = State.theme
  local cols = 3
  local cw = (w - (cols - 1) * 4) / cols
  local row_h = 20
  local rows = math.max(1, math.floor((h - 20) / row_h))
  local per = cols * rows
  local first = p.scroll_row * cols + 1
  local last  = math.min(#p.filtered, first + per - 1)

  local f = A.font(A.FONT_BODY, 10)
  love.graphics.setFont(f)
  for idx = first, last do
    local e = p.filtered[idx]
    local slot = idx - first
    local gx, gy = slot % cols, math.floor(slot / cols)
    local cx = x + gx * (cw + 4)
    local cy = y + 20 + gy * row_h
    local focused = focused_pane and (idx == p.sel)
    local marked = p.marks[e.path]

    if focused then
      col(th.amber_hi, 0.18)
      love.graphics.rectangle("fill", cx, cy, cw, row_h - 2, 2, 2)
      col(th.amber_hi, 0.85)
      love.graphics.rectangle("fill", cx, cy, 2, row_h - 2)
    elseif marked then
      col(th.cyan_hi, 0.10)
      love.graphics.rectangle("fill", cx, cy, cw, row_h - 2, 2, 2)
    end

    FI.draw(FI.get(e, p.cwd), cx + 10, cy + row_h/2 - 1, 6, focused and 1 or 0.7)
    col(focused and th.text_bright or th.text, 1)
    local nm = truncate(f, e.name or "", cw - 24)
    if marked then nm = "*" .. nm end
    love.graphics.print(nm, cx + 20, cy + row_h/2 - 5)
  end
end

-- ============================================================
--  Drawing: details view
-- ============================================================
local function draw_details_view(p, x, y, w, h, focused_pane)
  local th = State.theme
  local row_h = 56
  local per = math.max(1, math.floor((h - 20) / row_h))
  local first = p.scroll_row + 1
  local last  = math.min(#p.filtered, first + per - 1)

  for idx = first, last do
    local e = p.filtered[idx]
    local slot = idx - first
    local ry = y + 20 + slot * row_h
    local focused = focused_pane and (idx == p.sel)
    local marked  = p.marks[e.path]

    if focused then
      col(th.amber_hi, 0.16)
      love.graphics.rectangle("fill", x, ry, w, row_h - 3, 3, 3)
      col(th.amber_hi, 0.85)
      love.graphics.rectangle("fill", x, ry, 3, row_h - 3)
      love.graphics.setLineWidth(1.2)
      love.graphics.rectangle("line", x + 0.5, ry + 0.5, w - 1, row_h - 4, 3, 3)
      love.graphics.setLineWidth(1)
    elseif marked then
      col(th.cyan_hi, 0.10)
      love.graphics.rectangle("fill", x, ry, w, row_h - 3, 3, 3)
    else
      col({0.026, 0.024, 0.022}, 0.7)
      love.graphics.rectangle("fill", x, ry, w, row_h - 3, 3, 3)
    end

    FI.draw(FI.get(e, p.cwd), x + 22, ry + row_h/2 - 2, 12, focused and 1 or 0.85)

    love.graphics.setFont(A.font(focused and A.FONT_BODY_BOLD or A.FONT_BODY, 12))
    col(focused and th.text_bright or th.text, 1)
    love.graphics.print(truncate(love.graphics.getFont(), e.name or "", w - 60),
      x + 44, ry + 6)

    love.graphics.setFont(A.font(A.FONT_MONO, 9))
    col(th.text_dim, 0.9)
    love.graphics.print("size", x + 44, ry + 26)
    col(focused and th.amber_hi or th.text, 1)
    love.graphics.print(e.is_dir and "<DIR>" or FS.human_size(e.size or 0),
      x + 78, ry + 26)

    col(th.text_dim, 0.9)
    love.graphics.print("modified", x + 140, ry + 26)
    col(th.text, 1)
    love.graphics.print(short_date(e.mtime), x + 190, ry + 26)

    col(th.text_dim, 0.9)
    love.graphics.print("type", x + 260, ry + 26)
    col(th.cyan_hi, 0.9)
    local ext = FS.ext_of(e.name):upper()
    love.graphics.print(e.is_dir and "DIR" or (ext ~= "" and ext or "FILE"),
      x + 300, ry + 26)

    if not e.is_dir and e.path then
      col(th.text_dim, 0.65)
      love.graphics.print(truncate(love.graphics.getFont(), e.path, w - 60),
        x + 44, ry + 40)
    end
  end
end

-- ============================================================
--  Drawing: pane
-- ============================================================
local function draw_pane(p, x, y, w, h, focused_pane, pane_idx)
  local th = State.theme
  col({0.018, 0.016, 0.014}, 1)
  love.graphics.rectangle("fill", x, y, w, h, 3, 3)

  -- Breadcrumb
  draw_breadcrumb(p, x, y, w, focused_pane)

  -- Header strip: item count + free bar
  local info_y = y + 24
  love.graphics.setFont(A.font(A.FONT_MONO, 9))
  col(focused_pane and th.amber_hi or th.text_dim, focused_pane and 1 or 0.7)
  local per = pane_rows_per_page(p, w, h)
  local n_rows = math.ceil(math.max(1, #p.filtered) / math.max(1, per))
  local range = ""
  if #p.filtered > 0 then
    range = string.format("  [%d-%d/%d]",
      p.scroll_row + 1,
      math.min(#p.filtered, p.scroll_row + per),
      #p.filtered)
  end
  local info = string.format("%d items%s  %s",
    #p.filtered, range, FS.human_size(p.total_size))
  love.graphics.print(info, x + 6, info_y)
  draw_free_bar(x + w - 60, info_y + 2, 54, p.cwd)
  info_y = info_y + 14

  local cy = info_y
  local ch = h - (info_y - y) - 4

  -- Content
  if #p.filtered == 0 then
    col(th.text_dim, 0.8)
    love.graphics.setFont(A.font(A.FONT_BODY, 11))
    love.graphics.printf(p.error or "(empty)", x, cy + ch/2 - 8, w, "center")
  else
    if p.view == "grid" then
      draw_grid_view(p, x + 4, cy, w - 8, ch, focused_pane)
    elseif p.view == "compact" then
      draw_compact_view(p, x + 4, cy, w - 8, ch, focused_pane)
    elseif p.view == "details" then
      draw_details_view(p, x + 4, cy, w - 8, ch, focused_pane)
    else
      draw_list_view(p, x + 4, cy, w - 8, ch, focused_pane)
    end
  end

  -- Border
  if focused_pane then
    col(th.amber_hi, 0.95)
    love.graphics.setLineWidth(2)
  else
    col(th.amber_lo, 0.55)
    love.graphics.setLineWidth(1.4)
  end
  love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, 3, 3)
  love.graphics.setLineWidth(1)

  -- Pane number badge
  if S.dual then
    local bx = x + w - 22
    local by = y + 4
    local acc = (pane_idx == S.active) and th.amber_hi or th.text_dim
    col(acc, 0.85)
    love.graphics.setFont(A.font(A.FONT_MONO, 9))
    love.graphics.printf(tostring(pane_idx), bx, by, 16, "center")
  end
end

-- ============================================================
--  SPDW side panel
-- ============================================================
-- small icon glyphs for the panel
local function panel_icon(kind, cx, cy, r, colour, alpha)
  col(colour, alpha or 1)
  love.graphics.setLineWidth(1.4)
  if kind == "home" then
    love.graphics.polygon("line",
      cx, cy - r*0.85,
      cx + r*0.85, cy - r*0.05,
      cx + r*0.5,  cy - r*0.05,
      cx + r*0.5,  cy + r*0.85,
      cx - r*0.5,  cy + r*0.85,
      cx - r*0.5,  cy - r*0.05,
      cx - r*0.85, cy - r*0.05)
  elseif kind == "root" then
    love.graphics.circle("line", cx, cy, r*0.85)
    love.graphics.line(cx, cy - r*0.85, cx, cy + r*0.85)
    love.graphics.line(cx - r*0.85, cy, cx + r*0.85, cy)
  elseif kind == "menu" then
    for i = -1, 1 do
      love.graphics.line(cx - r*0.75, cy + i * r*0.5,
                         cx + r*0.75, cy + i * r*0.5)
    end
  elseif kind == "sd" then
    love.graphics.rectangle("line", cx - r*0.55, cy - r*0.8, r*1.1, r*1.6, 1, 1)
    love.graphics.line(cx - r*0.55, cy - r*0.55, cx + r*0.55, cy - r*0.55)
    love.graphics.rectangle("fill", cx - r*0.35, cy + r*0.15, r*0.7, r*0.35)
  elseif kind == "usb" then
    love.graphics.rectangle("line", cx - r*0.3, cy - r*0.85, r*0.6, r*0.7, 1, 1)
    love.graphics.rectangle("line", cx - r*0.55, cy - r*0.15, r*1.1, r*0.85, 1, 1)
  elseif kind == "temp" then
    love.graphics.rectangle("line", cx - r*0.7, cy - r*0.7, r*1.4, r*1.4, 1, 1)
    love.graphics.circle("line", cx, cy, r*0.3)
  elseif kind == "folder_plus" then
    love.graphics.rectangle("line", cx - r*0.85, cy - r*0.35, r*1.7, r*1.05)
    love.graphics.rectangle("fill", cx - r*0.85, cy - r*0.7, r*0.6, r*0.35)
    love.graphics.line(cx + r*0.15, cy + r*0.05, cx + r*0.15, cy + r*0.55)
    love.graphics.line(cx - r*0.1,  cy + r*0.30, cx + r*0.4,  cy + r*0.30)
  elseif kind == "file_plus" then
    love.graphics.rectangle("line", cx - r*0.55, cy - r*0.85, r*1.1, r*1.7, 1, 1)
    love.graphics.line(cx, cy - r*0.1, cx, cy + r*0.5)
    love.graphics.line(cx - r*0.3, cy + r*0.2, cx + r*0.3, cy + r*0.2)
  elseif kind == "pencil" then
    love.graphics.line(cx - r*0.55, cy + r*0.55, cx + r*0.55, cy - r*0.55)
    love.graphics.line(cx + r*0.55, cy - r*0.55, cx + r*0.75, cy - r*0.75)
  elseif kind == "trash" then
    love.graphics.rectangle("line", cx - r*0.6, cy - r*0.5, r*1.2, r*1.3, 1, 1)
    love.graphics.line(cx - r*0.75, cy - r*0.6, cx + r*0.75, cy - r*0.6)
    love.graphics.line(cx - r*0.25, cy - r*0.6, cx - r*0.25, cy - r*0.85)
    love.graphics.line(cx + r*0.25, cy - r*0.6, cx + r*0.25, cy - r*0.85)
  elseif kind == "disk" then
    love.graphics.ellipse("line", cx, cy, r*0.85, r*0.45)
    love.graphics.line(cx, cy - r*0.45, cx, cy + r*0.45)
    love.graphics.circle("fill", cx, cy, r*0.12)
  elseif kind == "chip" then
    love.graphics.rectangle("line", cx - r*0.6, cy - r*0.6, r*1.2, r*1.2, 1, 1)
    for i = -1, 1 do
      love.graphics.line(cx - r*0.85, cy + i*r*0.35, cx - r*0.6, cy + i*r*0.35)
      love.graphics.line(cx + r*0.6,  cy + i*r*0.35, cx + r*0.85, cy + i*r*0.35)
    end
  elseif kind == "gear" then
    for i = 0, 7 do
      local a = i * math.pi / 4
      love.graphics.line(cx + math.cos(a) * r*0.5, cy + math.sin(a) * r*0.5,
                         cx + math.cos(a) * r*0.9, cy + math.sin(a) * r*0.9)
    end
    love.graphics.circle("line", cx, cy, r*0.5)
  elseif kind == "help" then
    love.graphics.circle("line", cx, cy, r*0.85)
    love.graphics.line(cx - r*0.3, cy - r*0.3, cx + r*0.05, cy - r*0.3)
    love.graphics.arc("line", "open", cx - r*0.1, cy - r*0.3, r*0.25, math.pi, 0)
    love.graphics.line(cx, cy, cx, cy + r*0.1)
    love.graphics.circle("fill", cx, cy + r*0.4, 1.2)
  elseif kind == "eye" then
    love.graphics.ellipse("line", cx, cy, r*0.9, r*0.5)
    love.graphics.circle("fill", cx, cy, r*0.22)
  elseif kind == "columns" then
    love.graphics.rectangle("line", cx - r*0.85, cy - r*0.6, r*0.7, r*1.2, 1, 1)
    love.graphics.rectangle("line", cx + r*0.15, cy - r*0.6, r*0.7, r*1.2, 1, 1)
  elseif kind == "panel" then
    love.graphics.rectangle("line", cx - r*0.85, cy - r*0.6, r*1.7, r*1.2, 1, 1)
    love.graphics.line(cx + r*0.2, cy - r*0.6, cx + r*0.2, cy + r*0.6)
  elseif kind == "power" then
    love.graphics.arc("line", "open", cx, cy + r*0.15, r*0.7,
      -math.pi*0.75, -math.pi*0.25)
    love.graphics.line(cx, cy - r*0.85, cx, cy - r*0.15)
  else
    love.graphics.circle("line", cx, cy, r*0.7)
  end
  love.graphics.setLineWidth(1)
end

-- SPDW symbol cache
local _spdw_img = nil
local function get_spdw_img()
  if _spdw_img == nil then
    local ok, img = pcall(A.image, "assets/images/spdw_symbol.png")
    _spdw_img = (ok and img) or false
  end
  return _spdw_img or nil
end

local function draw_spdw_symbol(cx, cy, r, rot, alpha)
  local img = get_spdw_img()
  love.graphics.push()
  love.graphics.translate(cx, cy)
  love.graphics.rotate(rot or 0)
  if img then
    local iw, ih = img:getDimensions()
    local sc = (r * 2) / math.max(iw, ih)
    love.graphics.setColor(1, 1, 1, alpha or 1)
    love.graphics.draw(img, -iw * sc / 2, -ih * sc / 2, 0, sc, sc)
  else
    local th = State.theme
    col(th.amber_hi, alpha or 1)
    love.graphics.setLineWidth(2)
    love.graphics.circle("line", 0, 0, r)
    love.graphics.line(-r*0.5, 0, r*0.5, 0)
    love.graphics.line(0, -r*0.5, 0, r*0.5)
    love.graphics.setLineWidth(1)
  end
  love.graphics.pop()
  love.graphics.setColor(1, 1, 1, 1)
end

local function draw_side_panel(open)
  if open < 0.01 then return end
  local th = State.theme
  local x = -SIDE_W + SIDE_W * open
  local w = SIDE_W
  local h = H

  -- Full backdrop (covers everything behind)
  col({0.012, 0.010, 0.016}, 0.985)
  love.graphics.rectangle("fill", x, 0, w, h)

  -- Right edge accent
  col(th.amber_hi, 0.9)
  love.graphics.rectangle("fill", x + w - 1, 0, 1, h)
  col(th.amber_hi, 0.35)
  love.graphics.rectangle("fill", x + w - 3, 0, 1, h)

  -- Header band (top)
  local hy = Frame.TOP_H
  local hh = 44
  col({0.020, 0.016, 0.026}, 1)
  love.graphics.rectangle("fill", x, hy, w, hh)
  col(th.amber_hi, 0.85)
  love.graphics.rectangle("fill", x + 14, hy + hh - 1, w - 28, 1)

  love.graphics.setFont(A.font(A.FONT_TITLE, 15))
  col(th.amber_hi, 1)
  love.graphics.print("SPDW", x + 16, hy + 10)
  love.graphics.setFont(A.font(A.FONT_MONO, 9))
  col(th.text_dim, 0.85)
  love.graphics.print("9483  SYSTEM MENU", x + 66, hy + 16)

  -- Bottom footer
  local fy = H - Frame.BOTTOM_H - 26
  col(th.amber_hi, 0.6)
  love.graphics.rectangle("fill", x + 14, fy - 6, w - 28, 1)
  love.graphics.setFont(A.font(A.FONT_MONO, 9))
  col(th.text_dim, 0.7)
  love.graphics.print("v1.5.0", x + 16, fy)
  love.graphics.printf("SPDW FACTORY", x + 16, fy, w - 32, "right")

  -- Content region
  local cy_top = hy + hh + 6
  local cy_bot = fy - 12
  local cy_h = cy_bot - cy_top

  local rows = panel_rows()

  -- Row heights
  local HDR_H = 15
  local ITEM_H = 22

  local function row_h(r)
    if r.kind == "header" then return HDR_H end
    if r.kind == "sep" then return 6 end
    return ITEM_H
  end

  -- Total content height
  local total = 0
  for _, r in ipairs(rows) do total = total + row_h(r) end

  -- Selected position in pixels
  local sel_top = 0
  for i = 1, S.panel_sel - 1 do sel_top = sel_top + row_h(rows[i] or {}) end
  local sel_bot = sel_top + row_h(rows[S.panel_sel] or {})

  -- Scroll to keep selection visible
  if sel_top - 8 < S.panel_scroll then
    S.panel_scroll = math.max(0, sel_top - 8)
  end
  if sel_bot + 8 > S.panel_scroll + cy_h then
    S.panel_scroll = math.min(math.max(0, total - cy_h), sel_bot + 8 - cy_h)
  end
  S.panel_scroll = math.max(0, math.min(S.panel_scroll, math.max(0, total - cy_h)))

  love.graphics.setScissor(x, cy_top, w, cy_h)
  local yy = cy_top - S.panel_scroll

  for i, r in ipairs(rows) do
    if r.kind == "header" then
      love.graphics.setFont(A.font(A.FONT_MONO, 8))
      col(th.amber_hi, 0.55)
      love.graphics.print(r.label, x + 18, yy + 3)
      col(th.amber_hi, 0.18)
      love.graphics.rectangle("fill", x + 18, yy + HDR_H - 2, w - 36, 1)
    elseif r.kind == "sep" then
      col(th.amber_hi, 0.15)
      love.graphics.rectangle("fill", x + 18, yy + 3, w - 36, 1)
    else
      local focused = (i == S.panel_sel)
      local danger = r.danger == true
      local accent = danger and {0.95, 0.35, 0.30} or th.amber_hi

      if focused then
        col(accent, 0.20)
        love.graphics.rectangle("fill", x + 8, yy, w - 16, ITEM_H - 2, 3, 3)
        col(accent, 0.95)
        love.graphics.setLineWidth(1.4)
        love.graphics.rectangle("line", x + 8.5, yy + 0.5, w - 17, ITEM_H - 3, 3, 3)
        love.graphics.setLineWidth(1)
        col(accent, 1)
        love.graphics.rectangle("fill", x + 8, yy + 4, 3, ITEM_H - 10)
      end

      -- Icon
      local icx = x + 26
      local icy = yy + (ITEM_H - 2) / 2
      panel_icon(r.icon or "dot", icx, icy, 7,
        focused and accent or {0.75, 0.70, 0.62},
        focused and 1 or 0.75)

      -- Label
      love.graphics.setFont(A.font(A.FONT_BODY, 12))
      col(focused and {1,1,1} or th.text, 1)
      love.graphics.print(r.label, x + 44, yy + 4)

      -- Toggle marker
      if r.kind == "toggle" then
        local on = r.state == true
        local bx = x + w - 32
        local by = yy + (ITEM_H - 2) / 2
        col({0.06, 0.06, 0.08}, 1)
        love.graphics.rectangle("fill", bx - 10, by - 6, 20, 12, 6, 6)
        col(on and {0.35, 0.90, 0.50} or {0.55, 0.28, 0.30}, 0.9)
        love.graphics.setLineWidth(1.1)
        love.graphics.rectangle("line", bx - 9.5, by - 5.5, 19, 11, 6, 6)
        love.graphics.setLineWidth(1)
        col({0.96, 0.96, 0.97}, 1)
        love.graphics.circle("fill", on and (bx + 4) or (bx - 4), by, 4)
      end
    end
    yy = yy + row_h(r)
  end
  love.graphics.setScissor()

  -- Scrollbar
  if total > cy_h then
    local track_h = cy_h - 8
    local thumb_h = math.max(24, track_h * (cy_h / total))
    local thumb_y = cy_top + 4 + (track_h - thumb_h) *
      (S.panel_scroll / math.max(1, total - cy_h))
    col(th.amber_hi, 0.5)
    love.graphics.rectangle("fill", x + w - 5, thumb_y, 2, thumb_h, 1, 1)
  end
end

-- ============================================================
--  Main draw
-- ============================================================
function S.override_sfx(_name)
  return false
end

function S.draw()
  local th = State.theme
  D.bg()

  col(th.grid_faint, 0.06)
  for gy = Frame.TOP_H, H - Frame.BOTTOM_H, 16 do
    love.graphics.line(0, gy, W, gy)
  end

  local draw_count = S.dual and 2 or 1
  for i = 1, draw_count do
    local pane = S.panes[i]
    local px, py, pw, ph = pane_rect(i)
    local focused = (i == S.active) and (S.mode == "list")
    draw_pane(pane, px, py, pw, ph, focused, i)
  end

  -- Preview pane on the right
  if S.preview then
    local pxx, pyy, pww, phh = pane_rect(1)
    local preview_w = 180
    local preview_x = W - preview_w - PAD_R
    draw_preview(preview_x, pyy, preview_w, phh)
  end

  draw_side_panel(S.side_open)

  -- SPDW symbol: HUD badge, spins with the panel transition
  do
    local sym_cx = W - 44
    local sym_cy = H - Frame.BOTTOM_H - 44
    local sym_r = 26
    local rot = S.side_open * math.pi * 4
    local alpha = 0.28 + 0.72 * S.side_open
    if S.side_open > 0.05 then
      D.glow(sym_cx, sym_cy, sym_r * 2.4, {0.94, 0.66, 0.35},
        0.55 * S.side_open)
    end
    draw_spdw_symbol(sym_cx, sym_cy, sym_r, rot, alpha)
  end

  local hints
  if S.mode == "panel" then
    hints = {
      { key="up",    label="Navigate" },
      { key="a",     label="Activate" },
      { key="b",     label="Close" },
    }
  else
    hints = {
      { key="up",    label="Move" },
      { key="a",     label="Open" },
      { key="b",     label="Up" },
      { key="x",     label="Actions" },
      { key="y",     label="Sort" },
      { key="l2",    label="View" },
      { key="start", label="Panel" },
    }
  end

  Frame.draw_top("FGD", "grid")
  Frame.draw_bottom(hints)

  CM.draw()
  Prop.draw()

  D.scanlines(W, H, 0.06)
  D.vignette(W, H, 0.55)
end

return S
