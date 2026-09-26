-- core/lfs.lua -- filesystem helper with native fast path.
--
-- If the native lfs module is available (via core/native.lua), every
-- function here returns a result without forking a shell. If not,
-- the function returns nil and the caller falls back to the existing
-- shell-based implementation in services/fs.lua.

local Native = require("core.native")
local lfs    = Native.lfs

local M = { available = (lfs ~= nil) }

local function norm(path)
  if not path or path == "" then return nil end
  -- lfs refuses a trailing slash on directories on some builds
  path = path:gsub("/+$", "")
  if path == "" then path = "/" end
  return path
end

-- Return a table of entries. Each entry mirrors services/fs.lua's
-- parse_stat_line() output shape exactly.
function M.list(path)
  if not lfs then return nil end
  path = norm(path)
  if not path then return nil end
  local out = {}
  local ok, iter, dir_obj = pcall(lfs.dir, path)
  if not ok then return nil end
  for name in iter, dir_obj do
    if name ~= "." and name ~= ".." then
      local full = (path == "/") and ("/" .. name) or (path .. "/" .. name)
      local attr = lfs.attributes(full)
      if attr then
        local is_dir  = (attr.mode == "directory")
        local is_link = (attr.mode == "link")
        out[#out + 1] = {
          name    = name,
          path    = full,
          is_dir  = is_dir,
          is_link = is_link,
          size    = attr.size or 0,
          mtime   = attr.modification or 0,
          perms   = attr.permissions or "",
          ftype   = attr.mode or "?",
        }
      end
    end
  end
  return out
end

function M.stat(path)
  if not lfs then return nil end
  path = norm(path)
  if not path then return nil end
  local attr = lfs.attributes(path)
  if not attr then return nil end
  local name = path:match("([^/]+)$") or path
  return {
    name    = name,
    path    = path,
    is_dir  = (attr.mode == "directory"),
    is_link = (attr.mode == "link"),
    size    = attr.size or 0,
    mtime   = attr.modification or 0,
    perms   = attr.permissions or "",
    ftype   = attr.mode or "?",
  }
end

function M.is_dir(path)
  if not lfs then return nil end
  path = norm(path)
  if not path then return nil end
  local mode = lfs.attributes(path, "mode")
  return mode == "directory"
end

function M.exists(path)
  if not lfs then return nil end
  path = norm(path)
  if not path then return nil end
  local mode = lfs.attributes(path, "mode")
  return mode ~= nil
end

function M.mkdir(path)
  if not lfs then return nil end
  path = norm(path)
  if not path then return nil end
  return lfs.mkdir(path) == true
end

function M.rmdir(path)
  if not lfs then return nil end
  path = norm(path)
  if not path then return nil end
  return lfs.rmdir(path) == true
end

function M.touch(path)
  if not lfs then return nil end
  path = norm(path)
  if not path then return nil end
  if lfs.touch then
    return lfs.touch(path) == true
  end
  local f = io.open(path, "w")
  if f then f:close(); return true end
  return false
end

return M
