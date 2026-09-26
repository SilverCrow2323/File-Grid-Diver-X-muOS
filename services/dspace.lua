-- services/dspace.lua -- disk space, mounts, NTP time sync.
local sh = require("core.sh")
local M  = {}

local function human(n)
  if not n or n <= 0 then return "0 B" end
  local u = { "B", "KB", "MB", "GB", "TB" }
  local i = 1
  while n >= 1024 and i < #u do n = n / 1024; i = i + 1 end
  if i == 1 then return string.format("%d %s", n, u[i]) end
  return string.format("%.1f %s", n, u[i])
end
M.human = human

-- Returns total, used, free, percent (0..1), or nil.
local function df_one(path)
  local out = sh.read("df -kP " .. sh.shq(path) .. " 2>/dev/null")
  if not out then return nil end
  local line = out:match("[^\n]+\n([^\n]+)")
  if not line then return nil end
  local total, used, free, pct = line:match("%s(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%%")
  if not total then return nil end
  total, used, free, pct = tonumber(total), tonumber(used), tonumber(free), tonumber(pct)
  return total * 1024, used * 1024, free * 1024, (pct or 0) / 100
end
M.df = df_one

-- Returns all real mounts as a list of tables.
function M.mounts()
  local out = {}
  local SKIP = {
    proc=1, sysfs=1, tmpfs=1, devpts=1, cgroup=1, cgroup2=1,
    pstore=1, securityfs=1, debugfs=1, tracefs=1, configfs=1,
    fusectl=1, mqueue=1, hugetlbfs=1, binfmt_misc=1, rpc_pipefs=1,
    efivarfs=1, autofs=1, bpf=1, ramfs=1, devtmpfs=1,
  }
  local f = io.open("/proc/mounts", "r")
  if not f then return out end
  for line in f:lines() do
    local dev, mnt, fs, opts = line:match("^(%S+)%s+(%S+)%s+(%S+)%s+(%S+)")
    if dev and mnt and fs and not SKIP[fs] and dev:sub(1, 5) == "/dev/" then
      local t, u, fr, p = df_one(mnt)
      out[#out + 1] = {
        dev = dev, mnt = mnt, fs = fs, opts = opts,
        total = t, used = u, free = fr, pct = p,
      }
    end
  end
  f:close()
  return out
end

-- NTP sync via ntpdate / sntp / busybox ntpd -q
function M.ntp_sync(server)
  server = server or "pool.ntp.org"
  for _, cmd in ipairs({
    "ntpdate -u " .. sh.shq(server) .. " 2>&1",
    "sntp -S " .. sh.shq(server) .. " 2>&1",
    "busybox ntpd -q -n -p " .. sh.shq(server) .. " 2>&1",
  }) do
    local tool = cmd:match("^(%S+)")
    local h = io.popen("command -v " .. tool .. " 2>/dev/null")
    local found = false
    if h then local o = h:read("*a") or ""; h:close(); found = (o ~= "") end
    if found then
      local out = sh.read(cmd)
      if out and not out:lower():match("error") then
        return true, out
      end
    end
  end
  return false, "no NTP tool available"
end

function M.set_time(str)
  -- str: "YYYY-MM-DD HH:MM:SS"
  return sh.exec("date -s " .. sh.shq(str) .. " >/dev/null 2>&1") == 0
end

return M
