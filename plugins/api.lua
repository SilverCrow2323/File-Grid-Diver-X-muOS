-- plugins/api.lua -- plugin permission catalog and sandbox.
--
-- Design goal: make a plugin's reach VISIBLE and DECLARED, and stop
-- accidental damage from buggy plugins. This is not a jailbreak-proof
-- sandbox. A plugin that declares shell.exec can still do whatever
-- the OS lets it. That is the user's informed consent.
--
-- Permission catalog
--   filesystem.read   -- read files via io.open / io.lines
--   filesystem.write  -- create, modify or delete via io.open / io.remove
--   shell.exec        -- os.execute, io.popen, require("core.sh")
--   love.filesystem   -- full love.filesystem (read+write under save dir)
--
-- Any plugin that only uses the app's own services (services.fs,
-- services.trash, ui.*, core.*) does NOT need any permission. Those
-- wrappers are trusted: they belong to the app.

local JSON = require("core.json")

local M = {}

local PERM_FILE = "data/plugin_perms.json"

M.CATALOG = {
  ["filesystem.read"]  = "read files on the device",
  ["filesystem.write"] = "create, modify or delete files",
  ["shell.exec"]       = "run shell commands on the device",
  ["love.filesystem"]  = "read/write the app's data directory",
}

-- ----------------------------------------------------------------
--  Grant storage (data/plugin_perms.json)
-- ----------------------------------------------------------------
local function load_grants()
  local f = io.open(PERM_FILE, "r")
  if not f then return {} end
  local c = f:read("*a"); f:close()
  local ok, d = pcall(JSON.decode, c)
  if ok and type(d) == "table" then return d end
  return {}
end

local function save_grants(data)
  os.execute("mkdir -p data")
  local f = io.open(PERM_FILE, "w")
  if not f then return false end
  f:write(JSON.encode(data))
  f:close()
  return true
end

function M.granted(pkg)
  local all = load_grants()
  return all[pkg] or {}
end

function M.grant(pkg, perms)
  local all = load_grants()
  all[pkg] = all[pkg] or {}
  local seen = {}
  for _, p in ipairs(all[pkg]) do seen[p] = true end
  for _, p in ipairs(perms) do
    if not seen[p] then
      all[pkg][#all[pkg] + 1] = p
      seen[p] = true
    end
  end
  return save_grants(all)
end

function M.revoke(pkg)
  local all = load_grants()
  all[pkg] = nil
  return save_grants(all)
end

function M.missing(pkg, requested)
  local have = {}
  for _, p in ipairs(M.granted(pkg)) do have[p] = true end
  local out = {}
  for _, p in ipairs(requested or {}) do
    if not have[p] then out[#out + 1] = p end
  end
  return out
end

-- Whether the user has already decided on this plugin's permissions
-- (granted OR denied). Prevents the consent screen from re-appearing.
local DECIDED_FILE = "data/plugin_decided.json"
local function load_decided()
  local f = io.open(DECIDED_FILE, "r")
  if not f then return {} end
  local c = f:read("*a"); f:close()
  local ok, d = pcall(JSON.decode, c)
  if ok and type(d) == "table" then return d end
  return {}
end
local function save_decided(data)
  os.execute("mkdir -p data")
  local f = io.open(DECIDED_FILE, "w")
  if not f then return false end
  f:write(JSON.encode(data)); f:close()
  return true
end
function M.mark_decided(pkg)
  local d = load_decided(); d[pkg] = true; return save_decided(d)
end
function M.is_decided(pkg)
  return load_decided()[pkg] == true
end

-- ----------------------------------------------------------------
--  Sandbox environment
-- ----------------------------------------------------------------
local function has_perm(perms, key)
  for _, p in ipairs(perms or {}) do
    if p == key then return true end
  end
  return false
end

-- Write to the app's runtime log.
local function log_line(pkg, msg)
  local f = io.open("data/fgd_runtime.log", "a")
  if f then
    f:write(os.date("%Y-%m-%d %H:%M:%S ") .. "[plugin " .. pkg .. "] " ..
      msg .. "\n")
    f:close()
  end
end

-- Build the environment table for a plugin.
function M.build_env(pkg, perms)
  local can_read  = has_perm(perms, "filesystem.read")
  local can_write = has_perm(perms, "filesystem.write")
  local can_shell = has_perm(perms, "shell.exec")
  local can_lfs   = has_perm(perms, "love.filesystem")

  local env = {}

  -- Safe base
  env._G      = env
  env._VERSION = _VERSION
  env.assert   = assert
  env.error    = error
  env.ipairs   = ipairs
  env.next     = next
  env.pairs    = pairs
  env.pcall    = pcall
  env.xpcall   = xpcall
  env.select   = select
  env.type     = type
  env.tostring = tostring
  env.tonumber = tonumber
  env.unpack   = unpack or table.unpack
  env.setmetatable = setmetatable
  env.getmetatable = getmetatable
  env.rawequal = rawequal
  env.rawget   = rawget
  env.rawset   = rawset
  env.rawlen   = rawlen

  -- Safe libraries
  env.string    = string
  env.table     = table
  env.math      = math
  env.coroutine = coroutine
  if utf8 then env.utf8 = utf8 end
  if bit  then env.bit  = bit  end

  -- print -> log
  env.print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do
      parts[#parts + 1] = tostring(select(i, ...))
    end
    log_line(pkg, table.concat(parts, "\t"))
  end

  -- love (the graphics-adjacent subset is always allowed)
  env.love = {
    graphics = love.graphics,
    timer    = love.timer,
    audio    = love.audio,
    math     = love.math,
    event    = love.event,
    keyboard = love.keyboard,
    mouse    = love.mouse,
    window   = love.window,
    system   = love.system,
  }
  if can_lfs then
    env.love.filesystem = love.filesystem
  end

  -- io (gated)
  if can_read or can_write then
    local real_io = io
    env.io = {
      open = function(path, mode)
        mode = mode or "r"
        local wants_write = mode:match("[wa+]") ~= nil
        local wants_read  = mode:match("r") ~= nil
        if wants_write and not can_write then
          return nil, "permission denied: filesystem.write"
        end
        if wants_read and not can_read and not wants_write then
          return nil, "permission denied: filesystem.read"
        end
        return real_io.open(path, mode)
      end,
      lines = can_read and real_io.lines or nil,
      read  = can_read and real_io.read  or nil,
      write = can_write and real_io.write or nil,
    }
    if can_read then
      env.io.stdin  = real_io.stdin
      env.io.stdout = real_io.stdout
    end
  end

  -- os (safe subset always; execute/popen gated)
  env.os = {
    date    = os.date,
    time    = os.time,
    clock   = os.clock,
    difftime= os.difftime,
  }
  if can_read or can_write then
    env.os.remove = os.remove
    env.os.rename = os.rename
    env.os.tmpname = os.tmpname
  end
  if can_shell then
    env.os.execute = os.execute
    env.os.getenv  = os.getenv
    env.os.exit    = nil  -- never let a plugin kill the app
  end

  -- require (passthrough for app modules, sandbox for self-package)
  env.require = function(name)
    if name == "core.sh" then
      if not can_shell then
        error("permission denied: shell.exec (require core.sh)")
      end
      return require(name)
    end
    -- Self-package modules: sandbox them with the same env.
    local sub_pkg = name:match("^plugins%.([^%.]+)")
    if sub_pkg == pkg then
      return M.require_sandboxed(name, env, 0)
    end
    -- Cross-plugin require: deny
    if name:sub(1, 8) == "plugins." then
      error("cross-plugin require denied: " .. name)
    end
    -- Everything else: passthrough
    return require(name)
  end

  return env
end

-- ----------------------------------------------------------------
--  Sandboxed require + top-level load
-- ----------------------------------------------------------------
function M.require_sandboxed(name, env, depth)
  depth = depth or 0
  if depth > 12 then error("require depth exceeded for " .. name) end

  local cached = package.loaded[name]
  if cached ~= nil then return cached end

  local path = name:gsub("%.", "/") .. ".lua"
  local f = io.open(path, "r")
  if not f then
    -- Not a file we can sandbox; fall through to normal require.
    return require(name)
  end
  local src = f:read("*a"); f:close()

  local chunk, err = loadstring(src, "@" .. path)
  if not chunk then error(err) end
  setfenv(chunk, env)
  local result = chunk()
  if result == nil then result = true end
  package.loaded[name] = result
  return result
end

-- Load the entry file for a plugin inside the sandbox.
function M.load_plugin(pkg, entry_path, perms)
  local env = M.build_env(pkg, perms)
  local f = io.open(entry_path, "r")
  if not f then return nil, "cannot read " .. entry_path end
  local src = f:read("*a"); f:close()

  local chunk, err = loadstring(src, "@" .. entry_path)
  if not chunk then return nil, err end
  setfenv(chunk, env)
  local ok, result = pcall(chunk)
  if not ok then return nil, tostring(result) end
  if type(result) ~= "table" then
    return nil, "entry did not return a table"
  end
  return result, nil
end

return M
