-- screens/plugins.lua -- Plugin Hub v3 (definitive edition).
--
-- Three tabs, one intent each:
--   LAUNCH : only installed + enabled + has-screen plugins. A = run.
--   STORE  : Minoru Store. Catalog + management. Install / uninstall /
--            enable / disable / permissions / logs. Detail view inline.
--   TOOLS  : muOS applications (catalog + SD cards). Install / open /
--            manage / uninstall / repo QR.
--
-- Layout : header strip + tab bar + content. L1/R1 = change tab.
-- D-pad  : navigate. A = primary action. X = secondary. Y = install/refresh.
-- B      : back (or tab -> LAUNCH when in sub-view).

local A      = require("core.assets")
local State  = require("core.state")
local Input  = require("core.input_map")
local Frame  = require("ui.frame")
local D      = require("ui.draw")
local Notify = require("ui.notify")
local Modal  = require("ui.modal")
local sh     = require("core.sh")
local PR     = require("services.plugin_registry")
local Cat    = require("services.catalog")
local Loader = require("plugins.loader")
local FS     = require("services.fs")
local ExtImg = require("core.external_image")

local S = {}
local W, H = 640, 480

-- ============================================================
--  Palette
-- ============================================================
local AMB    = {0.94, 0.66, 0.35}
local AMB_HI = {1.00, 0.80, 0.48}
local CYA    = {0.48, 0.80, 0.90}
local CYA_HI = {0.62, 0.94, 1.00}
local PUR    = {0.70, 0.55, 0.92}
local PUR_HI = {0.86, 0.72, 1.00}
local GRN    = {0.55, 0.85, 0.45}
local GRN_HI = {0.70, 1.00, 0.55}
local YEL    = {0.95, 0.80, 0.30}
local RED    = {0.95, 0.30, 0.25}
local RED_HI = {1.00, 0.48, 0.42}
local GRY    = {0.45, 0.45, 0.50}
local BLU    = {0.55, 0.75, 0.95}

-- LÖVE 11.5: Font:getWrap(text, w) returns (width, table_of_lines).
-- Most code forgets the 2nd return value is a TABLE, then does
-- `tbl + number` and crashes silently inside pcall (black screen).
-- Use this helper to compute the pixel height of wrapped text.
local function _wrap_h(font, text, width)
  if not text or text == "" or not font then return 0 end
  local _, lines = font:getWrap(text, width)
  if type(lines) ~= "table" then return font:getHeight() end
  return #lines * font:getHeight()
end

local function col(c, a) love.graphics.setColor(c[1], c[2], c[3], a or 1) end

local function human(n)
  if not n or n <= 0 then return "0 B" end
  local u = {"B","KB","MB","GB","TB"}; local i = 1
  while n >= 1024 and i < #u do n = n / 1024; i = i + 1 end
  if i == 1 then return string.format("%d %s", n, u[i]) end
  return string.format("%.1f %s", n, u[i])
end

local function human_kb(n)
  if not n or n <= 0 then return "0 KB" end
  if n < 1024 then return n .. " KB" end
  return string.format("%.2f MB", n / 1024)
end

local function trunc(font, s, maxw)
  if not s then return "" end
  if font:getWidth(s) <= maxw then return s end
  local out = s
  while #out > 1 and font:getWidth(out .. ".") > maxw do out = out:sub(1,-2) end
  return out .. "."
end

-- ============================================================
--  Layout constants (fixed grid, no overlaps)
-- ============================================================
local TAB_Y      = Frame.TOP_H + 6
local TAB_H      = 34
local INFO_Y     = TAB_Y + TAB_H + 6
local INFO_H     = 16
local CONTENT_Y  = INFO_Y + INFO_H + 6

-- ============================================================
--  Tabs
-- ============================================================
local TABS = {
  { id = "launch", label = "LAUNCH", accent = AMB, accent_hi = AMB_HI },
  { id = "store",  label = "STORE",  accent = PUR, accent_hi = PUR_HI },
  { id = "tools",  label = "MUOS TOOLS", accent = CYA, accent_hi = CYA_HI },
}
local NTAB = #TABS

-- ============================================================
--  Module state
-- ============================================================
local tab       = 1
local t_global  = 0
local last_dt   = 0.016

local sel        = { 1, 1, 1 }
local scroll     = { 0, 0, 0 }
local view       = { "list", "list", "list" }
local detail_sel = { 1, 1, 1 }
local detail_tab = { 1, 1, 1 }
local detail_scroll = { 0, 0, 0 }

local filter     = 1
local store_items, store_loaded = {}, false
local tools_items, tools_loaded = {}, false
local tools_scanning = false

local progress = {}
local tools_dl = {}   -- [download_id] = { item = t, filename = ... }

-- ============================================================
--  Plugin helpers
-- ============================================================
local function __pdf_prefix()
  local cands = { "data/pdf_pack/lib", "data/pdf_pack",
                  "data/downloads/extracted" }
  for _, d in ipairs(cands) do
    local h = io.popen("test -d " .. require("core.sh").shq(d .. "/pymupdf") ..
      " && echo ok 2>/dev/null")
    if h then
      local o = h:read("*a") or ""
      h:close()
      if o:find("ok", 1, true) then
        return "PYTHONPATH=" .. require("core.sh").shq(d) .. " "
      end
    end
  end
  return ""
end

local function status_of(p)
  if p.needs_perm then return { label = "PERM", colour = YEL } end
  if p.source == "local" and p.screen == nil                      then
    return { label = "ERROR", colour = RED }
  end
  local st = progress[p.id]
  if st and st > 0 and st < 1 then
    return { label = string.format("%.0f%%", st * 100), colour = AMB }
  end
  if not p.installed then return { label = "MISSING", colour = RED } end
  if p.disabled then return { label = "OFF", colour = GRY } end
  return { label = "READY", colour = GRN }
end

-- ============================================================
--  LAUNCH list
-- ============================================================
local LAUNCH_EXCLUDE = {
  -- These live only in the STORE tab (info-only / superseded screens).
  archive_extender = true,
  office_reader    = true,
  web_view         = true,
}

local launch_list = {}

local function build_launch_list()
  local out = {}
  for _, p in ipairs(Loader.list()) do
    -- NOTE: do NOT filter by needs_perm. Plugins that still need
    -- consent must be visible: pressing A opens the perm dialog,
    -- which then auto-launches the plugin. Filtering them out made
    -- the LAUNCH tab empty on first boot.
    if p.key and p.screen and not LAUNCH_EXCLUDE[p.key]
       and not PR.is_disabled(p.key) then
      local ci = Cat.plugin_by_id and Cat.plugin_by_id(p.key) or nil
      out[#out + 1] = {
        key     = p.key,
        name    = (ci and ci.name) or p.name or p.key,
        tagline = (ci and ci.tagline) or p.desc or "",
        version = (ci and ci.version) or p.version or "1.0.0",
        author  = (ci and ci.author) or p.author or "sirpips",
        colour  = (ci and ci.colour) or p.colour or PUR,
        icon    = (ci and ci.icon) or p.icon or "plug",
        screen  = p.key,
        is_new  = (ci and ci.new) or false,
      }
    end
  end
  table.sort(out, function(a, b)
    if a.special ~= b.special then return a.special end
    return (a.name or ""):lower() < (b.name or ""):lower()
  end)
  return out
end

-- ============================================================
--  STORE list
-- ============================================================
local INFO_ONLY = { epub_reader_pro = true }

-- Plugins that have no real interactive screen (extenders, info-only).
-- The STORE detail hides the OPEN action for these.
local NO_OPEN = {
  archive_extender = true,
  office_reader    = true,
  web_view         = true,
}


local function build_store_list()
  local out, seen = {}, {}
  for _, p in ipairs(Loader.list()) do
    if not p.extender and p.key then
      local ci = Cat.plugin_by_id and Cat.plugin_by_id(p.key) or nil
      out[#out + 1] = {
        id           = p.key,
        name         = (ci and ci.name) or p.name or p.key,
        tagline      = (ci and ci.tagline) or p.desc or "",
        description  = (ci and ci.description) or p.desc or "",
        version      = (ci and ci.version) or p.version or "1.0.0",
        author       = (ci and ci.author) or p.author or "sirpips",
        category     = (ci and ci.category) or p.category or "local",
        colour       = (ci and ci.colour) or p.colour or PUR,
        icon         = (ci and ci.icon) or p.icon or "plug",
        features     = ci and ci.features or nil,
        dependencies = ci and ci.dependencies or nil,
        source       = "local",
        builtin      = true,
        installed    = true,
        disabled     = PR.is_disabled(p.key),
        screen       = p.key,
        needs_perm   = p.needs_perm == true,
        manage_key   = p.manage_key,
        is_new       = (ci and ci.new) or false,
        raw          = ci,
      }
      seen[p.key] = true
    end
  end
  for _, pl in ipairs(Cat.all_plugins()) do
    if not seen[pl.id] then
      local disabled = PR.is_disabled(pl.id)
      local installed = false
      if pl.builtin then installed = true
      elseif pl.installed_check then
        local o = sh.read(pl.installed_check or "echo no")
        installed = (o and o:find("ok", 1, true)) ~= nil
        if not installed then
          local o2 = sh.read(__pdf_prefix() ..
            (pl.installed_check or "echo no") .. " 2>&1")
          installed = (o2 and o2:find("ok", 1, true)) ~= nil
        end
      end
      out[#out + 1] = {
        id           = pl.id,
        name         = pl.name or pl.id,
        tagline      = pl.tagline or "",
        description  = pl.description or "",
        version      = pl.version or "1.0.0",
        author       = pl.author or "sirpips",
        category     = pl.category or "catalog",
        colour       = pl.colour or PUR,
        icon         = pl.icon or "plug",
        features     = pl.features,
        dependencies = pl.dependencies,
        source       = "catalog",
        builtin      = pl.builtin == true,
        installed    = installed,
        disabled     = disabled,
        screen       = pl.open_screen,
        needs_perm   = false,
        is_new       = pl.new or false,
        info_only    = INFO_ONLY[pl.id] == true,
        raw          = pl,
      }
      seen[pl.id] = true
    end
  end
  table.sort(out, function(a, b)
    local function rank(p)
      if p.needs_perm then return 5 end
      if p.info_only then return 4 end
      if p.installed and not p.disabled then return 1 end
      if p.installed and p.disabled then return 2 end
      return 3
    end
    local ra, rb = rank(a), rank(b)
    if ra ~= rb then return ra < rb end
    return (a.name or ""):lower() < (b.name or ""):lower()
  end)
  return out
end

local FILTERS = {
  { id = "all",     label = "ALL",     colour = BLU },
  { id = "ready",   label = "READY",   colour = GRN },
  { id = "off",     label = "OFF",     colour = GRY },
  { id = "missing", label = "MISSING", colour = RED },
  { id = "new",     label = "NEW",     colour = YEL },
}

local function store_filtered()
  local f = FILTERS[filter].id
  local out = {}
  for _, p in ipairs(store_items) do
    local keep = false
    if f == "all" then keep = true
    elseif f == "ready" then keep = p.installed and not p.disabled                     
    elseif f == "off" then keep = p.installed and p.disabled
    elseif f == "missing" then keep = (not p.installed)                     
    elseif f == "new" then keep = p.is_new end
    if keep then out[#out + 1] = p end
  end
  return out
end

-- ============================================================
--  Download / install machinery (plugins)
-- ============================================================
local function dl_dir() return "data/downloads" end
local function part_path(p) return dl_dir() .. "/" .. (p.raw.wheel_name or "") .. ".part" end
local function final_path(p) return dl_dir() .. "/" .. (p.raw.wheel_name or "") end
local function progress_path(p) return dl_dir() .. "/" .. p.id .. ".progress" end
local function done_path(p) return dl_dir() .. "/" .. p.id .. ".done" end
local function script_path(p) return dl_dir() .. "/" .. p.id .. ".sh" end
local function log_path(p) return "data/plugin_logs/" .. p.id .. ".log" end

local function log_event(p, event)
  os.execute("mkdir -p data/plugin_logs")
  local f = io.open(log_path(p), "a")
  if f then f:write(os.date("%Y-%m-%d %H:%M:%S") .. "  " .. event .. "\n"); f:close() end
end

local function read_progress(p)
  local f = io.open(progress_path(p))
  if not f then return 0 end
  local line = f:read("*l") or ""
  f:close()
  local cur, tot = line:match("(%d+)|(%d+)")
  cur = tonumber(cur) or 0
  tot = tonumber(tot) or (p.raw and p.raw.wheel_size or 1)
  if tot <= 0 then return 0 end
  return math.min(0.99, cur / tot)
end

local function clean_transient(p)
  sh.exec("rm -f " .. sh.shq(part_path(p)) .. " " ..
    sh.shq(progress_path(p)) .. " " .. sh.shq(done_path(p)) .. " " ..
    sh.shq(script_path(p)))
end

local function start_download(p)
  if not p.raw or not p.raw.wheel_url then
    Notify.show("error", "no download available"); return
  end
  sh.exec("mkdir -p " .. sh.shq(dl_dir()))
  clean_transient(p)
  local f = io.open(script_path(p), "w")
  if not f then Notify.show("error", "cannot write script"); return end
  f:write("#!/bin/sh\n")
  f:write("mkdir -p " .. sh.shq(dl_dir()) .. "\n")
  f:write("curl -L --fail --silent --show-error -o " ..
    sh.shq(part_path(p)) .. " " .. sh.shq(p.raw.wheel_url) .. " &\n")
  f:write("PID=$!\n")
  f:write("while kill -0 $PID 2>/dev/null; do\n")
  f:write("  if [ -f " .. sh.shq(part_path(p)) .. " ]; then\n")
  f:write("    SZ=$(stat -c '%s' " .. sh.shq(part_path(p)) .. " 2>/dev/null)\n")
  f:write("    [ -z \"$SZ\" ] && SZ=$(wc -c < " .. sh.shq(part_path(p)) .. " 2>/dev/null)\n")
  f:write("    [ -z \"$SZ\" ] && SZ=0\n")
  f:write("  else SZ=0; fi\n")
  f:write("  echo \"$SZ|" .. (p.raw.wheel_size or 0) .. "\" > " ..
    sh.shq(progress_path(p)) .. "\n")
  f:write("  sleep 0.4\n")
  f:write("done\n")
  f:write("wait $PID\n")
  f:write("touch " .. sh.shq(done_path(p)) .. "\n")
  f:close()
  sh.exec("chmod +x " .. sh.shq(script_path(p)))
  os.execute("(setsid sh " .. sh.shq(script_path(p)) .. " </dev/null >/dev/null 2>&1 &) " ..
    "|| (nohup sh " .. sh.shq(script_path(p)) .. " >/dev/null 2>&1 &) " ..
    "|| (sh " .. sh.shq(script_path(p)) .. " >/dev/null 2>&1 &)")
  progress[p.id] = 0.01
  log_event(p, "DOWNLOAD started " .. (p.raw.wheel_name or ""))
  Notify.show("info", "download: " .. p.name)
end

local function do_install(p)
  if not p.raw or not p.raw.pkg_name or p.raw.pkg_name == "" then
    p.installed = true; return
  end
  local cmd = "python3 -m pip install --no-index --find-links=" ..
    sh.shq(p.raw.pack_dir or dl_dir()) .. " " .. p.raw.pkg_name .. " 2>&1"
  local out = sh.read(cmd) or ""
  local lf = io.open("data/plugin_logs/" .. p.id .. ".install.log", "w")
  if lf then
    lf:write("=== pip install " .. p.raw.pkg_name .. " ===\n")
    lf:write(os.date("%Y-%m-%d %H:%M:%S") .. "\n\n"); lf:write(out); lf:close()
  end
  local check = sh.read(p.raw.installed_check or "echo no")
  if check and check:find("ok", 1, true) then
    p.installed = true; clean_transient(p)
    log_event(p, "INSTALL ok " .. p.raw.pkg_name)
    Notify.show("success", p.name .. " installed")
  else
    p.installed = false
    log_event(p, "ERROR install failed: " .. out:sub(1, 120))
    Notify.show("error", p.name .. " install failed")
  end
end

local function remove_plugin(p)
  if p.raw and p.raw.pkg_name and p.raw.pkg_name ~= "" then
    sh.exec("python3 -m pip uninstall -y " .. p.raw.pkg_name .. " 2>&1")
  end
  if p.raw and p.raw.wheel_name and p.raw.wheel_name ~= "" then
    sh.exec("rm -f " .. sh.shq(final_path(p)))
  end
  clean_transient(p)
  p.installed = false
  log_event(p, "UNINSTALL " .. (p.raw and p.raw.pkg_name or p.id))
  Notify.show("info", p.name .. " removed")
end

-- ============================================================
--  TOOLS: catalog + SD apps
-- ============================================================
local TOOLS_ROOTS = {
  { label = "SD1", path = "/mnt/mmc/MUOS/application" },
  { label = "SD2", path = "/mnt/sdcard/MUOS/application" },
  { label = "RUN", path = "/run/muos/storage/application" },
}

local function app_icon_for(folder)
  local h = io.popen("ls -1 " .. sh.shq(folder .. "/glyph") .. "/*.png 2>/dev/null | head -1")
  if h then local l = h:read("*l"); h:close(); if l and l ~= "" then return l end end
  h = io.popen("find " .. sh.shq(folder) .. " -maxdepth 1 -name '*.png' 2>/dev/null | head -1")
  if h then local l = h:read("*l"); h:close(); if l and l ~= "" then return l end end
  return nil
end

local function du_kb(path)
  local h = io.popen("du -sk " .. sh.shq(path) .. " 2>/dev/null | cut -f1")
  if not h then return 0 end
  local v = tonumber(h:read("*a") or "0") or 0
  h:close()
  return v * 1024
end

local function build_tools_list()
  local out, seen = {}, {}
  -- catalog apps
  for _, app in ipairs(Cat.all_apps()) do
    local installed = false
    if app.install_path and app.install_path ~= "" then
      installed = sh.exists(app.install_path)
    end
    out[#out + 1] = {
      key          = app.key,
      name         = app.name,
      tagline      = app.tagline,
      description  = app.desc,
      version      = app.version,
      category     = app.category,
      size_kb      = app.size_kb,
      format       = app.format,
      icon         = app.icon,
      colour       = app.colour,
      features     = app.features,
      download     = app.download,
      repo         = app.repo,
      install_path = app.install_path,
      source       = "catalog",
      installed    = installed,
      date_added   = app.date_added,
      is_new       = app.new or false,
      raw          = app,
    }
    seen[app.key] = true
  end
  -- installed apps on SD cards
  for _, root in ipairs(TOOLS_ROOTS) do
    if sh.is_dir(root.path) then
      local h = io.popen("ls -1d " .. sh.shq(root.path) .. "/*/ 2>/dev/null")
      if h then
        for line in h:lines() do
          local name = line:match("([^/]+)/$")
          if name then
            local lkey = "local_" .. name:lower():gsub("[^%w]+", "_")
            if not seen[lkey] then
              out[#out + 1] = {
                key          = lkey,
                name         = name,
                tagline      = "muOS app · " .. root.label,
                description  = "Application found on " .. root.label ..
                  " at " .. root.path .. "/" .. name,
                version      = "?",
                category     = "muOS App",
                icon         = "gear",
                colour       = {0.55, 0.85, 0.45},
                source       = "local",
                installed    = true,
                local_path   = root.path .. "/" .. name,
                install_path = root.path .. "/" .. name .. "/mux_launch.sh",
                sd           = root.label,
              }
              seen[lkey] = true
            end
          end
        end
        h:close()
      end
    end
  end
  table.sort(out, function(a, b)
    if a.installed ~= b.installed then return a.installed end
    return (a.name or ""):lower() < (b.name or ""):lower()
  end)
  return out
end

local function tools_scan()
  tools_scanning = true
  tools_items = build_tools_list()
  tools_loaded = true
  tools_scanning = false
end

-- ============================================================
--  TOOLS actions
-- ============================================================
local function tools_uninstall(t)
  Modal.show("Uninstall " .. t.name,
    "Remove " .. (t.local_path or t.install_path or "?") .. "?",
    { accept_label = "UNINSTALL", cancel_label = "CANCEL",
      accept_color = RED,
      on_accept = function()
        local folder = t.local_path
        if not folder and t.install_path then
          folder = t.install_path:match("^(.*)/[^/]+$")
        end
        if folder then
          sh.exec("rm -rf " .. sh.shq(folder))
          t.installed = false
          Notify.show("warning", t.name .. " removed")
        end
      end })
end

local function tools_open(t)
  local folder = t.local_path
  if not folder and t.install_path then
    folder = t.install_path:match("^(.*)/[^/]+$")
  end
  if not folder or not sh.is_dir(folder) then
    Notify.show("warning", "install folder not found"); return
  end
  local launcher = folder .. "/mux_launch.sh"
  if not sh.exists(launcher) then
    Notify.show("warning", "mux_launch.sh not found"); return
  end
  os.execute("cd " .. sh.shq(folder) ..
    " && setsid ./mux_launch.sh </dev/null >/dev/null 2>&1 &")
  Notify.show("info", "launching " .. t.name)
end

local function tools_manage(t)
  local folder = t.local_path
  if not folder and t.install_path then
    folder = t.install_path:match("^(.*)/[^/]+$")
  end
  if not folder or not sh.is_dir(folder) then
    Notify.show("warning", "install folder not found"); return
  end
  State.app_detail_path = folder
  State.app_detail_name = t.name
  State.app_detail_icon = app_icon_for(folder)
  State.app_detail_size = du_kb(folder)
  State.app_detail_root = folder:match("^(.*)/[^/]+$") or "."
  State.go("app_detail")
end

local function tools_start_install(t)
  if not t.download or t.download == "" then
    Notify.show("error", "no download URL"); return
  end
  local DL = require("services.downloader")
  local fname = t.download:match("([^/]+)$") or (t.key .. ".muxapp")
  local id, err = DL.start(t.download, fname, t.name)
  if not id then
    Notify.show("error", err or "download failed"); return
  end
  tools_dl[id] = { item = t, filename = fname }
  Notify.show("info", "download started: " .. t.name)
end

local function tools_show_repo(t)
  local text = "Repo: " .. (t.repo or "?") .. "\n\nDownload:\n" .. (t.download or "?")
  Modal.show(t.name .. " — source", text,
    { accept_label = "OK", hide_cancel = true })
end

local function tools_actions(t)
  local acts = {}
  if t.installed then
    acts[#acts+1] = { kind = "primary", label = "OPEN", colour = GRN,
      hint = "run mux_launch.sh", act = function() tools_open(t) end }
    acts[#acts+1] = { kind = "normal", label = "MANAGE", colour = CYA,
      hint = "migrate · build muxapp · uninstall · info",
      act = function() tools_manage(t) end }
    if t.source == "catalog" then
      acts[#acts+1] = { kind = "normal", label = "REINSTALL", colour = AMB,
        hint = "re-download and overwrite",
        act = function() tools_start_install(t) end }
      acts[#acts+1] = { kind = "danger", label = "UNINSTALL", colour = RED,
        hint = "remove the install folder",
        act = function() tools_uninstall(t) end }
    end
  else
    acts[#acts+1] = { kind = "primary", label = "INSTALL", colour = GRN,
      hint = "download and unzip to " .. (t.format or ".muxapp"),
      act = function() tools_start_install(t) end }
    acts[#acts+1] = { kind = "normal", label = "DOWNLOAD ONLY", colour = AMB,
      hint = "save to data/downloads/ (no install)",
      act = function() tools_download_only(t) end }
  end
  if t.repo then
    acts[#acts+1] = { kind = "normal", label = "REPO / QR", colour = PUR,
      hint = "show repository URL",
      act = function() tools_show_repo(t) end }
  end
  return acts
end

-- ============================================================
--  Icon renderer
-- ============================================================
local function draw_plugin_icon(kind, cx, cy, r, colour, alpha)
  col(colour, alpha or 1)
  love.graphics.setLineWidth(1.8)
  if kind == "pdf" then
    love.graphics.rectangle("line", cx - r*0.6, cy - r*0.75, r*1.2, r*1.5, 2, 2)
    love.graphics.line(cx - r*0.35, cy - r*0.45, cx + r*0.35, cy - r*0.45)
    love.graphics.line(cx - r*0.35, cy - r*0.15, cx + r*0.35, cy - r*0.15)
  elseif kind == "archive" then
    love.graphics.rectangle("line", cx - r*0.75, cy - r*0.15, r*1.5, r*0.75, 2, 2)
    love.graphics.rectangle("line", cx - r*0.75, cy - r*0.55, r*1.5, r*0.35, 2, 2)
    love.graphics.rectangle("fill", cx - r*0.15, cy - r*0.15, r*0.3, r*0.35)
  elseif kind == "office" or kind == "doc" then
    love.graphics.rectangle("line", cx - r*0.6, cy - r*0.75, r*1.2, r*1.5, 2, 2)
    love.graphics.rectangle("fill", cx - r*0.4, cy + r*0.10, r*0.18, r*0.35)
    love.graphics.rectangle("fill", cx - r*0.09, cy - r*0.15, r*0.18, r*0.60)
    love.graphics.rectangle("fill", cx + r*0.22, cy - r*0.40, r*0.18, r*0.85)
  elseif kind == "web" then
    love.graphics.circle("line", cx, cy, r*0.80)
    love.graphics.ellipse("line", cx, cy, r*0.32, r*0.80)
    love.graphics.line(cx - r*0.80, cy, cx + r*0.80, cy)
  elseif kind == "media" or kind == "wave" then
    love.graphics.rectangle("line", cx - r*0.75, cy - r*0.75, r*1.5, r*1.5, 3, 3)
    love.graphics.polygon("fill",
      cx - r*0.20, cy - r*0.40, cx - r*0.20, cy + r*0.40, cx + r*0.45, cy)
  elseif kind == "comic" then
    love.graphics.rectangle("line", cx - r*0.75, cy - r*0.75, r*0.65, r*1.5, 2, 2)
    love.graphics.rectangle("line", cx + r*0.10, cy - r*0.75, r*0.65, r*1.5, 2, 2)
  elseif kind == "font" then
    love.graphics.line(cx - r*0.35, cy + r*0.35, cx - r*0.15, cy - r*0.55)
    love.graphics.line(cx - r*0.15, cy - r*0.55, cx + r*0.05, cy + r*0.35)
  elseif kind == "hex" then
    love.graphics.rectangle("line", cx - r*0.75, cy - r*0.75, r*1.5, r*1.5, 2, 2)
    for i = 0, 3 do
      love.graphics.line(cx - r*0.55, cy - r*0.55 + i * r*0.36,
        cx + r*0.55, cy - r*0.55 + i * r*0.36)
    end
  elseif kind == "magnifier" then
    love.graphics.circle("line", cx - r*0.15, cy - r*0.15, r*0.60)
    love.graphics.line(cx + r*0.28, cy + r*0.28, cx + r*0.75, cy + r*0.75)
  elseif kind == "gear" then
    for i = 0, 7 do
      local ang = i * math.pi / 4
      love.graphics.line(cx + math.cos(ang) * r*0.55, cy + math.sin(ang) * r*0.55,
                         cx + math.cos(ang) * r*0.90, cy + math.sin(ang) * r*0.90)
    end
    love.graphics.circle("line", cx, cy, r*0.55)
    love.graphics.circle("line", cx, cy, r*0.22)
  elseif kind == "eye" then
    love.graphics.ellipse("line", cx, cy, r*1.0, r*0.55)
    love.graphics.circle("fill", cx, cy, r*0.28)
  elseif kind == "planet" then
    love.graphics.circle("line", cx, cy, r*0.55)
    love.graphics.ellipse("line", cx, cy, r, r*0.35)
    love.graphics.circle("fill", cx + r*0.5, cy - r*0.3, 2)
  elseif kind == "network" then
    love.graphics.circle("line", cx, cy, r*0.28)
    for _, a in ipairs({0, math.pi/2, math.pi, -math.pi/2}) do
      local px = cx + math.cos(a) * r*0.75
      local py = cy + math.sin(a) * r*0.75
      love.graphics.circle("line", px, py, r*0.22)
    end
  elseif kind == "dolphin" then
    love.graphics.arc("line", "open", cx, cy + r*0.2, r*0.75,
      -math.pi*0.95, -math.pi*0.05)
    love.graphics.line(cx, cy + r*0.7, cx, cy + r*0.2)
  elseif kind == "minoru" then
    love.graphics.circle("line", cx, cy, r*0.75)
    love.graphics.line(cx - r*0.4, cy, cx + r*0.4, cy)
  else
    love.graphics.circle("line", cx, cy, r*0.75)
    love.graphics.line(cx, cy - r*0.4, cx, cy + r*0.4)
    love.graphics.line(cx - r*0.4, cy, cx + r*0.4, cy)
  end
  love.graphics.setLineWidth(1)
end

-- ============================================================
--  Common widgets
-- ============================================================
local function draw_status_pill(x_right, cy, label, colour, small)
  local f = A.font(A.FONT_MONO, small and 8 or 9)
  love.graphics.setFont(f)
  local pw = f:getWidth(label) + (small and 16 or 20)
  local ph = small and 16 or 18
  local bx = x_right - pw
  local by = cy - ph / 2
  col({colour[1]*0.20, colour[2]*0.20, colour[3]*0.20}, 0.95)
  love.graphics.rectangle("fill", bx, by, pw, ph, ph/2, ph/2)
  col(colour, 0.9)
  love.graphics.setLineWidth(1)
  love.graphics.rectangle("line", bx + 0.5, by + 0.5, pw - 1, ph - 1, ph/2, ph/2)
  love.graphics.setLineWidth(1)
  col(colour, 1)
  love.graphics.circle("fill", bx + (small and 7 or 8), by + ph/2, small and 2 or 2.5)
  col({1, 1, 1}, 1)
  love.graphics.printf(label, bx + (small and 11 or 13),
    by + (small and 4 or 5), pw - (small and 13 or 15), "left")
end

local function draw_tab_bar(x, y, w)
  local tab_h = 34
  local gap = 6
  local tw = (w - (NTAB - 1) * gap) / NTAB
  for i, tb in ipairs(TABS) do
    local tx = x + (i - 1) * (tw + gap)
    local active = (i == tab)
    local c = tb.accent
    local c_hi = tb.accent_hi
    if active then
      col({c[1]*0.18, c[2]*0.18, c[3]*0.18}, 0.98)
      love.graphics.rectangle("fill", tx, y, tw, tab_h, 4, 4)
      col(c_hi, 0.95)
      love.graphics.setLineWidth(1.8)
      love.graphics.rectangle("line", tx + 0.5, y + 0.5, tw - 1, tab_h - 1, 4, 4)
      love.graphics.setLineWidth(1)
      col(c_hi, 1)
      love.graphics.rectangle("fill", tx + 8, y + tab_h - 3, tw - 16, 3, 1, 1)
      D.corner_ticks(tx + 6, y + 6, tw - 12, tab_h - 12, 8, c_hi, 0.8)
    else
      col({0.028, 0.026, 0.030}, 0.75)
      love.graphics.rectangle("fill", tx, y, tw, tab_h, 4, 4)
      col(c, 0.28)
      love.graphics.rectangle("line", tx + 0.5, y + 0.5, tw - 1, tab_h - 1, 4, 4)
    end
    love.graphics.setFont(A.font(A.FONT_BODY_BOLD, active and 13 or 12))
    col(active and {1, 1, 1} or {0.65, 0.68, 0.72}, 1)
    love.graphics.printf(tb.label, tx, y + 9, tw, "center")
  end
end

-- ============================================================
--  LAUNCH
-- ============================================================
local function launch_move(d)
  local n = #launch_list
  if n == 0 then return end
  sel[1] = sel[1] + d
  if sel[1] < 1 then sel[1] = n end
  if sel[1] > n then sel[1] = 1 end
end

local function launch_activate()
  local p = launch_list[sel[1]]
  if not p then return end
  local ok, SFX = pcall(require, "core.audio")
  if ok then SFX.play("enter") end
  State.go(p.screen)
end

local function draw_launch()
  local th = State.theme
  local acc, acc_hi = TABS[1].accent, TABS[1].accent_hi

  -- info strip
  love.graphics.setFont(A.font(A.FONT_MONO, 10))
  col(acc, 0.85)
  love.graphics.print("LAUNCH  //  " .. #launch_list .. " ready", 16, INFO_Y)

  local vp_y = CONTENT_Y
  local vp_h = H - Frame.BOTTOM_H - vp_y - 6

  if #launch_list == 0 then
    col(th.text_dim, 0.8)
    love.graphics.setFont(A.font(A.FONT_BODY, 13))
    love.graphics.printf("No plugins ready to launch.",
      W/2 - 200, vp_y + vp_h/2 - 30, 400, "center")
    love.graphics.setFont(A.font(A.FONT_MONO, 10))
    col(acc, 0.7)
    love.graphics.printf("Open the STORE tab to install plugins,\nor enable a disabled one.",
      W/2 - 200, vp_y + vp_h/2, 400, "center")
    return
  end

  local row_h = 70
  local row_step = row_h + 6
  local total_h = #launch_list * row_step
  local max_scroll = math.max(0, total_h - vp_h)
  local sel_top = (sel[1] - 1) * row_step
  local sel_bot = sel_top + row_h
  if sel_top - 8 < scroll[1] then scroll[1] = math.max(0, sel_top - 8) end
  if sel_bot + 8 > scroll[1] + vp_h then
    scroll[1] = math.min(max_scroll, sel_bot + 8 - vp_h)
  end
  scroll[1] = math.max(0, math.min(max_scroll, scroll[1]))

  love.graphics.setScissor(16, vp_y, W - 32, vp_h)
  local y = vp_y - scroll[1]
  for i, p in ipairs(launch_list) do
    local focused = (i == sel[1])
    local c = p.colour
    local x = 16
    local w = W - 32
    if focused then
      col({c[1]*0.14, c[2]*0.14, c[3]*0.14}, 0.95)
      love.graphics.rectangle("fill", x, y, w, row_h, 5, 5)
      col(c, 0.95)
      love.graphics.setLineWidth(1.8)
      love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, row_h - 1, 5, 5)
      love.graphics.setLineWidth(1)
      col(c, 1)
      love.graphics.rectangle("fill", x, y + 10, 3, row_h - 20)
      D.corner_ticks(x + 8, y + 8, w - 16, row_h - 16, 10, c, 0.9)
    else
      col({0.028, 0.024, 0.030}, 0.85)
      love.graphics.rectangle("fill", x, y, w, row_h, 5, 5)
      col(c, 0.28)
      love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, row_h - 1, 5, 5)
    end
    local icx, icy, ir = x + 42, y + row_h/2, 24
    col({c[1]*0.20, c[2]*0.20, c[3]*0.20}, 0.95)
    love.graphics.circle("fill", icx, icy, ir)
    col(c, focused and 0.95 or 0.6)
    love.graphics.setLineWidth(focused and 1.6 or 1.2)
    love.graphics.circle("line", icx, icy, ir)
    love.graphics.setLineWidth(1)
    draw_plugin_icon(p.icon, icx, icy, ir * 0.55, c, focused and 1 or 0.8)

    love.graphics.setFont(A.font(A.FONT_BODY_BOLD, focused and 15 or 14))
    col(focused and {1, 1, 1} or th.text, 1)
    local nm = p.name or p.key
    if #nm > 28 then nm = nm:sub(1, 27) .. "." end
    love.graphics.print(nm, x + 82, y + 12)

    love.graphics.setFont(A.font(A.FONT_BODY, 10))
    col(th.text_dim, 0.85)
    local tg = p.tagline or ""
    if #tg > 56 then tg = tg:sub(1, 55) .. "..." end
    love.graphics.print(tg, x + 82, y + 32)

    love.graphics.setFont(A.font(A.FONT_MONO, 9))
    col(c, focused and 0.85 or 0.55)
    love.graphics.print("v" .. (p.version or "?"), x + 82, y + 50)

    if p.is_new then
      local f = A.font(A.FONT_MONO, 8)
      love.graphics.setFont(f)
      local bw = f:getWidth("NEW") + 12
      col(YEL, 0.9)
      love.graphics.rectangle("fill", x + 130, y + 50, bw, 12, 6, 6)
      col({0, 0, 0}, 1)
      love.graphics.printf("NEW", x + 130, y + 52, bw, "center")
    end

    if focused then
      local pulse = 0.65 + 0.35 * math.sin(t_global * 5)
      col(acc_hi, 0.6 + pulse * 0.4)
      love.graphics.setLineWidth(2.4)
      local cx, cy = x + w - 22, y + row_h/2
      love.graphics.line(cx - 6, cy - 7, cx + 2, cy, cx - 6, cy + 7)
      love.graphics.setLineWidth(1)
    end
    y = y + row_step
  end
  love.graphics.setScissor()

  if max_scroll > 0 then
    local track_h = vp_h - 4
    local thumb_h = math.max(24, track_h * (vp_h / total_h))
    local denom = math.max(1, total_h - vp_h)
    local thumb_y = vp_y + 2 + (track_h - thumb_h) * (scroll[1] / denom)
    col(acc, 0.55)
    love.graphics.rectangle("fill", W - 6, thumb_y, 3, thumb_h, 1, 1)
  end
end

-- ============================================================
--  STORE
-- ============================================================
local function store_reload()
  store_items = build_store_list()
  store_loaded = true
end

local function store_current_list() return store_filtered() end
local function store_current_item() return store_current_list()[sel[2]] end

local function store_move(d)
  local n = #store_current_list()
  if n == 0 then return end
  sel[2] = sel[2] + d
  if sel[2] < 1 then sel[2] = n end
  if sel[2] > n then sel[2] = 1 end
end

local function store_change_filter(d)
  filter = filter + d
  if filter < 1 then filter = #FILTERS end
  if filter > #FILTERS then filter = 1 end
  sel[2] = 1; scroll[2] = 0
end

local function store_detail_actions(p)
  local acts = {}
  if p.source == "local" or p.installed then
    acts[#acts+1] = {
      kind = "toggle",
      label = "Plugin activation",
      hint = p.disabled
        and "OFF - press A to ENABLE"
        or  "ON - press A to DISABLE",
      colour = p.disabled and GRN or AMB,
      act = function()
        local now_off = PR.toggle(p.id)
        p.disabled = now_off
        log_event(p, now_off and "STATE disabled" or "STATE enabled")
        Notify.show("info", p.name .. (now_off and " disabled" or " enabled"))
      end,
    }
  end
  if not p.builtin and not p.installed then
    acts[#acts+1] = { kind = "primary", label = "INSTALL",
      hint = "download and install from catalog", colour = GRN,
      act = function() start_download(p) end }
  end
  if not p.builtin and p.installed then
    acts[#acts+1] = { kind = "normal", label = "REINSTALL",
      hint = "remove and re-download", colour = AMB,
      act = function()
        Modal.show("Reinstall " .. p.name, "Remove and download again?",
          { accept_label = "REINSTALL", cancel_label = "CANCEL",
            accept_color = AMB,
            on_accept = function() remove_plugin(p); start_download(p) end })
      end }
    acts[#acts+1] = { kind = "danger", label = "UNINSTALL",
      hint = "remove from the system", colour = RED,
      act = function()
        Modal.show("Uninstall " .. p.name, "Remove definitively?",
          { accept_label = "UNINSTALL", cancel_label = "CANCEL",
            accept_color = RED,
            on_accept = function() remove_plugin(p) end })
      end }
  end
  if p.source == "local" then
    local man = Loader.get(p.id)
    if man and man.manage_key then
      acts[#acts+1] = { kind = "normal", label = "PERMISSIONS",
        hint = "review what this plugin can access", colour = YEL,
        act = function() State.go(man.manage_key) end }
    end
  end
  if p.screen and p.installed and not p.disabled and not NO_OPEN[p.id] then
    acts[#acts+1] = { kind = "primary", label = "OPEN",
      hint = "run this plugin now", colour = CYA,
      act = function() State.go(p.screen) end }
  end
  if p.source == "local" then
    acts[#acts+1] = { kind = "normal", label = "VIEW LOG",
      hint = "recent events for this plugin", colour = PUR,
      act = function()
        local lines = {}
        local f = io.open(log_path(p), "r")
        if f then for line in f:lines() do lines[#lines+1] = line end; f:close() end
        if #lines == 0 then lines = { "(no events yet)" } end
        local start = math.max(1, #lines - 15)
        local show = {}
        for i = start, #lines do show[#show+1] = lines[i] end
        Modal.show("Log: " .. p.name, table.concat(show, "\n"),
          { accept_label = "OK", hide_cancel = true })
      end }
  end
  return acts
end

local function store_activate()
  local p = store_current_item()
  if not p then return end
  view[2] = "detail"
  detail_sel[2]    = 1
  detail_scroll[2] = 0
end

-- Split actions: 1 optional toggle + list of other actions
local function detail_split_actions(p)
  local acts = store_detail_actions(p)
  local toggle_act = nil
  local others = {}
  for _, a in ipairs(acts) do
    if a.kind == "toggle" and not toggle_act then
      toggle_act = a
    else
      others[#others + 1] = a
    end
  end
  return toggle_act, others
end

local function detail_item_count()
  local p = store_current_item()
  if not p then return 1 end
  local _, others = detail_split_actions(p)
  return 1 + #others
end

local function jump_plugin(d)
  local n = #store_current_list()
  if n == 0 then return end
  sel[2] = sel[2] + d
  if sel[2] < 1 then sel[2] = n end
  if sel[2] > n then sel[2] = 1 end
end

local function store_detail_move(d)
  local n = detail_item_count()
  if n <= 0 then return end
  detail_sel[2] = detail_sel[2] + d
  if detail_sel[2] < 1 then detail_sel[2] = n end
  if detail_sel[2] > n then detail_sel[2] = 1 end
end

local function store_detail_activate()
  local p = store_current_item()
  if not p then return end
  local toggle_act, others = detail_split_actions(p)
  local s = detail_sel[2]
  if s == 1 then
    if toggle_act and toggle_act.act then
      toggle_act.act()
    elseif not p.installed then
      Notify.show("warning", "install the plugin first")
    end
  else
    local a = others[s - 1]
    if a and a.act then a.act() end
  end
end

local function draw_store_list()
  local th = State.theme
  local acc, acc_hi = TABS[2].accent, TABS[2].accent_hi

  love.graphics.setFont(A.font(A.FONT_MONO, 10))
  col(acc, 0.85)
  love.graphics.print("MINORU STORE  //  " .. #store_items .. " items", 16, INFO_Y)

  -- filter pills
  local fp_y = CONTENT_Y
  local ph = 22
  local gap = 4
  local pw = (W - 32 - gap * (#FILTERS - 1)) / #FILTERS
  for i, flt in ipairs(FILTERS) do
    local fx = 16 + (i - 1) * (pw + gap)
    local active = (i == filter)
    local c = flt.colour
    if active then
      col({c[1]*0.22, c[2]*0.22, c[3]*0.22}, 0.95)
      love.graphics.rectangle("fill", fx, fp_y, pw, ph, 4, 4)
      col(c, 0.95)
      love.graphics.setLineWidth(1.4)
      love.graphics.rectangle("line", fx + 0.5, fp_y + 0.5, pw - 1, ph - 1, 4, 4)
      love.graphics.setLineWidth(1)
      col(c, 1)
      love.graphics.rectangle("fill", fx + 4, fp_y + ph - 3, pw - 8, 2)
    else
      col({0.030, 0.028, 0.032}, 0.7)
      love.graphics.rectangle("fill", fx, fp_y, pw, ph, 4, 4)
      col(c, 0.30)
      love.graphics.rectangle("line", fx + 0.5, fp_y + 0.5, pw - 1, ph - 1, 4, 4)
    end
    love.graphics.setFont(A.font(A.FONT_BODY_BOLD, 10))
    col(active and {1, 1, 1} or {0.65, 0.68, 0.72}, 1)
    love.graphics.printf(flt.label, fx, fp_y + 5, pw, "center")
  end

  local vp_y = fp_y + ph + 4
  local vp_h = H - Frame.BOTTOM_H - vp_y - 6
  local list = store_current_list()

  if #list == 0 then
    col(th.text_dim, 0.75)
    love.graphics.setFont(A.font(A.FONT_BODY, 12))
    love.graphics.printf("no items in this filter",
      W/2 - 200, vp_y + vp_h/2, 400, "center")
    return
  end

  local row_h = 56
  local row_step = row_h + 4
  local total_h = #list * row_step
  local max_scroll = math.max(0, total_h - vp_h)
  local sel_top = (sel[2] - 1) * row_step
  local sel_bot = sel_top + row_h
  if sel_top - 6 < scroll[2] then scroll[2] = math.max(0, sel_top - 6) end
  if sel_bot + 6 > scroll[2] + vp_h then
    scroll[2] = math.min(max_scroll, sel_bot + 6 - vp_h)
  end
  scroll[2] = math.max(0, math.min(max_scroll, scroll[2]))

  love.graphics.setScissor(16, vp_y, W - 32, vp_h)
  local y = vp_y - scroll[2]
  for i, p in ipairs(list) do
    local focused = (i == sel[2])
    local c = p.colour
    local x = 16
    local w = W - 32
    if focused then
      col({c[1]*0.15, c[2]*0.15, c[3]*0.15}, 0.95)
      love.graphics.rectangle("fill", x, y, w, row_h, 4, 4)
      col(c, 0.95)
      love.graphics.setLineWidth(1.7)
      love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, row_h - 1, 4, 4)
      love.graphics.setLineWidth(1)
      col(c, 1)
      love.graphics.rectangle("fill", x, y + 8, 3, row_h - 16)
      D.corner_ticks(x + 6, y + 6, w - 12, row_h - 12, 8, c, 0.85)
    else
      col({0.028, 0.026, 0.032}, 0.85)
      love.graphics.rectangle("fill", x, y, w, row_h, 4, 4)
      col(c, 0.25)
      love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, row_h - 1, 4, 4)
    end

    local icx, icy, ir = x + 32, y + row_h/2, 18
    col({c[1]*0.20, c[2]*0.20, c[3]*0.20}, 0.95)
    love.graphics.circle("fill", icx, icy, ir)
    col(c, focused and 0.95 or 0.55)
    love.graphics.setLineWidth(focused and 1.5 or 1.1)
    love.graphics.circle("line", icx, icy, ir)
    love.graphics.setLineWidth(1)
    draw_plugin_icon(p.icon, icx, icy, ir * 0.55, c, focused and 1 or 0.7)

    love.graphics.setFont(A.font(A.FONT_BODY_BOLD, focused and 13 or 12))
    col(focused and {1,1,1} or th.text, 1)
    local nm = p.name or p.id
    if #nm > 30 then nm = nm:sub(1, 29) .. "." end
    love.graphics.print(nm, x + 62, y + 8)

    love.graphics.setFont(A.font(A.FONT_BODY, 9))
    col(th.text_dim, 0.82)
    local tg = p.tagline or ""
    if #tg > 52 then tg = tg:sub(1, 51) .. "..." end
    love.graphics.print(tg, x + 62, y + 26)

    love.graphics.setFont(A.font(A.FONT_MONO, 8))
    col(c, 0.65)
    love.graphics.print((p.source or "?"):upper() .. "  v" .. (p.version or "?"),
      x + 62, y + 42)

    local st = status_of(p)
    draw_status_pill(x + w - 10, y + row_h/2, st.label, st.colour)
    y = y + row_step
  end
  love.graphics.setScissor()

  if max_scroll > 0 then
    local track_h = vp_h - 4
    local thumb_h = math.max(20, track_h * (vp_h / total_h))
    local denom = math.max(1, total_h - vp_h)
    local thumb_y = vp_y + 2 + (track_h - thumb_h) * (scroll[2] / denom)
    col(acc, 0.55)
    love.graphics.rectangle("fill", W - 6, thumb_y, 3, thumb_h, 1, 1)
  end
end

-- ============================================================
--  Detail (unified single-scroll view)
-- ============================================================
local function info_block_height(content, w_block)
  if not content or content == "" then return 0 end
  local f = A.font(A.FONT_BODY, 11)
  local ih = _wrap_h(f, content, w_block - 20)
  return math.max(40, ih + 32)
end

local function draw_info_block(x, yy, w_block, bh, title, content, colour, th, acc)
  if not content or content == "" or bh <= 0 then return end
  col({0.028, 0.024, 0.032}, 0.9)
  love.graphics.rectangle("fill", x, yy, w_block, bh, 4, 4)
  col(colour or acc, 0.45)
  love.graphics.rectangle("line", x + 0.5, yy + 0.5, w_block - 1, bh - 1, 4, 4)
  love.graphics.setFont(A.font(A.FONT_MONO, 9))
  col(colour or acc, 0.9)
  love.graphics.print(title, x + 10, yy + 6)
  col(colour or acc, 0.3)
  love.graphics.rectangle("fill", x + 10, yy + 20, w_block - 20, 1)
  love.graphics.setFont(A.font(A.FONT_BODY, 11))
  col(th.text, 0.95)
  love.graphics.printf(content, x + 10, yy + 26, w_block - 20, "left")
end

local function draw_store_detail()
  local th = State.theme
  local acc = TABS[2].accent
  local p = store_current_item()
  if not p then view[2] = "list"; return end
  local c = p.colour or acc

  local X = 16
  local Wc = W - 32

  -- Status
  local on = p.installed and not p.disabled
  local status_label, status_colour
  if not p.installed then
    status_label, status_colour = "NOT INSTALLED", RED
  elseif p.disabled then
    status_label, status_colour = "DISABLED", RED
  else
    status_label, status_colour = "ENABLED", GRN
  end

  local toggle_act, other_acts = detail_split_actions(p)

  local desc_txt = p.description or p.tagline or ""
  local feat_txt = ""
  if p.features and #p.features > 0 then
    feat_txt = "\226\128\162 " .. table.concat(p.features, "\n\226\128\162 ")
  end
  local req_txt = ""
  if p.dependencies and #p.dependencies > 0 then
    req_txt = table.concat(p.dependencies, "  \194\183  ")
  end

  local desc_h = info_block_height(desc_txt, Wc)
  local feat_h = info_block_height(feat_txt, Wc)
  local req_h  = info_block_height(req_txt,  Wc)
  if desc_h > 0 then desc_h = desc_h + 8 end
  if feat_h > 0 then feat_h = feat_h + 8 end
  if req_h  > 0 then req_h  = req_h  + 8 end

  -- Log lines
  local log_lines = {}
  do
    local f = io.open(log_path(p), "r")
    if f then
      for line in f:lines() do log_lines[#log_lines + 1] = line end
      f:close()
    end
  end
  local LOG_VISIBLE_MAX = 12
  local log_visible = math.min(#log_lines, LOG_VISIBLE_MAX)
  local log_h = math.max(70, 30 + log_visible * 12)

  local HERO_H = 84
  local ACTBOX_H = 56
  local ACTION_ROW_H = 42
  local GAP = 8

  local actions_block_h = 0
  if #other_acts > 0 then
    actions_block_h = 24 + #other_acts * ACTION_ROW_H + 4
  end

  local total_h = HERO_H + GAP + ACTBOX_H + GAP
                + desc_h + feat_h + req_h
                + actions_block_h + (actions_block_h > 0 and GAP or 0)
                + log_h + GAP

  local vp_y = CONTENT_Y
  local vp_h = H - Frame.BOTTOM_H - vp_y - 6
  local max_scroll = math.max(0, total_h - vp_h)
  if detail_scroll[2] > max_scroll then detail_scroll[2] = max_scroll end
  if detail_scroll[2] < 0 then detail_scroll[2] = 0 end

  local y_hero_abs    = 0
  local y_actbox_abs  = y_hero_abs + HERO_H + GAP
  local y_info_abs    = y_actbox_abs + ACTBOX_H + GAP
  local y_actions_abs = y_info_abs + desc_h + feat_h + req_h
  local y_log_abs     = y_actions_abs + actions_block_h
                        + (actions_block_h > 0 and GAP or 0)

  -- Follow selection
  local s = detail_sel[2]
  local focus_y_abs, focus_h
  if s == 1 then
    focus_y_abs = y_actbox_abs
    focus_h = ACTBOX_H
  else
    focus_y_abs = y_actions_abs + 24 + (s - 2) * ACTION_ROW_H
    focus_h = ACTION_ROW_H
  end
  local margin = 10
  if focus_y_abs - margin < detail_scroll[2] then
    detail_scroll[2] = math.max(0, focus_y_abs - margin)
  end
  if focus_y_abs + focus_h + margin > detail_scroll[2] + vp_h then
    detail_scroll[2] = math.min(max_scroll, focus_y_abs + focus_h + margin - vp_h)
  end

  local y_hero    = vp_y + y_hero_abs    - detail_scroll[2]
  local y_actbox  = vp_y + y_actbox_abs  - detail_scroll[2]
  local y_info    = vp_y + y_info_abs    - detail_scroll[2]
  local y_actions = vp_y + y_actions_abs - detail_scroll[2]
  local y_log     = vp_y + y_log_abs     - detail_scroll[2]

  love.graphics.setScissor(X - 4, vp_y, Wc + 8, vp_h)

  -- ===== HERO =====
  col({c[1]*0.12, c[2]*0.12, c[3]*0.12}, 0.95)
  love.graphics.rectangle("fill", X, y_hero, Wc, HERO_H, 5, 5)
  col(c, 0.9)
  love.graphics.setLineWidth(1.8)
  love.graphics.rectangle("line", X + 0.5, y_hero + 0.5, Wc - 1, HERO_H - 1, 5, 5)
  love.graphics.setLineWidth(1)
  D.corner_ticks(X + 8, y_hero + 8, Wc - 16, HERO_H - 16, 12, c, 0.9)

  local icx = X + 44
  local icy = y_hero + HERO_H / 2
  col({c[1]*0.22, c[2]*0.22, c[3]*0.22}, 0.95)
  love.graphics.circle("fill", icx, icy, 26)
  col(c, 0.95)
  love.graphics.circle("line", icx, icy, 26)
  draw_plugin_icon(p.icon or "plug", icx, icy, 18, c, 1)

  love.graphics.setFont(A.font(A.FONT_TITLE, 16))
  col(c, 1)
  local nm = p.name or p.id
  if #nm > 32 then nm = nm:sub(1, 31) .. "." end
  love.graphics.print(nm, X + 84, y_hero + 10)

  love.graphics.setFont(A.font(A.FONT_MONO, 9))
  col(c, 0.8)
  love.graphics.print("v" .. (p.version or "?") .. "  \194\183  " ..
    (p.author or "?") .. "  \194\183  " .. (p.source or "?"),
    X + 84, y_hero + 32)

  love.graphics.setFont(A.font(A.FONT_BODY, 10))
  col(th.text, 0.9)
  local tg = p.tagline or ""
  if #tg > 52 then tg = tg:sub(1, 51) .. "." end
  love.graphics.print(tg, X + 84, y_hero + 50)

  -- ===== ACTIVATION BOX =====
  local f1 = (s == 1)
  if f1 then
    col({status_colour[1]*0.15, status_colour[2]*0.15, status_colour[3]*0.15}, 0.95)
    love.graphics.rectangle("fill", X, y_actbox, Wc, ACTBOX_H, 5, 5)
    col(status_colour, 0.95)
    love.graphics.setLineWidth(1.8)
    love.graphics.rectangle("line", X + 0.5, y_actbox + 0.5,
      Wc - 1, ACTBOX_H - 1, 5, 5)
    love.graphics.setLineWidth(1)
    col(status_colour, 1)
    love.graphics.rectangle("fill", X, y_actbox + 8, 3, ACTBOX_H - 16)
    D.corner_ticks(X + 8, y_actbox + 8, Wc - 16, ACTBOX_H - 16, 10,
      status_colour, 0.9)
  else
    col({0.030, 0.026, 0.030}, 0.9)
    love.graphics.rectangle("fill", X, y_actbox, Wc, ACTBOX_H, 5, 5)
    col(status_colour, 0.35)
    love.graphics.rectangle("line", X + 0.5, y_actbox + 0.5,
      Wc - 1, ACTBOX_H - 1, 5, 5)
  end

  love.graphics.setFont(A.font(A.FONT_BODY_BOLD, 13))
  col(f1 and {1,1,1} or th.text, 1)
  love.graphics.print("Plugin activation", X + 16, y_actbox + 8)

  love.graphics.setFont(A.font(A.FONT_BODY, 9))
  col(th.text_dim, 0.85)
  local hint
  if not p.installed then
    hint = "install the plugin to activate"
  elseif p.disabled then
    hint = "OFF - press A to ENABLE"
  else
    hint = "ON - press A to DISABLE"
  end
  love.graphics.print(hint, X + 16, y_actbox + 28)

  -- Status text
  love.graphics.setFont(A.font(A.FONT_BODY_BOLD, 12))
  col(status_colour, 1)
  love.graphics.printf(status_label, X + Wc - 200, y_actbox + 19, 90, "right")

  -- Switch
  local sw_w, sw_h = 56, 28
  local sw_x = X + Wc - sw_w - 16
  local sw_y = y_actbox + (ACTBOX_H - sw_h) / 2
  col({0.05, 0.06, 0.08}, 1)
  love.graphics.rectangle("fill", sw_x, sw_y, sw_w, sw_h, sw_h/2, sw_h/2)
  local fill_w = (sw_w - 4) * (on and 1 or 0.55)
  col({status_colour[1]*0.55, status_colour[2]*0.55, status_colour[3]*0.55}, 0.9)
  love.graphics.rectangle("fill", sw_x + 2, sw_y + 2, fill_w, sw_h - 4,
    (sw_h-4)/2, (sw_h-4)/2)
  col(status_colour, 0.9)
  love.graphics.setLineWidth(1.5)
  love.graphics.rectangle("line", sw_x + 0.5, sw_y + 0.5,
    sw_w - 1, sw_h - 1, sw_h/2, sw_h/2)
  love.graphics.setLineWidth(1)
  local kr = sw_h/2 - 3
  local kx = on and (sw_x + sw_w - sw_h/2) or (sw_x + sw_h/2)
  local ky = sw_y + sw_h/2
  col({0,0,0}, 0.5)
  love.graphics.circle("fill", kx+1, ky+2, kr)
  col({0.96, 0.96, 0.97}, 1)
  love.graphics.circle("fill", kx, ky, kr)

  -- ===== INFO BLOCKS =====
  local yb = y_info
  if desc_h > 0 then
    draw_info_block(X, yb, Wc, desc_h - 8, "DESCRIPTION", desc_txt, acc, th, acc)
    yb = yb + desc_h
  end
  if feat_h > 0 then
    draw_info_block(X, yb, Wc, feat_h - 8, "FEATURES", feat_txt, GRN, th, acc)
    yb = yb + feat_h
  end
  if req_h > 0 then
    draw_info_block(X, yb, Wc, req_h - 8, "REQUIRES", req_txt, AMB, th, acc)
    yb = yb + req_h
  end

  -- ===== ACTIONS =====
  if #other_acts > 0 then
    love.graphics.setFont(A.font(A.FONT_MONO, 10))
    col(acc, 0.9)
    love.graphics.print("ACTIONS", X + 6, y_actions + 4)
    col(acc, 0.3)
    love.graphics.rectangle("fill", X + 6, y_actions + 18, Wc - 12, 1)

    for i, a in ipairs(other_acts) do
      local ry = y_actions + 24 + (i - 1) * ACTION_ROW_H
      local focused = (s == i + 1)
      local ac = a.colour or acc
      local rx = X + 6
      local rw = Wc - 12
      local rh = ACTION_ROW_H - 4

      if focused then
        col({ac[1]*0.18, ac[2]*0.18, ac[3]*0.18}, 0.95)
        love.graphics.rectangle("fill", rx, ry, rw, rh, 4, 4)
        col(ac, 0.95)
        love.graphics.setLineWidth(1.6)
        love.graphics.rectangle("line", rx + 0.5, ry + 0.5, rw - 1, rh - 1, 4, 4)
        love.graphics.setLineWidth(1)
        col(ac, 1)
        love.graphics.rectangle("fill", rx, ry + 6, 3, rh - 12)
      else
        col({0.028, 0.026, 0.030}, 0.85)
        love.graphics.rectangle("fill", rx, ry, rw, rh, 4, 4)
        col(ac, 0.25)
        love.graphics.rectangle("line", rx + 0.5, ry + 0.5, rw - 1, rh - 1, 4, 4)
      end

      love.graphics.setFont(A.font(A.FONT_BODY_BOLD, 12))
      col(focused and {1,1,1} or th.text, 1)
      love.graphics.print(a.label, rx + 14, ry + 4)

      love.graphics.setFont(A.font(A.FONT_BODY, 9))
      col(th.text_dim, 0.8)
      local hint2 = a.hint or ""
      if #hint2 > 52 then hint2 = hint2:sub(1, 51) .. "..." end
      love.graphics.print(hint2, rx + 14, ry + 22)

      if focused then
        col(ac, 0.9)
        love.graphics.setLineWidth(2)
        love.graphics.line(rx + rw - 20, ry + rh/2 - 6,
                           rx + rw - 12, ry + rh/2,
                           rx + rw - 20, ry + rh/2 + 6)
        love.graphics.setLineWidth(1)
      end
    end
  end

  -- ===== LOG =====
  col({0.028, 0.024, 0.032}, 0.9)
  love.graphics.rectangle("fill", X, y_log, Wc, log_h, 4, 4)
  col(acc, 0.45)
  love.graphics.rectangle("line", X + 0.5, y_log + 0.5, Wc - 1, log_h - 1, 4, 4)
  love.graphics.setFont(A.font(A.FONT_MONO, 9))
  col(acc, 0.9)
  love.graphics.print("LOG / HISTORY", X + 12, y_log + 6)
  col(acc, 0.3)
  love.graphics.rectangle("fill", X + 12, y_log + 20, Wc - 24, 1)

  love.graphics.setFont(A.font(A.FONT_MONO, 9))
  if #log_lines == 0 then
    col(th.text_dim, 0.7)
    love.graphics.print("(no events yet)", X + 14, y_log + 28)
  else
    local first = math.max(1, #log_lines - log_visible + 1)
    local yy = y_log + 26
    for i = first, #log_lines do
      local line = log_lines[i] or ""
      local cc = th.text
      if line:find("ERROR", 1, true) then cc = RED
      elseif line:find("STATE enabled", 1, true) then cc = GRN
      elseif line:find("STATE disabled", 1, true) then cc = AMB
      elseif line:find("DOWNLOAD", 1, true) then cc = CYA
      elseif line:find("INSTALL", 1, true) then cc = GRN
      elseif line:find("UNINSTALL", 1, true) then cc = RED
      end
      col(cc, 0.9)
      love.graphics.print(line:sub(1, 76), X + 14, yy)
      yy = yy + 12
    end
  end

  love.graphics.setScissor()

  -- Scrollbar
  if max_scroll > 0 then
    local track_h = vp_h - 8
    local thumb_h = math.max(20, track_h * (vp_h / (vp_h + max_scroll)))
    local thumb_y = vp_y + 4 + (track_h - thumb_h) * (detail_scroll[2] / max_scroll)
    col(acc, 0.55)
    love.graphics.rectangle("fill", W - 6, thumb_y, 3, thumb_h, 1, 1)
  end

  Frame.draw_top("FGD", "plugins")
  Frame.draw_bottom({
    { key = "l1",  label = "Prev" },
    { key = "r1",  label = "Next" },
    { key = "up",  label = "Move" },
    { key = "a",   label = "Run" },
    { key = "b",   label = "Back" },
  })
end

local function draw_store()
  if view[2] == "detail" then draw_store_detail() else draw_store_list() end
end

-- ============================================================
--  TOOLS
-- ============================================================
local function tools_move(d)
  local n = #tools_items
  if n == 0 then return end
  sel[3] = sel[3] + d
  if sel[3] < 1 then sel[3] = n end
  if sel[3] > n then sel[3] = 1 end
end

local function tools_activate()
  local t = tools_items[sel[3]]
  if not t then return end
  view[3] = "detail"
  detail_sel[3]    = 1
  detail_scroll[3] = 0
end

local function tools_split_actions(t)
  local acts = tools_actions(t)
  local primary_act = nil
  local others = {}
  for _, a in ipairs(acts) do
    if a.kind == "primary" and not primary_act then
      primary_act = a
    else
      others[#others + 1] = a
    end
  end
  return primary_act, others
end

local function tools_item_count()
  local t = tools_items[sel[3]]
  if not t then return 1 end
  local _, others = tools_split_actions(t)
  return 1 + #others
end

local function tools_jump(d)
  local n = #tools_items
  if n == 0 then return end
  sel[3] = sel[3] + d
  if sel[3] < 1 then sel[3] = n end
  if sel[3] > n then sel[3] = 1 end
end

local function tools_detail_move(d)
  local n = tools_item_count()
  if n <= 0 then return end
  detail_sel[3] = detail_sel[3] + d
  if detail_sel[3] < 1 then detail_sel[3] = n end
  if detail_sel[3] > n then detail_sel[3] = 1 end
end

local function tools_detail_activate()
  local t = tools_items[sel[3]]
  if not t then return end
  local primary_act, others = tools_split_actions(t)
  local s = detail_sel[3]
  if s == 1 then
    if primary_act and primary_act.act then primary_act.act() end
  else
    local a = others[s - 1]
    if a and a.act then a.act() end
  end
end

local function draw_tools_list()
  local th = State.theme
  local acc, acc_hi = TABS[3].accent, TABS[3].accent_hi

  love.graphics.setFont(A.font(A.FONT_MONO, 10))
  col(acc, 0.85)
  love.graphics.print("EXTERNAL TOOLS  //  " .. #tools_items .. " apps", 16, INFO_Y)
  love.graphics.setFont(A.font(A.FONT_BODY, 10))
  col(th.text_dim, 0.7)

  local vp_y = CONTENT_Y
  local vp_h = H - Frame.BOTTOM_H - vp_y - 6

  if tools_scanning then
    col(th.text_dim, 0.85)
    love.graphics.setFont(A.font(A.FONT_BODY, 13))
    love.graphics.printf("scanning SD1 and SD2...",
      W/2 - 200, vp_y + vp_h/2, 400, "center")
    return
  end

  if #tools_items == 0 then
    col(th.text_dim, 0.75)
    love.graphics.setFont(A.font(A.FONT_BODY, 13))
    love.graphics.printf("no muOS applications found",
      W/2 - 200, vp_y + vp_h/2 - 20, 400, "center")
    love.graphics.setFont(A.font(A.FONT_MONO, 10))
    col(acc, 0.7)
    love.graphics.printf("press Y to rescan, or check the catalog",
      W/2 - 200, vp_y + vp_h/2 + 10, 400, "center")
    return
  end

  local row_h = 62
  local row_step = row_h + 4
  local total_h = #tools_items * row_step
  local max_scroll = math.max(0, total_h - vp_h)
  local sel_top = (sel[3] - 1) * row_step
  local sel_bot = sel_top + row_h
  if sel_top - 6 < scroll[3] then scroll[3] = math.max(0, sel_top - 6) end
  if sel_bot + 6 > scroll[3] + vp_h then
    scroll[3] = math.min(max_scroll, sel_bot + 6 - vp_h)
  end
  scroll[3] = math.max(0, math.min(max_scroll, scroll[3]))

  love.graphics.setScissor(16, vp_y, W - 32, vp_h)
  local y = vp_y - scroll[3]
  for i, t in ipairs(tools_items) do
    local focused = (i == sel[3])
    local c = t.colour or acc
    local x = 16
    local w = W - 32

    if focused then
      col({c[1]*0.15, c[2]*0.15, c[3]*0.15}, 0.95)
      love.graphics.rectangle("fill", x, y, w, row_h, 4, 4)
      col(c, 0.95)
      love.graphics.setLineWidth(1.7)
      love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, row_h - 1, 4, 4)
      love.graphics.setLineWidth(1)
      col(c, 1)
      love.graphics.rectangle("fill", x, y + 8, 3, row_h - 16)
      D.corner_ticks(x + 6, y + 6, w - 12, row_h - 12, 8, c, 0.85)
    else
      col({0.028, 0.026, 0.030}, 0.85)
      love.graphics.rectangle("fill", x, y, w, row_h, 4, 4)
      col(c, 0.25)
      love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, row_h - 1, 4, 4)
    end

    -- icon
    local icx, icy, ir = x + 34, y + row_h/2, 20
    col({c[1]*0.20, c[2]*0.20, c[3]*0.20}, 0.95)
    love.graphics.circle("fill", icx, icy, ir)
    col(c, focused and 0.95 or 0.55)
    love.graphics.circle("line", icx, icy, ir)
    if t.source == "local" and t.local_path then
      local icon_path = app_icon_for(t.local_path)
      if icon_path then
        local img = ExtImg.load(icon_path)
        if img then
          local iw, ih = img:getDimensions()
          local sc = (ir * 1.6) / math.max(iw, ih)
          love.graphics.setColor(1, 1, 1, 1)
          love.graphics.draw(img, icx - iw*sc/2, icy - ih*sc/2, 0, sc, sc)
          love.graphics.setColor(1, 1, 1, 1)
        else
          draw_plugin_icon(t.icon, icx, icy, ir * 0.55, c, focused and 1 or 0.7)
        end
      else
        draw_plugin_icon(t.icon, icx, icy, ir * 0.55, c, focused and 1 or 0.7)
      end
    else
      draw_plugin_icon(t.icon, icx, icy, ir * 0.55, c, focused and 1 or 0.7)
    end

    -- name
    love.graphics.setFont(A.font(A.FONT_BODY_BOLD, focused and 13 or 12))
    col(focused and {1,1,1} or th.text, 1)
    local nm = t.name or t.key
    if #nm > 30 then nm = nm:sub(1, 29) .. "." end
    love.graphics.print(nm, x + 66, y + 8)

    -- tagline
    love.graphics.setFont(A.font(A.FONT_BODY, 9))
    col(th.text_dim, 0.85)
    local tg = t.tagline or ""
    if #tg > 52 then tg = tg:sub(1, 51) .. "..." end
    love.graphics.print(tg, x + 66, y + 26)

    -- meta: category + size
    love.graphics.setFont(A.font(A.FONT_MONO, 8))
    col(c, 0.7)
    local meta = (t.category or "?") .. "  ·  "
    if t.size_kb then meta = meta .. human_kb(t.size_kb)
    elseif t.local_path then meta = meta .. human(du_kb(t.local_path))
    else meta = meta .. "?" end
    love.graphics.print(meta, x + 66, y + 42)

    -- status pill
    local label, colr
    if t.installed then
      label, colr = "INSTALLED", GRN
    else
      label, colr = "NOT INSTALLED", RED
    end
    draw_status_pill(x + w - 10, y + row_h/2, label, colr)

    -- download progress bar
    for _, job in pairs(tools_dl) do
      if job.item == t then
        local bw = w - 32
        col({0.06, 0.07, 0.09}, 1)
        love.graphics.rectangle("fill", x + 16, y + row_h - 6, bw, 3, 1, 1)
        col(AMB, 0.9)
        love.graphics.rectangle("fill", x + 16, y + row_h - 6, bw * 0.5, 3, 1, 1)
      end
    end

    y = y + row_step
  end
  love.graphics.setScissor()

  if max_scroll > 0 then
    local track_h = vp_h - 4
    local thumb_h = math.max(20, track_h * (vp_h / total_h))
    local denom = math.max(1, total_h - vp_h)
    local thumb_y = vp_y + 2 + (track_h - thumb_h) * (scroll[3] / denom)
    col(acc, 0.55)
    love.graphics.rectangle("fill", W - 6, thumb_y, 3, thumb_h, 1, 1)
  end
end

local function draw_tools_detail()
  local th = State.theme
  local acc = TABS[3].accent
  local t = tools_items[sel[3]]
  if not t then view[3] = "list"; return end
  local c = t.colour or acc

  local X = 16
  local Wc = W - 32

  local installed = t.installed
  local status_label  = installed and "INSTALLED"     or "NOT INSTALLED"
  local status_colour = installed and GRN             or RED

  local primary_act, other_acts = tools_split_actions(t)

  local desc_txt = t.description or t.tagline or ""
  local feat_txt = ""
  if t.features and #t.features > 0 then
    feat_txt = "\226\128\162 " .. table.concat(t.features, "\n\226\128\162 ")
  end

  local info_lines = {}
  local path_val = t.install_path or t.local_path
  if path_val and path_val ~= "" then
    info_lines[#info_lines+1] = "PATH       " .. path_val
  end
  if t.repo and t.repo ~= "" then
    info_lines[#info_lines+1] = "REPO       " .. t.repo
  end
  if t.download and t.download ~= "" then
    info_lines[#info_lines+1] = "DOWNLOAD   " .. t.download
  end
  local meta_txt = table.concat(info_lines, "\n")

  local desc_h = info_block_height(desc_txt, Wc)
  local feat_h = info_block_height(feat_txt, Wc)
  local meta_h = info_block_height(meta_txt, Wc)
  if desc_h > 0 then desc_h = desc_h + 8 end
  if feat_h > 0 then feat_h = feat_h + 8 end
  if meta_h > 0 then meta_h = meta_h + 8 end

  local HERO_H       = 84
  local ACTBOX_H     = 56
  local ACTION_ROW_H = 42
  local GAP          = 8

  local actions_block_h = 0
  if #other_acts > 0 then
    actions_block_h = 24 + #other_acts * ACTION_ROW_H + 4
  end

  local total_h = HERO_H + GAP + ACTBOX_H + GAP
                + desc_h + feat_h + meta_h
                + actions_block_h + (actions_block_h > 0 and GAP or 0)

  local vp_y = CONTENT_Y
  local vp_h = H - Frame.BOTTOM_H - vp_y - 6
  local max_scroll = math.max(0, total_h - vp_h)
  if detail_scroll[3] > max_scroll then detail_scroll[3] = max_scroll end
  if detail_scroll[3] < 0 then detail_scroll[3] = 0 end

  local y_hero_abs    = 0
  local y_actbox_abs  = y_hero_abs + HERO_H + GAP
  local y_info_abs    = y_actbox_abs + ACTBOX_H + GAP
  local y_actions_abs = y_info_abs + desc_h + feat_h + meta_h

  local s = detail_sel[3]
  local focus_y_abs, focus_h
  if s == 1 then
    focus_y_abs = y_actbox_abs
    focus_h = ACTBOX_H
  else
    focus_y_abs = y_actions_abs + 24 + (s - 2) * ACTION_ROW_H
    focus_h = ACTION_ROW_H
  end
  local margin = 10
  if focus_y_abs - margin < detail_scroll[3] then
    detail_scroll[3] = math.max(0, focus_y_abs - margin)
  end
  if focus_y_abs + focus_h + margin > detail_scroll[3] + vp_h then
    detail_scroll[3] = math.min(max_scroll, focus_y_abs + focus_h + margin - vp_h)
  end

  local y_hero    = vp_y + y_hero_abs    - detail_scroll[3]
  local y_actbox  = vp_y + y_actbox_abs  - detail_scroll[3]
  local y_info    = vp_y + y_info_abs    - detail_scroll[3]
  local y_actions = vp_y + y_actions_abs - detail_scroll[3]

  love.graphics.setScissor(X - 4, vp_y, Wc + 8, vp_h)

  -- ===== HERO =====
  col({c[1]*0.12, c[2]*0.12, c[3]*0.12}, 0.95)
  love.graphics.rectangle("fill", X, y_hero, Wc, HERO_H, 5, 5)
  col(c, 0.9)
  love.graphics.setLineWidth(1.8)
  love.graphics.rectangle("line", X + 0.5, y_hero + 0.5, Wc - 1, HERO_H - 1, 5, 5)
  love.graphics.setLineWidth(1)
  D.corner_ticks(X + 8, y_hero + 8, Wc - 16, HERO_H - 16, 12, c, 0.9)

  local icx = X + 44
  local icy = y_hero + HERO_H / 2
  col({c[1]*0.22, c[2]*0.22, c[3]*0.22}, 0.95)
  love.graphics.circle("fill", icx, icy, 26)
  col(c, 0.95)
  love.graphics.circle("line", icx, icy, 26)
  draw_plugin_icon(t.icon or "gear", icx, icy, 18, c, 1)

  love.graphics.setFont(A.font(A.FONT_TITLE, 16))
  col(c, 1)
  local nm = t.name or t.key or "?"
  if #nm > 32 then nm = nm:sub(1, 31) .. "." end
  love.graphics.print(nm, X + 84, y_hero + 10)

  love.graphics.setFont(A.font(A.FONT_MONO, 9))
  col(c, 0.8)
  love.graphics.print("v" .. (t.version or "?") .. "  \194\183  " ..
    (t.category or "?") .. "  \194\183  " .. (t.source or "?"),
    X + 84, y_hero + 32)

  love.graphics.setFont(A.font(A.FONT_BODY, 10))
  col(th.text, 0.9)
  local tg = t.tagline or ""
  if #tg > 52 then tg = tg:sub(1, 51) .. "." end
  love.graphics.print(tg, X + 84, y_hero + 50)

  -- ===== STATUS BOX =====
  local f1 = (s == 1)
  if f1 then
    col({status_colour[1]*0.15, status_colour[2]*0.15, status_colour[3]*0.15}, 0.95)
    love.graphics.rectangle("fill", X, y_actbox, Wc, ACTBOX_H, 5, 5)
    col(status_colour, 0.95)
    love.graphics.setLineWidth(1.8)
    love.graphics.rectangle("line", X + 0.5, y_actbox + 0.5, Wc - 1, ACTBOX_H - 1, 5, 5)
    love.graphics.setLineWidth(1)
    col(status_colour, 1)
    love.graphics.rectangle("fill", X, y_actbox + 8, 3, ACTBOX_H - 16)
    D.corner_ticks(X + 8, y_actbox + 8, Wc - 16, ACTBOX_H - 16, 10, status_colour, 0.9)
  else
    col({0.030, 0.026, 0.030}, 0.9)
    love.graphics.rectangle("fill", X, y_actbox, Wc, ACTBOX_H, 5, 5)
    col(status_colour, 0.35)
    love.graphics.rectangle("line", X + 0.5, y_actbox + 0.5, Wc - 1, ACTBOX_H - 1, 5, 5)
  end

  love.graphics.setFont(A.font(A.FONT_BODY_BOLD, 13))
  col(f1 and {1,1,1} or th.text, 1)
  love.graphics.print("Application status", X + 16, y_actbox + 8)

  love.graphics.setFont(A.font(A.FONT_BODY, 9))
  col(th.text_dim, 0.85)
  local subtext = installed and "ready to launch" or "install to enable"
  love.graphics.print(subtext, X + 16, y_actbox + 28)

  -- Status label (right)
  love.graphics.setFont(A.font(A.FONT_BODY_BOLD, 12))
  col(status_colour, 1)
  love.graphics.printf(status_label, X + Wc - 220, y_actbox + 19, 110, "right")

  -- LED indicator
  local led_x = X + Wc - 30
  local led_y = y_actbox + ACTBOX_H / 2
  col({0, 0, 0}, 0.5)
  love.graphics.circle("fill", led_x + 1, led_y + 2, 12)
  col(status_colour, 0.35)
  love.graphics.circle("fill", led_x, led_y, 12)
  col(status_colour, 1)
  love.graphics.circle("fill", led_x, led_y, 6)

  -- Primary action pill (top right)
  if primary_act then
    local pac = primary_act.colour or status_colour
    local paf = A.font(A.FONT_MONO, 9)
    love.graphics.setFont(paf)
    local label = primary_act.label or "?"
    local pw = paf:getWidth(label) + 20
    local ph = 14
    local px = X + Wc - pw - 46
    local py = y_actbox + 4
    col({pac[1]*0.22, pac[2]*0.22, pac[3]*0.22}, 1)
    love.graphics.rectangle("fill", px, py, pw, ph, 7, 7)
    col(pac, 0.9)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", px + 0.5, py + 0.5, pw - 1, ph - 1, 7, 7)
    love.graphics.setLineWidth(1)
    col({1,1,1}, 1)
    love.graphics.printf(label, px, py + 2, pw, "center")
  end

  -- ===== INFO BLOCKS =====
  local yb = y_info
  if desc_h > 0 then
    draw_info_block(X, yb, Wc, desc_h - 8, "DESCRIPTION", desc_txt, acc, th, acc)
    yb = yb + desc_h
  end
  if feat_h > 0 then
    draw_info_block(X, yb, Wc, feat_h - 8, "FEATURES", feat_txt, GRN, th, acc)
    yb = yb + feat_h
  end
  if meta_h > 0 then
    draw_info_block(X, yb, Wc, meta_h - 8, "INFO", meta_txt, CYA, th, acc)
    yb = yb + meta_h
  end

  -- ===== ACTIONS =====
  if #other_acts > 0 then
    love.graphics.setFont(A.font(A.FONT_MONO, 10))
    col(acc, 0.9)
    love.graphics.print("ACTIONS", X + 6, y_actions + 4)
    col(acc, 0.3)
    love.graphics.rectangle("fill", X + 6, y_actions + 18, Wc - 12, 1)

    for i, a in ipairs(other_acts) do
      local ry = y_actions + 24 + (i - 1) * ACTION_ROW_H
      local focused = (s == i + 1)
      local ac = a.colour or acc
      local rx = X + 6
      local rw = Wc - 12
      local rh = ACTION_ROW_H - 4

      if focused then
        col({ac[1]*0.18, ac[2]*0.18, ac[3]*0.18}, 0.95)
        love.graphics.rectangle("fill", rx, ry, rw, rh, 4, 4)
        col(ac, 0.95)
        love.graphics.setLineWidth(1.6)
        love.graphics.rectangle("line", rx + 0.5, ry + 0.5, rw - 1, rh - 1, 4, 4)
        love.graphics.setLineWidth(1)
        col(ac, 1)
        love.graphics.rectangle("fill", rx, ry + 6, 3, rh - 12)
      else
        col({0.028, 0.026, 0.030}, 0.85)
        love.graphics.rectangle("fill", rx, ry, rw, rh, 4, 4)
        col(ac, 0.25)
        love.graphics.rectangle("line", rx + 0.5, ry + 0.5, rw - 1, rh - 1, 4, 4)
      end

      love.graphics.setFont(A.font(A.FONT_BODY_BOLD, 12))
      col(focused and {1,1,1} or th.text, 1)
      love.graphics.print(a.label, rx + 14, ry + 4)

      love.graphics.setFont(A.font(A.FONT_BODY, 9))
      col(th.text_dim, 0.8)
      local hint2 = a.hint or ""
      if #hint2 > 52 then hint2 = hint2:sub(1, 51) .. "..." end
      love.graphics.print(hint2, rx + 14, ry + 22)

      if focused then
        col(ac, 0.9)
        love.graphics.setLineWidth(2)
        love.graphics.line(rx + rw - 20, ry + rh/2 - 6,
                           rx + rw - 12, ry + rh/2,
                           rx + rw - 20, ry + rh/2 + 6)
        love.graphics.setLineWidth(1)
      end
    end
  end

  love.graphics.setScissor()

  if max_scroll > 0 then
    local track_h = vp_h - 8
    local thumb_h = math.max(20, track_h * (vp_h / (vp_h + max_scroll)))
    local thumb_y = vp_y + 4 + (track_h - thumb_h) * (detail_scroll[3] / max_scroll)
    col(acc, 0.55)
    love.graphics.rectangle("fill", W - 6, thumb_y, 3, thumb_h, 1, 1)
  end

  Frame.draw_top("FGD", "plugins")
  Frame.draw_bottom({
    { key = "l1",  label = "Prev" },
    { key = "r1",  label = "Next" },
    { key = "up",  label = "Move" },
    { key = "a",   label = "Run" },
    { key = "b",   label = "Back" },
  })
end

local function draw_tools()
  if view[3] == "detail" then draw_tools_detail() else draw_tools_list() end
end

-- ============================================================
--  Lifecycle
-- ============================================================
function S.enter()
  tab = 1
  sel = { 1, 1, 1 }
  scroll = { 0, 0, 0 }
  view = { "list", "list", "list" }
  detail_sel = { 1, 1, 1 }
  detail_tab = { 1, 1, 1 }
  detail_scroll = { 0, 0, 0 }
  launch_list = build_launch_list()
  store_reload()
  tools_scan()

  local ok, PI = pcall(require, "ui.plugin_intro")
  if ok and PI.start then
    PI.start("plugins_hub_v3", "PLUGINS", AMB, "hex")
  end
end

function S.leave() end

function S.update(dt)
  t_global = t_global + dt
  last_dt = dt
  pcall(function() require("ui.frame").sync() end)

  -- plugin download progress
  for _, p in ipairs(store_items) do
    local st = progress[p.id]
    if st and st > 0 and st < 1 then
      progress[p.id] = read_progress(p)
      if sh.exists(done_path(p)) then
        local f = io.open(part_path(p), "rb")
        local sz = 0
        if f then sz = f:seek("end"); f:close() end
        if sz > 0 then
          sh.exec("mv " .. sh.shq(part_path(p)) .. " " .. sh.shq(final_path(p)))
          sh.exec("rm -f " .. sh.shq(done_path(p)) .. " " .. sh.shq(progress_path(p)))
          log_event(p, "DOWNLOAD complete")
          do_install(p)
          progress[p.id] = 0
        else
          log_event(p, "ERROR download empty")
          progress[p.id] = 0
          Notify.show("error", p.name .. ": download failed")
        end
      end
    end
  end

  -- tools download poll
  if next(tools_dl) then
    local DL = require("services.downloader")
    for id, job in pairs(tools_dl) do
      local st = DL.status(id)
      if st and st.done then
        local out = "data/downloads/" .. job.filename
        if st.rc == 0 then
          if job.item.format == ".muxapp" and job.item.install_path then
            local app_folder = job.item.install_path:match("^(.*)/[^/]+$")
            if app_folder then
              local app_name = app_folder:match("([^/]+)$")
              local tmp = "/tmp/fgdx_extract_" .. tostring(os.time())
              sh.exec("rm -rf " .. sh.shq(tmp))
              sh.exec("mkdir -p " .. sh.shq(tmp))
              sh.exec("unzip -o -q " .. sh.shq(out) .. " -d " .. sh.shq(tmp))
              local found = sh.read("find " .. sh.shq(tmp) .. " -name mux_launch.sh -print -quit 2>/dev/null")
              found = (found or ""):gsub("%s+$", "")
              if found ~= "" then
                local found_dir = found:match("^(.*)/[^/]+$") or tmp
                if found_dir == tmp then
                  sh.exec("mkdir -p " .. sh.shq(app_folder))
                  sh.exec("cp -a " .. sh.shq(tmp) .. "/. " .. sh.shq(app_folder))
                else
                  local rel = found_dir:sub(#tmp + 2)
                  local top = rel:match("^([^/]+)") or app_name
                  local gp = app_folder:match("^(.*)/[^/]+$") or "/"
                  sh.exec("mkdir -p " .. sh.shq(gp))
                  sh.exec("rm -rf " .. sh.shq(gp .. "/" .. top))
                  sh.exec("mv " .. sh.shq(tmp .. "/" .. top) .. " " .. sh.shq(gp .. "/"))
                end
                job.item.installed = true
                Notify.show("success", job.item.name .. " installed")
              else
                Notify.show("error", "mux_launch.sh non trovato: " .. job.item.name)
              end
              sh.exec("rm -rf " .. sh.shq(tmp))
            end
          else
            Notify.show("info", job.item.name .. " downloaded to data/downloads/")
          end
        else
          Notify.show("error", job.item.name .. " download failed")
        end
        tools_dl[id] = nil
        DL.dismiss(id)
      end
    end
  end
end

-- ============================================================
--  Input
-- ============================================================
local function change_tab(d)
  tab = tab + d
  if tab < 1 then tab = NTAB end
  if tab > NTAB then tab = 1 end
end

function S.pad(b)
  if Modal.is_open() then
    if b == Input.A then Modal.accept()
    elseif b == Input.B then Modal.cancel() end
    return
  end

  if b == Input.L1 then
    if tab == 2 and view[2] == "detail" then
      jump_plugin(-1)
      detail_sel[2] = 1
      detail_scroll[2] = 0
    else
      change_tab(-1)
    end
    return
  end
  if b == Input.R1 then
    if tab == 2 and view[2] == "detail" then
      jump_plugin(1)
      detail_sel[2] = 1
      detail_scroll[2] = 0
    else
      change_tab(1)
    end
    return
  end

  if tab == 1 then
    if     b == Input.UP    then launch_move(-1)
    elseif b == Input.DOWN  then launch_move( 1)
    elseif b == Input.A     then launch_activate()
    elseif b == Input.B or b == Input.SELECT then State.go("mainmenu") end
  elseif tab == 2 then
    if view[2] == "detail" then
      if     b == Input.UP    then store_detail_move(-1)
      elseif b == Input.DOWN  then store_detail_move( 1)
      elseif b == Input.A     then store_detail_activate()
      elseif b == Input.B or b == Input.SELECT then view[2] = "list" end
    else
      if     b == Input.UP    then store_move(-1)
      elseif b == Input.DOWN  then store_move( 1)
      elseif b == Input.LEFT  then store_change_filter(-1)
      elseif b == Input.RIGHT then store_change_filter( 1)
      elseif b == Input.A     then store_activate()
      elseif b == Input.X then
        local p = store_current_item()
        if p and (p.source == "local" or p.installed) then
          local now_off = PR.toggle(p.id)
          p.disabled = now_off
          log_event(p, now_off and "STATE disabled" or "STATE enabled")
          Notify.show("info", p.name .. (now_off and " disabled" or " enabled"))
        end
      elseif b == Input.Y then
        local p = store_current_item()
        if p and not p.builtin and not p.installed then start_download(p)
        elseif p and p.screen and p.installed and not p.disabled
                                    then State.go(p.screen)
        else Notify.show("info", "nothing to do") end
      elseif b == Input.B or b == Input.SELECT then State.go("mainmenu") end
    end
  elseif tab == 3 then
    if view[3] == "detail" then
      if     b == Input.UP    then tools_detail_move(-1)
      elseif b == Input.DOWN  then tools_detail_move( 1)
      elseif b == Input.A     then tools_detail_activate()
      elseif b == Input.B or b == Input.SELECT then view[3] = "list" end
    else
      if     b == Input.UP    then tools_move(-1)
      elseif b == Input.DOWN  then tools_move( 1)
      elseif b == Input.A     then tools_activate()
      elseif b == Input.X then
        local t = tools_items[sel[3]]
        if t then tools_open(t) end
      elseif b == Input.Y then
        tools_scan(); Notify.show("info", "rescan done")
      elseif b == Input.B or b == Input.SELECT then State.go("mainmenu") end
    end
  end
end

function S.hat(dir)
  if Modal.is_open() then return end
  if tab == 1 then
    if     dir == "up"   then launch_move(-1)
    elseif dir == "down" then launch_move( 1) end
  elseif tab == 2 then
    if view[2] == "detail" then
      if     dir == "up"    then store_detail_move(-1)
      elseif dir == "down"  then store_detail_move( 1)
      end
    else
      if     dir == "up"    then store_move(-1)
      elseif dir == "down"  then store_move( 1)
      elseif dir == "left"  then store_change_filter(-1)
      elseif dir == "right" then store_change_filter( 1) end
    end
  elseif tab == 3 then
    if view[3] == "detail" then
      if     dir == "up"    then tools_detail_move(-1)
      elseif dir == "down"  then tools_detail_move( 1)
      end
    else
      if     dir == "up"   then tools_move(-1)
      elseif dir == "down" then tools_move( 1) end
    end
  end
end

function S.key(k)
  if Modal.is_open() then
    if k == "return" or k == "space" then Modal.accept()
    elseif k == "escape" or k == "backspace" then Modal.cancel() end
    return
  end
  if     k == "q" then change_tab(-1); return end
  if     k == "e" then change_tab( 1); return end
  if     k == "up"    then S.hat("up"); return end
  if     k == "down"  then S.hat("down"); return end
  if     k == "left"  then S.hat("left"); return end
  if     k == "right" then S.hat("right"); return end
  if     k == "return" or k == "space" then S.pad(Input.A); return end
  if     k == "x" then S.pad(Input.X); return end
  if     k == "y" then S.pad(Input.Y); return end
  if     k == "escape" or k == "backspace" then
    if (tab == 2 and view[2] == "detail") or (tab == 3 and view[3] == "detail") then
      view[tab] = "list"
    else
      State.go("mainmenu")
    end
    return
  end
end

-- ============================================================
--  Main draw
-- ============================================================
function S.draw()
  D.bg()
  local acc = TABS[tab].accent

  col(acc, 0.045)
  for y = Frame.TOP_H, H - Frame.BOTTOM_H, 20 do
    for x = 0, W, 20 do love.graphics.rectangle("fill", x, y, 1, 1) end
  end
  D.corner_ticks(4, Frame.TOP_H + 2, W - 8,
    H - Frame.TOP_H - Frame.BOTTOM_H - 4, 18, acc, 0.30)

  draw_tab_bar(16, TAB_Y, W - 32)

  if tab == 1 then draw_launch()
  elseif tab == 2 then draw_store()
  else draw_tools() end

  Frame.draw_top("FGD", "plugins")

  local hints
  if tab == 1 then
    hints = {
      { key = "l1",  label = "Tab" },
      { key = "up",  label = "Select" },
      { key = "a",   label = "Launch" },
      { key = "b",   label = "Back" },
    }
  elseif tab == 2 then
    if view[2] == "detail" then
      hints = {
        { key = "l1",  label = "Tab" },
        { key = "up",  label = "Move" },
        { key = "l/r", label = "Section" },
        { key = "a",   label = "Run" },
        { key = "b",   label = "Back" },
      }
    else
      hints = {
        { key = "l1",  label = "Tab" },
        { key = "up",  label = "Move" },
        { key = "l/r", label = "Filter" },
        { key = "a",   label = "Details" },
        { key = "x",   label = "Toggle" },
        { key = "y",   label = "Install" },
        { key = "b",   label = "Back" },
      }
    end
  else
    if view[3] == "detail" then
      hints = {
        { key = "l1",  label = "Tab" },
        { key = "up",  label = "Move" },
        { key = "l/r", label = "Section" },
        { key = "a",   label = "Run" },
        { key = "b",   label = "Back" },
      }
    else
      hints = {
        { key = "l1",  label = "Tab" },
        { key = "up",  label = "Move" },
        { key = "a",   label = "Manage" },
        { key = "x",   label = "Open" },
        { key = "y",   label = "Rescan" },
        { key = "b",   label = "Back" },
      }
    end
  end
  Frame.draw_bottom(hints)

  Modal.draw()
  D.scanlines(W, H, 0.05)
  D.vignette(W, H, 0.55)
end

return S