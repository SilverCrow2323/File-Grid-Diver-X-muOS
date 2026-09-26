-- screens/fgd_plugins.lua -- FGD-X Plugins catalogue v2.
-- List: single-column rows, L1/R1 jump between plugins.
-- Detail: 2 tabs (SUMMARY / ACTIONS).
--   SUMMARY: identity, description, features, dependencies, documentation
--   ACTIONS: power switch, install/reinstall/uninstall, log/history
-- Each plugin has a stable identifier code (FGD-XXXX, hash of id).

local A       = require("core.assets")
local State   = require("core.state")
local Input   = require("core.input_map")
local Frame   = require("ui.frame")
local D       = require("ui.draw")
local BI      = require("ui.button_icons")
local Notify  = require("ui.notify")
local Modal   = require("ui.modal")
local sh      = require("core.sh")
local PR      = require("services.plugin_registry")
local Cat     = require("services.catalog")
local Loader  = require("plugins.loader")

local S = {}
local W, H = 640, 480

local function col(c, a)
  love.graphics.setColor(c[1], c[2], c[3], a or 1)
end

local function log_err(where, err)
  local msg = string.format("[fgd_plugins %s] %s", where, tostring(err))
  local f = io.open("data/fgd_runtime.log", "a")
  if f then
    f:write(os.date("%Y-%m-%d %H:%M:%S ") .. msg .. "\n"); f:close()
  end
  print(msg)
end

-- Palette
local PURP    = {0.70, 0.55, 0.92}
local PURP_HI = {0.85, 0.70, 1.00}
local GRN     = {0.35, 0.90, 0.50}
local RED     = {0.95, 0.35, 0.30}
local AMB     = {0.94, 0.66, 0.35}
local GRY     = {0.45, 0.45, 0.50}
local CYA     = {0.30, 0.85, 0.95}

-- ============================================================
--  Stable plugin identifier
-- ============================================================
local function plugin_code(id)
  local h = 0
  for i = 1, #id do
    h = (h * 33 + id:byte(i)) % 0x10000
  end
  return string.format("FGD-%04X", h)
end

-- ============================================================
--  Per-plugin log
-- ============================================================
local LOG_DIR = "data/plugin_logs"
os.execute("mkdir -p " .. LOG_DIR)

local function plugin_log_path(p)
  return LOG_DIR .. "/" .. (p.id or p.key or "unknown") .. ".log"
end

local function plugin_log(p, event)
  local f = io.open(plugin_log_path(p), "a")
  if f then
    f:write(os.date("%Y-%m-%d %H:%M:%S") .. "  " .. event .. "\n")
    f:close()
  end
end

local function plugin_read_log(p, max_lines)
  max_lines = max_lines or 300
  local lines = {}
  local f = io.open(plugin_log_path(p), "r")
  if f then
    for line in f:lines() do lines[#lines+1] = line end
    f:close()
  end
  local start = math.max(1, #lines - max_lines + 1)
  local out = {}
  for i = start, #lines do out[#out+1] = lines[i] end
  return out
end

-- ============================================================
--  Plugin list
-- ============================================================
local PLUGINS = {}

local function load_plugins()
  PLUGINS = {}
  local seen = {}

  for _, p in ipairs(Loader.list()) do
    if not p.extender then
      PLUGINS[#PLUGINS+1] = {
        id = p.key, key = p.key,
        name = p.name,
        tagline = p.desc or "",
        description = p.desc or "",
        version = p.version or "1.0.0",
        author = p.author or "sirpips",
        source = "local plugin",
        license = "GPL-3.0",
        icon = p.icon or "plug",
        colour = p.colour or PURP,
        dependencies = { "built-in engine" },
        features = {},
        builtin = true,
        open_screen = p.key,
        installed_check = "echo ok",
        category = "local",
      }
      seen[p.key] = true
    end
  end

  for _, pl in ipairs(Cat.all_plugins()) do
    if not seen[pl.id] and not pl.coming_soon then
      PLUGINS[#PLUGINS+1] = pl
      seen[pl.id] = true
    end
  end

  table.sort(PLUGINS, function(a, b)
    local an = (a.name or ""):lower()
    local bn = (b.name or ""):lower()
    if an == bn then return (a.id or "") < (b.id or "") end
    return an < bn
  end)

  for _, p in ipairs(PLUGINS) do
    p.code = plugin_code(p.id)
  end
end

-- ============================================================
--  Status / download helpers
-- ============================================================
local status = {}

local function dl_dir() return "data/downloads" end
local function part_path(p) return dl_dir() .. "/" .. (p.wheel_name or "") .. ".part" end
local function final_path(p) return dl_dir() .. "/" .. (p.wheel_name or "") end
local function progress_path(p) return dl_dir() .. "/" .. p.id .. ".progress" end
local function done_path(p) return dl_dir() .. "/" .. p.id .. ".done" end
local function script_path(p) return dl_dir() .. "/" .. p.id .. ".sh" end
local function install_log_path(p) return LOG_DIR .. "/" .. p.id .. ".install.log" end

local function read_progress(p)
  local f = io.open(progress_path(p))
  if not f then return 0 end
  local line = f:read("*l") or ""
  f:close()
  local cur, tot = line:match("(%d+)|(%d+)")
  cur = tonumber(cur) or 0
  tot = tonumber(tot) or (p.wheel_size or 1)
  if tot <= 0 then return 0 end
  return math.min(0.99, cur / tot)
end

local function clean_transient(p)
  sh.exec("rm -f " .. sh.shq(part_path(p)) .. " " ..
    sh.shq(progress_path(p)) .. " " .. sh.shq(done_path(p)) .. " " ..
    sh.shq(script_path(p)))
end

local function refresh_status(p)
  local is_off = PR.is_disabled(p.id)
  if p.builtin then
    status[p.id] = is_off and "disabled" or "installed"
    return
  end
  local out = sh.read(p.installed_check or "echo no")
  if out and out:find("ok", 1, true) then
    status[p.id] = is_off and "disabled" or "installed"
    return
  end
  if sh.exists(final_path(p)) then
    status[p.id] = "installing"
    return
  end
  if sh.exists(part_path(p)) and sh.exists(done_path(p)) then
    status[p.id] = "downloading"
    return
  end
  if sh.exists(part_path(p)) then clean_transient(p) end
  status[p.id] = "missing"
end

-- ============================================================
--  Download / install / remove
-- ============================================================
local function start_download(p)
  sh.exec("mkdir -p " .. sh.shq(dl_dir()))
  clean_transient(p)
  local f = io.open(script_path(p), "w")
  if not f then
    status[p.id] = "error"
    plugin_log(p, "ERROR cannot write download script")
    return
  end
  f:write("#!/bin/sh\n")
  f:write("mkdir -p " .. sh.shq(dl_dir()) .. "\n")
  f:write("curl -L --fail --silent --show-error -o " .. sh.shq(part_path(p)) ..
    " " .. sh.shq(p.wheel_url) .. " &\n")
  f:write("PID=$!\n")
  f:write("while kill -0 $PID 2>/dev/null; do\n")
  f:write("  if [ -f " .. sh.shq(part_path(p)) .. " ]; then\n")
  f:write("    SZ=$(stat -c '%s' " .. sh.shq(part_path(p)) .. " 2>/dev/null)\n")
  f:write("    [ -z \"$SZ\" ] && SZ=$(wc -c < " .. sh.shq(part_path(p)) .. " 2>/dev/null)\n")
  f:write("    [ -z \"$SZ\" ] && SZ=0\n")
  f:write("  else SZ=0; fi\n")
  f:write("  echo \"$SZ|" .. (p.wheel_size or 0) .. "\" > " .. sh.shq(progress_path(p)) .. "\n")
  f:write("  sleep 0.4\n")
  f:write("done\n")
  f:write("wait $PID\n")
  f:write("touch " .. sh.shq(done_path(p)) .. "\n")
  f:close()
  sh.exec("chmod +x " .. sh.shq(script_path(p)))
  local cmd = "(setsid sh " .. sh.shq(script_path(p)) .. " </dev/null >/dev/null 2>&1 &) " ..
    "|| (nohup sh " .. sh.shq(script_path(p)) .. " >/dev/null 2>&1 &) " ..
    "|| (sh " .. sh.shq(script_path(p)) .. " >/dev/null 2>&1 &)"
  os.execute(cmd)
  status[p.id] = "downloading"
  plugin_log(p, "DOWNLOAD started " .. (p.wheel_name or ""))
end

local function do_install(p)
  if not p.pkg_name or p.pkg_name == "" then
    status[p.id] = "installed"
    return
  end
  local cmd = "python3 -m pip install --no-index --find-links=" ..
    sh.shq(p.pack_dir or "data/downloads") .. " " .. p.pkg_name .. " 2>&1"
  local out = sh.read(cmd) or ""
  local lf = io.open(install_log_path(p), "w")
  if lf then
    lf:write("=== pip install " .. p.pkg_name .. " ===\n")
    lf:write(os.date("%Y-%m-%d %H:%M:%S") .. "\n\n")
    lf:write(out); lf:close()
  end
  local check = sh.read(p.installed_check or "echo no")
  if check and check:find("ok", 1, true) then
    status[p.id] = "installed"
    clean_transient(p)
    plugin_log(p, "INSTALL ok " .. p.pkg_name)
    Notify.show("success", p.name .. " installed")
  else
    status[p.id] = "error"
    plugin_log(p, "ERROR install failed: " .. out:sub(1, 120))
    Notify.show("error", p.name .. " install failed")
  end
end

local function remove_plugin(p)
  if p.pkg_name and p.pkg_name ~= "" then
    sh.exec("python3 -m pip uninstall -y " .. p.pkg_name .. " 2>&1")
  end
  sh.exec("rm -f " .. sh.shq(final_path(p)))
  clean_transient(p)
  status[p.id] = "missing"
  plugin_log(p, "UNINSTALL " .. (p.pkg_name or p.id))
  Notify.show("info", p.name .. " removed")
end

-- ============================================================
--  Module state
-- ============================================================
local mode       = "list"
local sel        = 1
local scroll     = 0
local detail_idx = 1
local tab        = 1
local TAB_COUNT  = 2
local TAB_NAMES  = { "SUMMARY", "ACTIONS" }
local sum_scroll = 0
local sum_max    = 0
local act_sel    = 1
local act_scroll = 0
local act_max    = 0
local t_enter    = 0
local progress   = {}

-- ============================================================
--  Lifecycle
-- ============================================================
function S.enter()
  t_enter = 0
  mode = "list"
  sel = 1
  scroll = 0
  load_plugins()
  for _, p in ipairs(PLUGINS) do
    progress[p.id] = 0
    if not p.builtin then clean_transient(p) end
    refresh_status(p)
  end
  for _, p in ipairs(PLUGINS) do
    if not plugin_read_log(p, 1)[1] then
      plugin_log(p, "DETECTED status=" .. (status[p.id] or "?"))
    end
  end
end

function S.leave() end

function S.update(dt)
  t_enter = t_enter + dt
  for _, p in ipairs(PLUGINS) do
    if not p.builtin then
      local st = status[p.id]
      if st == "downloading" then
        progress[p.id] = read_progress(p)
        if sh.exists(done_path(p)) then
          local f = io.open(part_path(p), "rb")
          local sz = 0
          if f then sz = f:seek("end"); f:close() end
          if sz > 0 then
            sh.exec("mv " .. sh.shq(part_path(p)) .. " " .. sh.shq(final_path(p)))
            sh.exec("rm -f " .. sh.shq(done_path(p)) .. " " .. sh.shq(progress_path(p)))
            plugin_log(p, "DOWNLOAD complete")
            status[p.id] = "installing"
          else
            status[p.id] = "error"
            plugin_log(p, "ERROR download empty")
          end
        end
      elseif st == "installing" then
        do_install(p)
      end
    end
  end
end

-- ============================================================
--  Helpers
-- ============================================================
local function current_plugin()
  return PLUGINS[sel]
end

local function move(d)
  if #PLUGINS == 0 then return end
  sel = sel + d
  if sel < 1 then sel = 1 end
  if sel > #PLUGINS then sel = #PLUGINS end
end

local function jump_plugin(d)
  if #PLUGINS == 0 then return end
  sel = sel + d
  if sel < 1 then sel = #PLUGINS end
  if sel > #PLUGINS then sel = 1 end
end

local function open_detail()
  local p = current_plugin()
  if not p then return end
  detail_idx = sel
  tab = 1
  sum_scroll = 0
  act_sel = 1
  act_scroll = 0
  mode = "detail"
  if not status[p.id] then refresh_status(p) end
end

local function toggle_plugin(p)
  if not p then return end
  local st = status[p.id]
  if not p.builtin and (st ~= "installed" and st ~= "disabled") then
    Notify.show("warning", "plugin is not installed")
    return
  end
  local now_off = PR.toggle(p.id)
  plugin_log(p, now_off and "STATE disabled" or "STATE enabled")
  Notify.show("info", p.name .. (now_off and " disabled" or " enabled"))
  refresh_status(p)
end

-- ============================================================
--  Input
-- ============================================================
function S.pad(b)
  if Modal.is_open() then
    if b == Input.A then Modal.accept()
    elseif b == Input.B then Modal.cancel() end
    return
  end

  if mode == "list" then
    if     b == Input.UP    or b == Input.L1 then move(-1)
    elseif b == Input.DOWN  or b == Input.R1 then move( 1)
    elseif b == Input.A     then open_detail()
    elseif b == Input.Y     then toggle_plugin(current_plugin())
    elseif b == Input.B or b == Input.SELECT then State.back() end
  else
    local p = PLUGINS[detail_idx]
    if not p then mode = "list"; return end

    if b == Input.L1 then
      jump_plugin(-1)
      detail_idx = sel
      sum_scroll, act_scroll = 0, 0
      if not status[PLUGINS[detail_idx].id] then refresh_status(PLUGINS[detail_idx]) end
    elseif b == Input.R1 then
      jump_plugin( 1)
      detail_idx = sel
      sum_scroll, act_scroll = 0, 0
      if not status[PLUGINS[detail_idx].id] then refresh_status(PLUGINS[detail_idx]) end
    elseif b == Input.LEFT then
      tab = tab - 1
      if tab < 1 then tab = TAB_COUNT end
    elseif b == Input.RIGHT then
      tab = tab + 1
      if tab > TAB_COUNT then tab = 1 end
    elseif b == Input.UP then
      if tab == 1 then sum_scroll = math.max(0, sum_scroll - 30)
      else act_sel = math.max(1, act_sel - 1) end
    elseif b == Input.DOWN then
      if tab == 1 then sum_scroll = math.min(sum_max, sum_scroll + 30)
      else
        local n = #(p.__actions or {})
        act_sel = math.min(math.max(1, n), act_sel + 1)
      end
    elseif b == Input.A then
      -- Activate focused action in ACTIONS tab; open plugin in SUMMARY tab
      if tab == 1 then
        if (status[p.id] == "installed") and p.open_screen and p.open_screen ~= "" then
          State.go(p.open_screen)
        end
      else
        local a = (p.__actions or {})[act_sel]
        if a and a.kind == "switch" then
          toggle_plugin(p)
        elseif a and a.kind == "install" then
          start_download(p)
        elseif a and a.kind == "reinstall" then
          Modal.show("Reinstall " .. p.name, "Remove and re-download?",
            { accept_label = "REINSTALL", cancel_label = "CANCEL",
              accept_color = AMB,
              on_accept = function() remove_plugin(p); start_download(p) end })
        elseif a and a.kind == "uninstall" then
          Modal.show("Uninstall " .. p.name,
            "Permanently uninstall this plugin?",
            { accept_label = "UNINSTALL", cancel_label = "CANCEL",
              accept_color = RED,
              on_accept = function() remove_plugin(p) end })
        elseif a and a.kind == "cancel" then
          clean_transient(p)
          status[p.id] = "missing"
          plugin_log(p, "DOWNLOAD cancelled")
        end
      end
    elseif b == Input.X then
      -- Quick manage from any tab
      if not p.builtin then
        local st = status[p.id]
        if st == "missing" or st == "error" then
          start_download(p)
        elseif st == "installed" or st == "disabled" then
          Modal.show("Manage " .. p.name,
            "What do you want to do?",
            { accept_label = "REINSTALL", cancel_label = "UNINSTALL",
              accept_color = AMB, cancel_color = RED,
              on_accept = function() remove_plugin(p); start_download(p) end,
              on_cancel = function() remove_plugin(p) end })
        end
      end
    elseif b == Input.Y then
      toggle_plugin(p)
    elseif b == Input.B or b == Input.SELECT then
      mode = "list"
      sel = detail_idx
    end
  end
end

function S.hat(dir)
  if Modal.is_open() then return end
  if mode == "list" then
    if dir == "up" then move(-1)
    elseif dir == "down" then move(1) end
  else
    if dir == "left" then S.pad(Input.LEFT)
    elseif dir == "right" then S.pad(Input.RIGHT)
    elseif dir == "up" then S.pad(Input.UP)
    elseif dir == "down" then S.pad(Input.DOWN) end
  end
end

function S.key(k)
  if Modal.is_open() then
    if k == "return" or k == "space" then Modal.accept()
    elseif k == "escape" or k == "backspace" then Modal.cancel() end
    return
  end
  if     k == "up" then S.pad(Input.UP)
  elseif k == "down" then S.pad(Input.DOWN)
  elseif k == "left" then S.pad(Input.LEFT)
  elseif k == "right" then S.pad(Input.RIGHT)
  elseif k == "q" then S.pad(Input.L1)
  elseif k == "e" then S.pad(Input.R1)
  elseif k == "return" or k == "space" then S.pad(Input.A)
  elseif k == "x" then S.pad(Input.X)
  elseif k == "y" then S.pad(Input.Y)
  elseif k == "escape" or k == "backspace" then S.pad(Input.B) end
end

-- ============================================================
--  Icons
-- ============================================================
local function draw_icon(kind, cx, cy, r, colour, alpha)
  col(colour, alpha or 1)
  love.graphics.setLineWidth(1.6)
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
    love.graphics.polygon("fill", cx - r*0.20, cy - r*0.40, cx - r*0.20, cy + r*0.40, cx + r*0.45, cy)
  elseif kind == "comic" then
    love.graphics.rectangle("line", cx - r*0.75, cy - r*0.75, r*0.65, r*1.5, 2, 2)
    love.graphics.rectangle("line", cx + r*0.10, cy - r*0.75, r*0.65, r*1.5, 2, 2)
  elseif kind == "font" then
    love.graphics.line(cx - r*0.35, cy + r*0.35, cx - r*0.15, cy - r*0.55)
    love.graphics.line(cx - r*0.15, cy - r*0.55, cx + r*0.05, cy + r*0.35)
    love.graphics.line(cx - r*0.28, cy - r*0.05, cx - r*0.02, cy - r*0.05)
  elseif kind == "hex" then
    love.graphics.rectangle("line", cx - r*0.75, cy - r*0.75, r*1.5, r*1.5, 2, 2)
    for i = 0, 3 do
      love.graphics.line(cx - r*0.55, cy - r*0.55 + i * r*0.36, cx + r*0.55, cy - r*0.55 + i * r*0.36)
    end
  elseif kind == "magnifier" then
    love.graphics.circle("line", cx - r*0.15, cy - r*0.15, r*0.55)
    love.graphics.line(cx + r*0.25, cy + r*0.25, cx + r*0.75, cy + r*0.75)
  elseif kind == "gear" then
    for i = 0, 7 do
      local a = i * math.pi / 4
      love.graphics.line(cx + math.cos(a) * r*0.55, cy + math.sin(a) * r*0.55,
                         cx + math.cos(a) * r*0.90, cy + math.sin(a) * r*0.90)
    end
    love.graphics.circle("line", cx, cy, r*0.55)
    love.graphics.circle("line", cx, cy, r*0.22)
  elseif kind == "eye" then
    love.graphics.ellipse("line", cx, cy, r*1.0, r*0.55)
    love.graphics.circle("fill", cx, cy, r*0.28)
  else
    love.graphics.circle("line", cx, cy, r*0.80)
  end
  love.graphics.setLineWidth(1)
end

-- ============================================================
--  Status pill
-- ============================================================
local function status_label(p)
  local st = status[p.id] or "missing"
  local is_off = PR.is_disabled(p.id)
  if is_off then return "DISABLED", GRY end
  if st == "installed" then return "READY", GRN end
  if st == "missing" then return "NOT INSTALLED", RED end
  if st == "downloading" then
    return string.format("%.0f%%", (progress[p.id] or 0) * 100), AMB
  end
  if st == "installing" then return "INSTALLING", AMB end
  if st == "error" then return "ERROR", RED end
  return "?", GRY
end

local function draw_status_pill(x_right, cy, label, colour)
  local f = A.font(A.FONT_MONO, 8)
  love.graphics.setFont(f)
  local tw = f:getWidth(label) + 18
  local bx = x_right - tw
  local by = cy - 9
  col({colour[1]*0.20, colour[2]*0.20, colour[3]*0.20}, 1)
  love.graphics.rectangle("fill", bx, by, tw, 18, 9, 9)
  col(colour, 0.9)
  love.graphics.setLineWidth(1)
  love.graphics.rectangle("line", bx + 0.5, by + 0.5, tw - 1, 17, 9, 9)
  love.graphics.setLineWidth(1)
  col(colour, 1)
  love.graphics.circle("fill", bx + 8, by + 9, 2)
  col({1,1,1}, 1)
  love.graphics.printf(label, bx + 14, by + 5, tw - 16, "left")
end

-- ============================================================
--  List view
-- ============================================================
local ROW_H = 68
local ROW_GAP = 6

local function draw_list()
  love.graphics.setFont(A.font(A.FONT_TITLE, 20))
  col(PURP_HI, 1)
  love.graphics.printf("FGD-X PLUGINS", 0, Frame.TOP_H + 8, W, "center")

  love.graphics.setFont(A.font(A.FONT_MONO, 9))
  col(PURP, 0.7)
  love.graphics.printf(#PLUGINS .. " plugins  \194\183  L1/R1 to jump",
    0, Frame.TOP_H + 32, W, "center")

  if #PLUGINS == 0 then
    col(State.theme.text_dim, 0.8)
    love.graphics.setFont(A.font(A.FONT_BODY, 12))
    love.graphics.printf("no plugins available", 0, H/2, W, "center")
    Frame.draw_top("FGD", "plugins")
    Frame.draw_bottom({ { key = "b", label = "Back" } })
    return
  end

  local vp_y = Frame.TOP_H + 52
  local vp_h = H - Frame.BOTTOM_H - vp_y - 4

  local total_h = #PLUGINS * (ROW_H + ROW_GAP)
  local max_scroll = math.max(0, total_h - vp_h)

  local sel_top = (sel - 1) * (ROW_H + ROW_GAP)
  local sel_bot = sel_top + ROW_H
  local MARGIN = 8
  if sel_top - MARGIN < scroll then scroll = math.max(0, sel_top - MARGIN) end
  if sel_bot + MARGIN > scroll + vp_h then
    scroll = math.min(max_scroll, sel_bot + MARGIN - vp_h)
  end
  scroll = math.max(0, math.min(max_scroll, scroll))

  love.graphics.setScissor(0, vp_y, W, vp_h)
  for i, p in ipairs(PLUGINS) do
    local y = vp_y + (i - 1) * (ROW_H + ROW_GAP) - scroll
    if y + ROW_H > vp_y and y < vp_y + vp_h then
      local focused = (i == sel)
      local c = p.colour or PURP
      local x = 20
      local w = W - 40

      if focused then
        col(c, 0.18)
        love.graphics.rectangle("fill", x, y, w, ROW_H, 4, 4)
        col(c, 0.95)
        love.graphics.setLineWidth(1.6)
        love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, ROW_H - 1, 4, 4)
        love.graphics.setLineWidth(1)
        D.corner_ticks(x + 6, y + 6, w - 12, ROW_H - 12, 10, c, 0.9)
      else
        col({0.030, 0.026, 0.040}, 0.9)
        love.graphics.rectangle("fill", x, y, w, ROW_H, 4, 4)
        col(c, 0.25)
        love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, ROW_H - 1, 4, 4)
      end

      local icx = x + 32
      local icy = y + ROW_H / 2
      col({c[1]*0.20, c[2]*0.20, c[3]*0.20}, 0.95)
      love.graphics.circle("fill", icx, icy, 22)
      col(c, 0.9)
      love.graphics.circle("line", icx, icy, 22)
      draw_icon(p.icon or "plug", icx, icy, 14, c, 1)

      love.graphics.setFont(A.font(A.FONT_BODY_BOLD, 13))
      col(focused and {1,1,1} or c, 1)
      local name = p.name or "?"
      if #name > 28 then name = name:sub(1, 27) .. "." end
      love.graphics.print(name, x + 66, y + 8)

      love.graphics.setFont(A.font(A.FONT_MONO, 9))
      col(c, focused and 0.9 or 0.55)
      love.graphics.print(p.code or "FGD-????", x + 66, y + 26)

      love.graphics.setFont(A.font(A.FONT_BODY, 10))
      col(State.theme.text_dim, 0.85)
      local tag = (p.tagline or ""):sub(1, 42)
      love.graphics.print(tag, x + 66, y + 42)

      local label, colr = status_label(p)
      draw_status_pill(x + w - 12, y + ROW_H / 2, label, colr)
    end
  end
  love.graphics.setScissor()

  if max_scroll > 0 then
    local track_h = vp_h - 8
    local thumb_h = math.max(24, track_h * (vp_h / total_h))
    local thumb_y = vp_y + 4 + (track_h - thumb_h) * (scroll / max_scroll)
    col(PURP_HI, 0.55)
    love.graphics.rectangle("fill", W - 6, thumb_y, 3, thumb_h, 1, 1)
  end

  Frame.draw_top("FGD", "plugins")
  Frame.draw_bottom({
    { key = "l1",  label = "Prev" },
    { key = "r1",  label = "Next" },
    { key = "a",   label = "Details" },
    { key = "y",   label = "On/Off" },
    { key = "b",   label = "Back" },
  })
end

-- ============================================================
--  Detail - Summary
-- ============================================================
local function draw_summary(p, y0, h0)
  local c = p.colour or PURP
  local th = State.theme
  local X = 20
  local W_content = W - 40

  love.graphics.setScissor(X, y0, W_content, h0)
  local y = y0 - sum_scroll

  local hero_h = 84
  col({0.030, 0.020, 0.045}, 0.95)
  love.graphics.rectangle("fill", X, y, W_content, hero_h, 5, 5)
  col(c, 0.6)
  love.graphics.setLineWidth(1.2)
  love.graphics.rectangle("line", X + 0.5, y + 0.5, W_content - 1, hero_h - 1, 5, 5)
  love.graphics.setLineWidth(1)

  local icx = X + 52
  local icy = y + hero_h / 2
  col({c[1]*0.25, c[2]*0.25, c[3]*0.25}, 0.95)
  love.graphics.circle("fill", icx, icy, 30)
  col(c, 0.95)
  love.graphics.setLineWidth(1.4)
  love.graphics.circle("line", icx, icy, 30)
  love.graphics.setLineWidth(1)
  draw_icon(p.icon or "plug", icx, icy, 20, c, 1)

  love.graphics.setFont(A.font(A.FONT_TITLE, 17))
  col(c, 1)
  love.graphics.print(p.name or "?", X + 96, y + 10)

  love.graphics.setFont(A.font(A.FONT_MONO, 9))
  col(c, 0.8)
  love.graphics.print(p.code or "FGD-????", X + 96, y + 32)

  love.graphics.setFont(A.font(A.FONT_BODY, 10))
  col(th.text, 0.9)
  love.graphics.print((p.tagline or ""):sub(1, 46), X + 96, y + 48)

  love.graphics.setFont(A.font(A.FONT_MONO, 9))
  col(th.text_dim, 0.85)
  love.graphics.print("by " .. (p.author or "sirpips") ..
    "  v" .. (p.version or "?") .. "  \194\183  " .. (p.source or "?"),
    X + 96, y + 66)

  local label, colr = status_label(p)
  draw_status_pill(X + W_content - 12, y + 22, label, colr)

  y = y + hero_h + 8

  local desc = p.description or ""
  if desc ~= "" then
    love.graphics.setFont(A.font(A.FONT_BODY, 10))
    local _, dh = love.graphics.getFont():getWrap(desc, W_content - 24)
    local box_h = math.max(50, dh + 34)
    col({0.025, 0.020, 0.035}, 0.9)
    love.graphics.rectangle("fill", X, y, W_content, box_h, 4, 4)
    col(c, 0.45)
    love.graphics.rectangle("line", X + 0.5, y + 0.5, W_content - 1, box_h - 1, 4, 4)
    love.graphics.setFont(A.font(A.FONT_MONO, 9))
    col(c, 0.9)
    love.graphics.print("DESCRIPTION", X + 12, y + 6)
    col(c, 0.3)
    love.graphics.rectangle("fill", X + 12, y + 20, W_content - 24, 1)
    love.graphics.setFont(A.font(A.FONT_BODY, 10))
    col(th.text, 0.95)
    love.graphics.printf(desc, X + 12, y + 26, W_content - 24, "left")
    y = y + box_h + 8
  end

  if p.features and #p.features > 0 then
    local fh = 26 + #p.features * 16
    col({0.025, 0.020, 0.035}, 0.9)
    love.graphics.rectangle("fill", X, y, W_content, fh, 4, 4)
    col(c, 0.45)
    love.graphics.rectangle("line", X + 0.5, y + 0.5, W_content - 1, fh - 1, 4, 4)
    love.graphics.setFont(A.font(A.FONT_MONO, 9))
    col(c, 0.9)
    love.graphics.print("FEATURES", X + 12, y + 6)
    col(c, 0.3)
    love.graphics.rectangle("fill", X + 12, y + 20, W_content - 24, 1)
    love.graphics.setFont(A.font(A.FONT_BODY, 10))
    local fy = y + 26
    for _, feat in ipairs(p.features) do
      col(GRN, 1)
      love.graphics.print(">", X + 14, fy)
      col(th.text, 0.95)
      love.graphics.print(feat, X + 26, fy)
      fy = fy + 16
    end
    y = y + fh + 8
  end

  if p.dependencies and #p.dependencies > 0 then
    local dh2 = 26 + #p.dependencies * 15
    col({0.025, 0.020, 0.035}, 0.9)
    love.graphics.rectangle("fill", X, y, W_content, dh2, 4, 4)
    col(c, 0.45)
    love.graphics.rectangle("line", X + 0.5, y + 0.5, W_content - 1, dh2 - 1, 4, 4)
    love.graphics.setFont(A.font(A.FONT_MONO, 9))
    col(c, 0.9)
    love.graphics.print("REQUIRES", X + 12, y + 6)
    col(c, 0.3)
    love.graphics.rectangle("fill", X + 12, y + 20, W_content - 24, 1)
    local dy = y + 26
    for _, dep in ipairs(p.dependencies) do
      local ok = true
      if dep ~= "built-in engine" then
        ok = (sh.exec("command -v " .. dep .. " >/dev/null 2>&1") == 0)
      end
      love.graphics.setFont(A.font(A.FONT_MONO, 9))
      if ok then col(GRN, 1); love.graphics.print("OK", X + 14, dy)
      else col(RED, 1); love.graphics.print("--", X + 14, dy) end
      love.graphics.setFont(A.font(A.FONT_BODY, 10))
      col(th.text, 0.95)
      love.graphics.print(dep, X + 36, dy)
      dy = dy + 15
    end
    y = y + dh2 + 8
  end

  local info_h = 72
  col({0.025, 0.020, 0.035}, 0.9)
  love.graphics.rectangle("fill", X, y, W_content, info_h, 4, 4)
  col(c, 0.45)
  love.graphics.rectangle("line", X + 0.5, y + 0.5, W_content - 1, info_h - 1, 4, 4)
  love.graphics.setFont(A.font(A.FONT_MONO, 9))
  col(c, 0.9)
  love.graphics.print("INFO", X + 12, y + 6)
  col(c, 0.3)
  love.graphics.rectangle("fill", X + 12, y + 20, W_content - 24, 1)
  love.graphics.setFont(A.font(A.FONT_MONO, 9))
  col(th.text_dim, 0.85)
  love.graphics.print("USAGE", X + 14, y + 26)
  col(th.text, 0.9)
  love.graphics.print((p.usage or "-"):sub(1, 40), X + 66, y + 26)
  col(th.text_dim, 0.85)
  love.graphics.print("LICENSE", X + 14, y + 42)
  col(th.text, 0.9)
  love.graphics.print(p.license or "-", X + 66, y + 42)
  col(th.text_dim, 0.85)
  love.graphics.print("CATEGORY", X + 14, y + 58)
  col(th.text, 0.9)
  love.graphics.print(p.category or "-", X + 66, y + 58)

  y = y + info_h + 8

  if p.documentation and p.documentation ~= "" then
    love.graphics.setFont(A.font(A.FONT_BODY, 11))
    local _, dwh = love.graphics.getFont():getWrap(p.documentation, W_content - 24)
    local doc_h = math.max(80, dwh + 40)
    col({0.025, 0.020, 0.035}, 0.9)
    love.graphics.rectangle("fill", X, y, W_content, doc_h, 4, 4)
    col(c, 0.45)
    love.graphics.rectangle("line", X + 0.5, y + 0.5, W_content - 1, doc_h - 1, 4, 4)
    love.graphics.setFont(A.font(A.FONT_MONO, 9))
    col(c, 0.9)
    love.graphics.print("DOCUMENTATION", X + 12, y + 6)
    col(c, 0.3)
    love.graphics.rectangle("fill", X + 12, y + 20, W_content - 24, 1)
    love.graphics.setFont(A.font(A.FONT_BODY, 11))
    col(th.text, 0.92)
    love.graphics.printf(p.documentation, X + 12, y + 28, W_content - 24, "left")
    y = y + doc_h + 8
  end

  sum_max = math.max(0, y - y0 - h0)
  if sum_scroll > sum_max then sum_scroll = sum_max end
  love.graphics.setScissor()

  if sum_max > 0 then
    local track_h = h0 - 8
    local thumb_h = math.max(20, track_h * (h0 / (h0 + sum_max)))
    local thumb_y = y0 + 4 + (track_h - thumb_h) * (sum_scroll / sum_max)
    col(PURP_HI, 0.55)
    love.graphics.rectangle("fill", W - 8, thumb_y, 3, thumb_h, 1, 1)
  end
end

-- ============================================================
--  Detail - Actions
-- ============================================================
local function draw_switch(cx, cy, on, enabled)
  local w, h = 44, 20
  local x, y = cx - w/2, cy - h/2
  local bg
  if not enabled then bg = {0.28, 0.28, 0.32}
  elseif on then bg = GRN
  else bg = {0.55, 0.28, 0.30} end

  col({0.05, 0.05, 0.08}, 1)
  love.graphics.rectangle("fill", x, y, w, h, h/2, h/2)
  if on and enabled then
    col({bg[1]*0.5, bg[2]*0.5, bg[3]*0.5}, 0.85)
    love.graphics.rectangle("fill", x + 2, y + 2, w - 4, h - 4, (h-4)/2, (h-4)/2)
  end
  col(bg, enabled and 0.9 or 0.5)
  love.graphics.setLineWidth(1.2)
  love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, h/2, h/2)
  love.graphics.setLineWidth(1)
  local knob_x = on and (x + w - h/2) or (x + h/2)
  col({0.95, 0.95, 0.97}, enabled and 1 or 0.55)
  love.graphics.circle("fill", knob_x, cy, h/2 - 2)
end

local function build_actions(p)
  local items = {}
  local st = status[p.id] or "missing"
  local installed = (st == "installed" or st == "disabled")

  items[#items+1] = {
    kind = "switch",
    label = "Plugin enabled",
    hint = installed and "Y to toggle" or "not installed",
    enabled = installed,
    colour = installed and (PR.is_disabled(p.id) and AMB or GRN) or GRY,
  }

  if not p.builtin then
    if st == "missing" or st == "error" then
      items[#items+1] = {
        kind = "install", label = "INSTALL",
        hint = "Download and install from catalogue",
        colour = GRN,
      }
    elseif st == "downloading" then
      items[#items+1] = {
        kind = "cancel", label = "CANCEL DOWNLOAD",
        hint = string.format("%.0f%% downloaded",
          (progress[p.id] or 0) * 100),
        colour = RED,
      }
    elseif st == "installing" then
      items[#items+1] = {
        kind = "wait", label = "INSTALLING...",
        hint = "do not power off", colour = AMB,
      }
    elseif st == "installed" or st == "disabled" then
      items[#items+1] = {
        kind = "reinstall", label = "REINSTALL",
        hint = "Remove and re-download",
        colour = AMB,
      }
      items[#items+1] = {
        kind = "uninstall", label = "UNINSTALL",
        hint = "Remove from system",
        colour = RED,
      }
    end
  end
  return items
end

local function draw_actions(p, y0, h0)
  local c = p.colour or PURP
  local th = State.theme
  local X = 20
  local W_content = W - 40

  love.graphics.setScissor(X, y0, W_content, h0)
  local y = y0 - act_scroll

  local items = build_actions(p)
  p.__actions = items
  if act_sel < 1 then act_sel = 1 end
  if act_sel > #items then act_sel = #items end

  -- ===== Actions list =====
  local row_h = 42
  local list_h = #items * row_h + 12

  col({0.025, 0.020, 0.035}, 0.9)
  love.graphics.rectangle("fill", X, y, W_content, list_h, 4, 4)
  col(c, 0.45)
  love.graphics.rectangle("line", X + 0.5, y + 0.5, W_content - 1, list_h - 1, 4, 4)

  local ry = y + 6
  for i, it in ipairs(items) do
    local focused = (i == act_sel)
    local rc = it.colour or c
    local rx = X + 6
    local rw = W_content - 12

    if focused then
      col(rc, 0.18)
      love.graphics.rectangle("fill", rx, ry, rw, row_h - 2, 4, 4)
      col(rc, 0.9)
      love.graphics.setLineWidth(1.5)
      love.graphics.rectangle("line", rx + 0.5, ry + 0.5, rw - 1, row_h - 3, 4, 4)
      love.graphics.setLineWidth(1)
    end

    love.graphics.setFont(A.font(A.FONT_BODY_BOLD, 12))
    col(focused and {1,1,1} or rc, 1)
    love.graphics.print(it.label, rx + 14, ry + 8)

    love.graphics.setFont(A.font(A.FONT_BODY, 9))
    col(th.text_dim, 0.85)
    love.graphics.print(it.hint, rx + 14, ry + 24)

    if it.kind == "switch" then
      local sw_cx = rx + rw - 44
      local sw_cy = ry + (row_h - 2) / 2
      draw_switch(sw_cx, sw_cy, it.enabled and not PR.is_disabled(p.id), it.enabled)
      BI.draw(rx + rw - 90, sw_cy, 8, "y")
    elseif it.kind ~= "wait" then
      BI.draw(rx + rw - 24, ry + (row_h - 2) / 2, 8, "a")
    end

    ry = ry + row_h
  end
  y = y + list_h + 8

  -- ===== History / Log =====
  local hist = plugin_read_log(p, 200)
  local line_h = 13
  local visible = math.max(4, math.min(30, #hist))
  local hist_h = math.max(80, 30 + visible * line_h)

  col({0.025, 0.020, 0.035}, 0.9)
  love.graphics.rectangle("fill", X, y, W_content, hist_h, 4, 4)
  col(c, 0.45)
  love.graphics.rectangle("line", X + 0.5, y + 0.5, W_content - 1, hist_h - 1, 4, 4)
  love.graphics.setFont(A.font(A.FONT_MONO, 9))
  col(c, 0.9)
  love.graphics.print("LOG / HISTORY", X + 12, y + 6)
  col(c, 0.3)
  love.graphics.rectangle("fill", X + 12, y + 20, W_content - 24, 1)

  love.graphics.setFont(A.font(A.FONT_MONO, 9))
  if #hist == 0 then
    col(th.text_dim, 0.7)
    love.graphics.print("(no events yet)", X + 14, y + 30)
  else
    local yy = y + 26
    for i = 1, math.min(#hist, visible) do
      local line = hist[i] or ""
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
      yy = yy + line_h
    end
  end

  y = y + hist_h + 8

  act_max = math.max(0, y - y0 - h0)
  if act_scroll > act_max then act_scroll = act_max end

  -- Auto-scroll to keep focused action visible
  local focus_y = 6 + (act_sel - 1) * row_h
  local focus_bot = focus_y + row_h
  if focus_y < act_scroll then act_scroll = focus_y end
  if focus_bot > act_scroll + h0 - 8 then act_scroll = focus_bot - h0 + 8 end
  if act_scroll < 0 then act_scroll = 0 end
  if act_scroll > act_max then act_scroll = act_max end

  love.graphics.setScissor()

  if act_max > 0 then
    local track_h = h0 - 8
    local thumb_h = math.max(20, track_h * (h0 / (h0 + act_max)))
    local thumb_y = y0 + 4 + (track_h - thumb_h) * (act_scroll / act_max)
    col(PURP_HI, 0.55)
    love.graphics.rectangle("fill", W - 8, thumb_y, 3, thumb_h, 1, 1)
  end
end

-- ============================================================
--  Detail - main
-- ============================================================
local function draw_tab_bar(y)
  local x = 20
  local w = W - 40
  local tab_w = w / TAB_COUNT
  for i = 1, TAB_COUNT do
    local tx = x + (i - 1) * tab_w
    local active = (i == tab)
    if active then
      col(PURP, 0.25)
      love.graphics.rectangle("fill", tx, y, tab_w - 4, 26, 4, 4)
      col(PURP_HI, 0.95)
      love.graphics.setLineWidth(1.5)
      love.graphics.rectangle("line", tx + 0.5, y + 0.5, tab_w - 5, 25, 4, 4)
      love.graphics.setLineWidth(1)
    else
      col({0.030, 0.026, 0.040}, 0.85)
      love.graphics.rectangle("fill", tx, y, tab_w - 4, 26, 4, 4)
      col(PURP, 0.30)
      love.graphics.rectangle("line", tx + 0.5, y + 0.5, tab_w - 5, 25, 4, 4)
    end
    love.graphics.setFont(A.font(A.FONT_BODY_BOLD, 11))
    col(active and PURP_HI or PURP, active and 1 or 0.7)
    love.graphics.printf(TAB_NAMES[i], tx, y + 6, tab_w - 4, "center")
  end
end

local function draw_detail()
  local p = PLUGINS[detail_idx]
  if not p then mode = "list"; return end

  love.graphics.setFont(A.font(A.FONT_MONO, 9))
  col(PURP, 0.75)
  love.graphics.printf("PLUGIN " .. detail_idx .. " / " .. #PLUGINS ..
    "  \194\183  " .. (p.code or "FGD-????"),
    0, Frame.TOP_H + 4, W, "center")

  local tab_y = Frame.TOP_H + 20
  draw_tab_bar(tab_y)

  local content_y = tab_y + 34
  local content_h = H - Frame.BOTTOM_H - content_y - 4

  local ok, err = pcall(function()
    if tab == 1 then
      draw_summary(p, content_y, content_h)
    else
      draw_actions(p, content_y, content_h)
    end
  end)
  love.graphics.setScissor()
  if not ok then
    log_err("detail", err)
    col({0.030, 0.010, 0.015}, 0.95)
    love.graphics.rectangle("fill", 20, content_y, W - 40, content_h, 5, 5)
    col({1.0, 0.4, 0.4}, 1)
    love.graphics.setFont(A.font(A.FONT_BODY_BOLD, 14))
    love.graphics.print("DETAIL VIEW crashed", 40, content_y + 18)
    love.graphics.setFont(A.font(A.FONT_MONO, 10))
    col({1.0, 0.85, 0.85}, 0.95)
    love.graphics.printf(tostring(err), 40, content_y + 46, W - 80, "left")
  end

  Frame.draw_top("FGD", "plugins")
  Frame.draw_bottom({
    { key = "l1",  label = "Prev" },
    { key = "r1",  label = "Next" },
    { key = "l2",  label = "Tab" },
    { key = "a",   label = "Run" },
    { key = "x",   label = "Manage" },
    { key = "y",   label = "On/Off" },
    { key = "b",   label = "Back" },
  })
end

-- ============================================================
--  Main draw
-- ============================================================
function S.draw()
  D.bg()
  col(PURP, 0.05)
  for gy = Frame.TOP_H, H - Frame.BOTTOM_H, 20 do
    for gx = 0, W, 20 do love.graphics.rectangle("fill", gx, gy, 1, 1) end
  end

  local ok, err = pcall(function()
    if mode == "list" then draw_list() else draw_detail() end
  end)
  love.graphics.setScissor()
  if not ok then log_err("draw", err) end

  Modal.draw()
  D.scanlines(W, H, 0.06)
end

return S
