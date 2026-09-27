-- core/log.lua - structured logging with levels and rotation.
--
-- Usage:
--   local LOG = require("core.log")
--   LOG.info("started")
--   LOG.warn("file not found: " .. path, "fs")
--   LOG.error("crash: " .. err, "main")
--
-- Level filter (debug < info < warn < error) can be set at runtime:
--   LOG.set_level("debug")
-- or via env var FGD_LOG=debug when launching the app.
--
-- Output: stderr (captured by launcher log) AND data/fgd_runtime.log
-- (with timestamp). Log is rotated to half-size when it exceeds 512 KB.

local M = {}

local LEVELS = { debug = 1, info = 2, warn = 3, error = 4 }
local current_level = LEVELS.info

local LOG_PATH  = "data/fgd_runtime.log"
local MAX_KB    = 512
local write_ctr = 0

local function env_level()
  local v = os.getenv("FGD_LOG")
  if v and LEVELS[v] then return LEVELS[v] end
  return nil
end

local function should_write(level)
  return LEVELS[level] and LEVELS[level] >= current_level
end

local function rotate()
  write_ctr = write_ctr + 1
  if write_ctr < 100 then return end
  write_ctr = 0
  local f = io.open(LOG_PATH, "r")
  if not f then return end
  local sz = f:seek("end")
  f:close()
  if sz <= MAX_KB * 1024 then return end
  local ok, sh = pcall(require, "core.sh")
  if ok and sh and sh.shq then
    os.execute("tail -c " .. (MAX_KB * 512) .. " " .. sh.shq(LOG_PATH) ..
      " > " .. sh.shq(LOG_PATH .. ".tmp") .. " 2>/dev/null && " ..
      "mv " .. sh.shq(LOG_PATH .. ".tmp") .. " " .. sh.shq(LOG_PATH))
  end
end

local function write(level, msg, tag)
  if not should_write(level) then return end
  local prefix = "[" .. level:upper() .. "]"
  if tag and tag ~= "" then prefix = prefix .. "[" .. tag .. "]" end
  local line = prefix .. " " .. tostring(msg)

  io.stderr:write(line .. "\n")
  io.stderr:flush()

  local f = io.open(LOG_PATH, "a")
  if f then
    f:write(os.date("%Y-%m-%d %H:%M:%S ") .. line .. "\n")
    f:close()
    rotate()
  end
end

function M.set_level(level)
  if LEVELS[level] then current_level = LEVELS[level] end
end

function M.get_level()
  for name, n in pairs(LEVELS) do
    if n == current_level then return name end
  end
  return "info"
end

function M.debug(msg, tag) write("debug", msg, tag) end
function M.info (msg, tag) write("info",  msg, tag) end
function M.warn (msg, tag) write("warn",  msg, tag) end
function M.error(msg, tag) write("error", msg, tag) end

do
  local lvl = env_level()
  if lvl then current_level = lvl end
end

return M
