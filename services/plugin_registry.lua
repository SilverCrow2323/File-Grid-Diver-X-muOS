-- services/plugin_registry.lua -- enable / disable state for extenders.
-- A disabled extender is not consulted by the file manager.
local JSON = require("core.json")
local M = {}

local FILE = "data/plugin_disabled.json"

local function load()
  local f = io.open(FILE, "r")
  if not f then return {} end
  local c = f:read("*a"); f:close()
  local ok, d = pcall(JSON.decode, c)
  if ok and type(d) == "table" then return d end
  return {}
end

local function save(d)
  os.execute("mkdir -p data")
  local f = io.open(FILE, "w")
  if not f then return false end
  f:write(JSON.encode(d)); f:close()
  return true
end

function M.is_disabled(key)
  return load()[key] == true
end

function M.set_disabled(key, disabled)
  local d = load()
  if disabled then d[key] = true
  else d[key] = nil end
  return save(d)
end

function M.toggle(key)
  local d = load()
  if d[key] then d[key] = nil else d[key] = true end
  save(d)
  return d[key] == true
end

function M.all_disabled()
  return load()
end

return M
