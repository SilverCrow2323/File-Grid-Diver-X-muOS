-- services/catalog.lua -- load the Minoru Store catalogue.
-- Tries remote JSON, falls back to a local cache, then to a built-in
-- embedded copy. Never blocks the UI: uses a background download.
local sh   = require("core.sh")
local JSON = require("core.json")

local M = {}

M.REMOTE_URL = "https://raw.githubusercontent.com/SilverCrow2323/File-Grid-Diver-X-muOS/main/data/catalog.json"
M.LOCAL_FILE = "data/catalog.json"         -- embedded (shipped with app)
M.CACHE_FILE = "data/catalog.cache.json"   -- downloaded from remote
M.STATUS_FILE = "data/catalog.status"      -- background download marker

local data_cache = nil

-- ============================================================
--  Reading
-- ============================================================
local function read_json_file(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local c = f:read("*a"); f:close()
  if not c or #c < 10 then return nil end
  local ok, d = pcall(JSON.decode, c)
  if ok and type(d) == "table" then return d end
  return nil
end

-- Returns the newest valid copy (cache > local)
function M.load()
  if data_cache then return data_cache end
  local d = read_json_file(M.CACHE_FILE)
  if not d then d = read_json_file(M.LOCAL_FILE) end
  if d then data_cache = d end
  return data_cache
end

function M.invalidate()
  data_cache = nil
  M.load()
end

function M.all_plugins()
  local d = M.load()
  return d and d.plugins or {}
end

function M.all_apps()
  local d = M.load()
  return d and d.muos_apps or {}
end

function M.announcements()
  local d = M.load()
  return d and d.announcements or {}
end

-- ============================================================
--  Background remote refresh
-- ============================================================
-- Start a detached download of the remote catalogue.
-- The result lands in CACHE_FILE; caller should poll M.is_refreshing().
function M.refresh_async()
  sh.exec("mkdir -p data")
  sh.exec("rm -f " .. sh.shq(M.STATUS_FILE))

  local script = "data/catalog_refresh.sh"
  local f = io.open(script, "w")
  if not f then return false end
  f:write("#!/bin/sh\n")
  f:write("URL=" .. sh.shq(M.REMOTE_URL) .. "\n")
  f:write("OUT=" .. sh.shq(M.CACHE_FILE) .. "\n")
  f:write("STATUS=" .. sh.shq(M.STATUS_FILE) .. "\n")
  f:write("TMP=$OUT.part\n")
  f:write("curl -L --fail --silent --show-error -o \"$TMP\" \"$URL\" 2>/dev/null\n")
  f:write("if [ -s \"$TMP\" ]; then\n")
  f:write("  mv \"$TMP\" \"$OUT\"\n")
  f:write("  echo ok > \"$STATUS\"\n")
  f:write("else\n")
  f:write("  rm -f \"$TMP\"\n")
  f:write("  echo fail > \"$STATUS\"\n")
  f:write("fi\n")
  f:close()
  sh.exec("chmod +x " .. sh.shq(script))
  local cmd = "(setsid sh " .. sh.shq(script) .. " </dev/null >/dev/null 2>&1 &) " ..
    "|| (nohup sh " .. sh.shq(script) .. " >/dev/null 2>&1 &) " ..
    "|| (sh " .. sh.shq(script) .. " >/dev/null 2>&1 &)"
  os.execute(cmd)
  return true
end

function M.is_refreshing()
  local f = io.open(M.STATUS_FILE, "r")
  if f then f:close(); return false end
  return true
end

function M.last_refresh_ok()
  local f = io.open(M.STATUS_FILE, "r")
  if not f then return nil end
  local s = f:read("*l") or ""
  f:close()
  return s == "ok"
end

function M.clear_status()
  sh.exec("rm -f " .. sh.shq(M.STATUS_FILE))
end

-- ============================================================
--  Helpers
-- ============================================================
function M.plugin_by_id(id)
  for _, p in ipairs(M.all_plugins()) do
    if p.id == id then return p end
  end
  return nil
end

function M.app_by_key(key)
  for _, a in ipairs(M.all_apps()) do
    if a.key == key then return a end
  end
  return nil
end

-- Most recently added item across both lists
function M.latest()
  local newest_plugin, newest_plugin_date = nil, ""
  for _, p in ipairs(M.all_plugins()) do
    local d = p.date_added or ""
    if d > newest_plugin_date then
      newest_plugin = p
      newest_plugin_date = d
    end
  end
  local newest_app, newest_app_date = nil, ""
  for _, a in ipairs(M.all_apps()) do
    local d = a.date_added or ""
    if d > newest_app_date then
      newest_app = a
      newest_app_date = d
    end
  end
  if newest_plugin_date >= newest_app_date and newest_plugin then
    return newest_plugin, "plugin"
  elseif newest_app then
    return newest_app, "app"
  end
  return nil, nil
end

-- Should we auto-refresh? True if cache is missing or older than 24h
function M.should_auto_refresh()
  local f = io.open(M.CACHE_FILE, "r")
  if not f then return true end  -- never fetched
  local mtime = f:seek("end")    -- dummy to keep handle valid
  f:close()
  -- Use shell stat to get mtime reliably
  local out = require("core.sh").read("stat -c %Y " .. require("core.sh").shq(M.CACHE_FILE) .. " 2>/dev/null")
  local mtime_num = tonumber(out or "0") or 0
  local now = os.time()
  if now - mtime_num > 24 * 3600 then return true end
  return false
end


-- ============================================================
--  Auto-refresh on boot + app version check (user-toggleable)
-- ============================================================
function M.should_refresh()
  local ok, Store = pcall(require, "core.settings_store")
  if not ok then return true end
  return Store.get("update", "auto_catalog") ~= false
end

function M.should_check_app()
  local ok, Store = pcall(require, "core.settings_store")
  if not ok then return true end
  return Store.get("update", "auto_app_check") ~= false
end

-- Lancia il refresh del catalogo in background (non bloccante).
-- Usa lo stesso meccanismo di refresh_async ma con un nome dedicato
-- per chiarezza di log.
function M.refresh_on_boot()
  if not M.should_refresh() then
    print("[catalog] auto-refresh disabilitato dall'utente")
    return
  end
  print("[catalog] refresh on boot -- avvio in background")
  return M.refresh_async()
end

-- Controllo versione app: scrive il risultato in data/update_check.result.
-- Non bloccante: lancia uno script detached. Il risultato va letto con
-- M.poll_update_result() al tick successivo.
function M.check_app_version_async(local_ver)
  if not M.should_check_app() then return end
  local sh = require("core.sh")
  local tmp = "data/update_check.result"
  os.execute("mkdir -p data")
  os.remove(tmp)
  local script = "data/update_check.sh"
  local f = io.open(script, "w")
  if not f then return end
  f:write("#!/bin/sh\n")
  f:write("TMP=/tmp/fgd_catalog_probe.tmp\n")
  f:write("curl -sL --max-time 6 " .. sh.shq(M.REMOTE_URL) .. " -o \"$TMP\" 2>/dev/null\n")
  f:write("if [ -s \"$TMP\" ]; then\n")
  f:write("  grep -o '\"app_version\"[^,}]*' \"$TMP\" | head -1 | sed 's/.*\"\\(.*\\)\"/\\1/' > " .. sh.shq(tmp) .. "\n")
  f:write("  rm -f \"$TMP\"\n")
  f:write("fi\n")
  f:close()
  os.execute("chmod +x " .. sh.shq(script))
  os.execute("(setsid sh " .. sh.shq(script) .. " </dev/null >/dev/null 2>&1 &) " ..
    "|| (nohup sh " .. sh.shq(script) .. " >/dev/null 2>&1 &) " ..
    "|| (sh " .. sh.shq(script) .. " >/dev/null 2>&1 &)")
end

-- Da chiamare in love.update: se il file risultato esiste, notifica e cancella.
function M.poll_update_result(local_ver)
  local f = io.open("data/update_check.result", "r")
  if not f then return end
  local remote = (f:read("*l") or ""):gsub("%s+", "")
  f:close()
  os.remove("data/update_check.result")
  os.remove("data/update_check.sh")
  if remote ~= "" and remote ~= local_ver then
    local ok, N = pcall(require, "ui.notify")
    if ok then
      N.show("info", "Aggiornamento disponibile: " .. remote, 4.5)
    end
    print("[catalog] update available: " .. remote .. " (local " .. local_ver .. ")")
  else
    print("[catalog] app up to date (" .. (local_ver or "?") .. ")")
  end
end

return M
