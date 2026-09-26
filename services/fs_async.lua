-- services/fs_async.lua — async filesystem operations.
--
-- Pattern: write a shell script to /tmp, launch it detached, poll
-- for a .done marker. Result parsed from a .out file. No threads,
-- no coroutines, no blocking the main loop.

local sh = require("core.sh")
local M  = {}

local TMP = "/tmp"
local JOBS = {}

-- ── Helpers ─────────────────────────────────────────────────
local function tmpname(job_id, suffix)
  return TMP .. "/fgd_" .. job_id .. suffix
end

local function write_script(path, body)
  local f = io.open(path, "w")
  if not f then return false end
  f:write("#!/bin/sh\n")
  f:write(body)
  f:write("\n")
  f:close()
  os.execute("chmod +x " .. sh.shq(path))
  return true
end

local function spawn_script(path)
  return sh.exec("setsid sh " .. sh.shq(path) ..
    " </dev/null >/dev/null 2>&1 &") == 0
end

local function remove_if_exists(p)
  os.remove(p)
end

-- ── Scan (single global slot, always replaces previous) ─────
local scan_job = nil

function M.scan(path)
  if not path or path == "" then return false end

  -- Cancel any previous scan
  if scan_job then
    M.cancel(scan_job.id)
    scan_job = nil
  end

  local id = "scan_" .. tostring(os.time()) .. "_" ..
             tostring(math.random(1000, 9999))
  local script = tmpname(id, ".sh")
  local out    = tmpname(id, ".out")
  local done   = tmpname(id, ".done")

  remove_if_exists(out)
  remove_if_exists(done)

  local body = table.concat({
    "set +e",
    "OUT=" .. sh.shq(out),
    "DONE=" .. sh.shq(done),
    ': > "$OUT"',
    'find ' .. sh.shq(path) ..
      ' -mindepth 1 -maxdepth 1 -exec stat -c "%n|%F|%s|%Y|%A" {} + ' ..
      '2>/dev/null > "$OUT"',
    'touch "$DONE"',
  }, "\n")

  if not write_script(script, body) then return false end
  if not spawn_script(script) then return false end

  scan_job = {
    id     = id,
    path   = path,
    script = script,
    out    = out,
    done   = done,
    t      = 0,
  }
  return true
end

-- Poll the scan job. Returns:
--   false, nil       → still running
--   true, entries    → done with results
--   true, nil        → done with error (no output file)
function M.poll_scan(dt)
  if not scan_job then return false, nil end
  scan_job.t = scan_job.t + (dt or 0)

  -- Timeout after 30 s
  if scan_job.t > 30 then
    M.cancel(scan_job.id)
    scan_job = nil
    return true, nil
  end

  local df = io.open(scan_job.done, "r")
  if not df then return false, nil end
  df:close()

  local entries = {}
  local of = io.open(scan_job.out, "r")
  if of then
    local FS = require("services.fs")
    for line in of:lines() do
      local path, ftype, size, mtime, perms =
        line:match("^(.-)|(.-)|(%d+)|(%d+)|(.+)$")
      if path then
        local name = path:match("([^/]+)$") or path
        entries[#entries + 1] = {
          path    = path,
          name    = name,
          is_dir  = ftype:find("directory") ~= nil,
          is_link = ftype:find("symbolic link") ~= nil,
          size    = tonumber(size) or 0,
          mtime   = tonumber(mtime) or 0,
          perms   = perms,
          ftype   = ftype,
        }
      end
    end
    of:close()
  end

  -- Cleanup
  os.remove(scan_job.script)
  os.remove(scan_job.out)
  os.remove(scan_job.done)
  scan_job = nil

  return true, entries
end

function M.is_scanning()
  return scan_job ~= nil
end

function M.cancel(id)
  if not id then return end
  local script = tmpname(id, ".sh")
  local out    = tmpname(id, ".out")
  local done   = tmpname(id, ".done")
  os.execute("pkill -f " .. sh.shq(script) .. " 2>/dev/null")
  os.remove(script)
  os.remove(out)
  os.remove(done)
end

function M.cancel_scan()
  if scan_job then
    M.cancel(scan_job.id)
    scan_job = nil
  end
end

-- ── Copy / move / delete (fire-and-forget with progress) ────
-- Returns a job table that the caller stores and polls.
-- Currently simplified: operations complete silently; progress
-- tracking will be added in a later revision.

local function fire_and_forget(id, body)
  local script = tmpname(id, ".sh")
  if not write_script(script, body) then return nil end
  if not spawn_script(script) then return nil end
  return { id = id, script = script, t = 0, done = false }
end

function M.cp_many(paths, dst)
  local id = "cp_" .. tostring(os.time())
  local parts = { "set +e" }
  for _, p in ipairs(paths) do
    parts[#parts + 1] = "cp -a " .. sh.shq(p) .. " " .. sh.shq(dst) .. "/"
  end
  parts[#parts + 1] = "rm -f " .. sh.shq(tmpname(id, ".sh"))
  return fire_and_forget(id, table.concat(parts, "\n"))
end

function M.mv_many(paths, dst)
  local id = "mv_" .. tostring(os.time())
  local parts = { "set +e" }
  for _, p in ipairs(paths) do
    parts[#parts + 1] = "mv " .. sh.shq(p) .. " " .. sh.shq(dst) .. "/"
  end
  parts[#parts + 1] = "rm -f " .. sh.shq(tmpname(id, ".sh"))
  return fire_and_forget(id, table.concat(parts, "\n"))
end

function M.rm_many(paths)
  local id = "rm_" .. tostring(os.time())
  local parts = { "set +e" }
  for _, p in ipairs(paths) do
    parts[#parts + 1] = "rm -rf " .. sh.shq(p)
  end
  parts[#parts + 1] = "rm -f " .. sh.shq(tmpname(id, ".sh"))
  return fire_and_forget(id, table.concat(parts, "\n"))
end

return M
