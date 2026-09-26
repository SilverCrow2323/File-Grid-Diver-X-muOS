-- plugins/loader.lua -- scan, permission-check, sandbox-load.
-- Uses ui/perm_dialog for the consent screen. Each plugin gets:
--   man.screen        -> its real screen (or the perm dialog if missing)
--   man.manage_screen -> always the perm dialog (reopen from plugins list)
local API = require("plugins.api")
local PermDialog = require("ui.perm_dialog")

local M = { all = {}, by_key = {} }

local function list_dirs()
  local out = {}
  local h = io.popen("ls -1d plugins/*/ 2>/dev/null")
  if not h then return out end
  for line in h:lines() do
    local pkg = line:match("plugins/([^/]+)/")
    if pkg then out[#out + 1] = pkg end
  end
  h:close()
  return out
end

local function read_manifest(pkg)
  local path = "plugins/" .. pkg .. "/plugin.lua"
  local chunk = love.filesystem.load(path)
  if not chunk then return nil, "load failed: " .. path end
  local ok, man = pcall(chunk)
  if not ok then return nil, "exec failed: " .. tostring(man) end
  if type(man) ~= "table" then return nil, "not a table: " .. path end
  if not man.entry then return nil, "missing .entry: " .. path end
  return man, nil
end

function M.scan()
  M.all = {}
  M.by_key = {}

  local dirs = list_dirs()
  for _, pkg in ipairs(dirs) do
    local man, err = read_manifest(pkg)
    if not man then
      print("[loader] skip " .. pkg .. ": " .. tostring(err))
    else
      man.pkg         = pkg
      man.permissions = man.permissions or {}
      man.missing     = API.missing(pkg, man.permissions)

      -- Always create the manage screen
      local mkey = (man.key or pkg) .. "__manage"
      man.manage_key    = mkey
      man.manage_screen = PermDialog.make(pkg, man, man.permissions,
        { manage_only = true })

      -- Show the consent screen only if there are missing permissions
      -- AND the user has not yet made a decision for this plugin.
      if #man.missing > 0 and not API.is_decided(pkg) then
        man.screen = PermDialog.make(pkg, man, man.permissions)
        man.needs_perm = true
        print("[loader] " .. pkg .. " needs permission: " ..
          table.concat(man.missing, ", "))
      else
        -- Load with only the granted permissions. Denied permissions
        -- are silently unavailable to the plugin sandbox.
        local granted = API.granted(pkg)
        local entry_path = "plugins/" .. pkg .. "/" .. man.entry .. ".lua"
        local screen, lerr = API.load_plugin(pkg, entry_path, granted)
        if not screen then
          print("[loader] load FAIL " .. pkg .. ": " .. tostring(lerr))
          man.screen = nil
        else
          man.screen = screen
          man.needs_perm = false
          print("[loader] OK: " .. pkg .. " -> " .. (man.key or pkg))
        end
      end

      M.all[#M.all + 1] = man
      M.by_key[man.key or pkg] = man
    end
  end
end

function M.rescan()
  for name in pairs(package.loaded) do
    if name:sub(1, 8) == "plugins." and name:sub(1, 12) ~= "plugins.api"
       and name:sub(1, 15) ~= "plugins.loader" then
      package.loaded[name] = nil
    end
  end
  M.scan()
end

function M.get(key) return M.by_key[key] end
function M.list()     return M.all end

return M
