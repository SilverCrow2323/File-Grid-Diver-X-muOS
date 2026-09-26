-- services/trash.lua -- per-volume soft delete with restore.
--
-- Each mount point gets its own .fgd_trash directory:
--   /mnt/mmc/file.iso       -> /mnt/mmc/.fgd_trash/
--   /mnt/sdcard/file.iso    -> /mnt/sdcard/.fgd_trash/
--   <app>/data/trash/file   -> data/trash/  (fallback, on the app's volume)
--
-- Moves within the same volume are instant renames. No cross-device
-- copy, no doubling of storage requirements, no 4 GB ISO crawling
-- through the app's CWD to reach a different filesystem.
--
-- The public API is unchanged: move / list / restore / purge_all /
-- purge_index / size / restore_by_stored.

local sh = require("core.sh")
local M  = {}

local FALLBACK_TRASH = "data/trash"

-- ----------------------------------------------------------------
--  Mount detection
-- ----------------------------------------------------------------
-- Return the longest mount prefix of `path`, or nil if none.
-- /proc/mounts escapes spaces and control chars; we decode the
-- common ones (\040 space, \011 tab, \012 newline).
local function mount_of(path)
  if not path or path == "" then return nil end
  local best, best_len = nil, 0
  local f = io.open("/proc/mounts", "r")
  if not f then return nil end
  for line in f:lines() do
    local mnt = line:match("^%S+%s+(%S+)")
    if mnt then
      mnt = mnt:gsub("\\040", " "):gsub("\\011", "\t"):gsub("\\012", "\n")
      local len = #mnt
      if len > best_len
         and path:sub(1, len) == mnt
         and (len == 1 or path:sub(len + 1, len + 1) == "/") then
        best = mnt
        best_len = len
      end
    end
  end
  f:close()
  return best
end

-- The trash directory that should hold the deletion of `path`.
local function trash_dir_for(path)
  local mnt = mount_of(path)
  if not mnt or mnt == "/" then
    return FALLBACK_TRASH
  end
  return mnt .. "/.fgd_trash"
end

-- Every trash directory the system might currently have.
-- Always includes the fallback so old entries stay visible.
local function all_trash_dirs()
  local out = { FALLBACK_TRASH }
  local seen = { [FALLBACK_TRASH] = true }
  local f = io.open("/proc/mounts", "r")
  if f then
    for line in f:lines() do
      local mnt = line:match("^%S+%s+(%S+)")
      if mnt then
        mnt = mnt:gsub("\\040", " "):gsub("\\011", "\t"):gsub("\\012", "\n")
        if mnt ~= "/" then
          local dir = mnt .. "/.fgd_trash"
          if not seen[dir] then
            seen[dir] = true
            out[#out + 1] = dir
          end
        end
      end
    end
    f:close()
  end
  return out
end

-- ----------------------------------------------------------------
--  Index I/O (per directory)
-- ----------------------------------------------------------------
local function read_index(path)
  local out = {}
  local f = io.open(path, "r")
  if f then
    for line in f:lines() do
      local ts, orig, stored = line:match("^(%d+)\t(.-)\t(.+)$")
      if ts then
        out[#out + 1] = { t = tonumber(ts), orig = orig, stored = stored }
      end
    end
    f:close()
  end
  return out
end

local function write_index(path, entries)
  local dir = path:match("^(.*)/[^/]+$") or "."
  os.execute("mkdir -p " .. sh.shq(dir))
  local f = io.open(path, "w")
  if not f then return end
  for _, e in ipairs(entries) do
    f:write(string.format("%d\t%s\t%s\n", e.t, e.orig, e.stored))
  end
  f:close()
end

-- ----------------------------------------------------------------
--  Public API
-- ----------------------------------------------------------------
local function basename(p) return (p or ""):match("([^/]+)$") or p or "item" end

function M.move(path)
  if not path or path == "" then return false, "no path" end

  local dir = trash_dir_for(path)
  os.execute("mkdir -p " .. sh.shq(dir))

  local ts   = os.time()
  local name = basename(path)
  local stored = dir .. "/" .. ts .. "_" .. name

  -- Avoid collision within the same second
  local k = 0
  while sh.exists(stored) do
    k = k + 1
    stored = dir .. "/" .. ts .. "_" .. k .. "_" .. name
  end

  -- Same-volume move is a rename: fast, atomic, no copy.
  local rc = sh.exec("mv " .. sh.shq(path) .. " " .. sh.shq(stored))
  if rc ~= 0 then
    -- Fallback for the rare cross-device case (e.g. bind mounts).
    if sh.exec("cp -a " .. sh.shq(path) .. " " .. sh.shq(stored)) == 0 then
      sh.exec("rm -rf " .. sh.shq(path))
    else
      return false, "move failed"
    end
  end

  local idx = dir .. "/index.txt"
  local entries = read_index(idx)
  entries[#entries + 1] = { t = ts, orig = path, stored = stored }
  write_index(idx, entries)
  return true, stored
end

-- Merged view of every volume's index.
function M.list()
  local merged = {}
  for _, dir in ipairs(all_trash_dirs()) do
    local idx = dir .. "/index.txt"
    for _, e in ipairs(read_index(idx)) do
      e._idx = idx       -- remember where it came from
      merged[#merged + 1] = e
    end
  end
  return merged
end

function M.restore(i)
  local list = M.list()
  local e = list[i]
  if not e then return false, "not found" end
  if not sh.exists(e.stored) then return false, "already gone" end

  local target = e.orig
  if sh.exists(target) then
    local base, ext = target:match("^(.*)(%.[^%.]+)$")
    if not base then base, ext = target, "" end
    local k = 1
    repeat target = base .. "_restored_" .. k .. ext; k = k + 1
    until not sh.exists(target) or k > 999
  end

  local rc = sh.exec("mv " .. sh.shq(e.stored) .. " " .. sh.shq(target))
  if rc == 0 then
    local entries = read_index(e._idx)
    for j, x in ipairs(entries) do
      if x.stored == e.stored then
        table.remove(entries, j)
        break
      end
    end
    write_index(e._idx, entries)
    return true, target
  end
  return false, "restore failed"
end

function M.restore_by_stored(stored)
  if not stored then return false, "no path" end
  local list = M.list()
  for i, e in ipairs(list) do
    if e.stored == stored then
      return M.restore(i)
    end
  end
  return false, "not in index"
end

function M.purge_all()
  for _, dir in ipairs(all_trash_dirs()) do
    if sh.exists(dir) then
      -- Wipe contents thoroughly, including hidden files.
      os.execute("find " .. sh.shq(dir) ..
        " -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null")
      os.execute(": > " .. sh.shq(dir .. "/index.txt"))
    end
  end
  return true
end

function M.purge_index(i)
  local list = M.list()
  local e = list[i]
  if not e then return false end
  sh.exec("rm -rf " .. sh.shq(e.stored))
  local entries = read_index(e._idx)
  for j, x in ipairs(entries) do
    if x.stored == e.stored then
      table.remove(entries, j)
      break
    end
  end
  write_index(e._idx, entries)
  return true
end

-- Total footprint across all volumes.
function M.size()
  local total = 0
  for _, dir in ipairs(all_trash_dirs()) do
    if sh.exists(dir) then
      local h = io.popen("du -sk " .. sh.shq(dir) .. " 2>/dev/null")
      if h then
        local out = h:read("*a") or ""
        h:close()
        local kb = tonumber(out:match("^(%d+)")) or 0
        total = total + kb * 1024
      end
    end
  end
  return total
end

-- Expose for diagnostics.
function M.volumes()
  local out = {}
  for _, dir in ipairs(all_trash_dirs()) do
    out[#out + 1] = {
      dir      = dir,
      exists   = sh.exists(dir),
      entries  = #read_index(dir .. "/index.txt"),
    }
  end
  return out
end

return M
