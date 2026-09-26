-- screens/disk_tools.lua — fsck / badblocks / mount options / safe mode.
--
-- The most common source of data loss on a handheld is a FAT32 SD
-- card that got power-killed during a write. This screen exposes the
-- tools needed to detect and repair that, without leaving the device.
local A     = require("core.assets")
local State = require("core.state")
local Input = require("core.input_map")
local Frame = require("ui.frame")
local D     = require("ui.draw")
local Modal = require("ui.modal")
local Notify= require("ui.notify")
local sh    = require("core.sh")

local S = {}
local W, H = 640, 480

local volumes = {}   -- { dev, mnt, fs, opts, total, used, free }
local sel     = 1
local tab     = "volumes"   -- volumes | scan | log
local scan_lines = {}
local scan_job   = nil
local scan_name  = ""

-- ── Helpers ─────────────────────────────────────────────────
local SKIP_FS = {
  proc=true, sysfs=true, tmpfs=true, devpts=true, cgroup=true,
  cgroup2=true, pstore=true, securityfs=true, debugfs=true,
  tracefs=true, configfs=true, fusectl=true, mqueue=true,
  hugetlbfs=true, binfmt_misc=true, rpc_pipefs=true, efivarfs=true,
  autofs=true, bpf=true, ramfs=true, devtmpfs=true,
}

local function human(n)
  if not n or n <= 0 then return "0 B" end
  local u = { "B","KB","MB","GB","TB" }
  local i = 1
  while n >= 1024 and i < #u do n = n/1024; i = i+1 end
  if i == 1 then return string.format("%d %s", n, u[i]) end
  return string.format("%.1f %s", n, u[i])
end

local function reload()
  volumes = {}
  local dfmap = {}
  local out = sh.read("df -kP 2>/dev/null") or ""
  for line in out:gmatch("[^\n]+") do
    local dev,total,used,avail,pct,mnt =
      line:match("^(%S+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%%%s+(.+)$")
    if dev and mnt then
      dfmap[mnt] = {
        total = tonumber(total)*1024,
        used  = tonumber(used)*1024,
        free  = tonumber(avail)*1024,
      }
    end
  end
  local f = io.open("/proc/mounts","r")
  if f then
    for line in f:lines() do
      local dev, mnt, fs, opts = line:match("^(%S+)%s+(%S+)%s+(%S+)%s+(%S+)")
      if dev and mnt and fs and not SKIP_FS[fs] then
        if dev:sub(1,5) == "/dev/" then
          local d = dfmap[mnt] or {}
          volumes[#volumes+1] = {
            dev=dev, mnt=mnt, fs=fs, opts=opts,
            total=d.total, used=d.used, free=d.free,
          }
        end
      end
    end
    f:close()
  end
  if sel > #volumes then sel = math.max(1,#volumes) end
  if sel < 1 then sel = 1 end
end

local function append_log(line)
  scan_lines[#scan_lines+1] = line
  if #scan_lines > 200 then table.remove(scan_lines,1) end
end

local function run_scan(name, cmd, ttl)
  scan_name = name
  scan_lines = { "> " .. name, "> " .. cmd, "" }
  tab = "log"
  local id = tostring(os.time()) .. "_" .. tostring(math.random(1000,9999))
  local script = "/tmp/fgd_scan_" .. id .. ".sh"
  local out    = "/tmp/fgd_scan_" .. id .. ".out"
  local done   = "/tmp/fgd_scan_" .. id .. ".done"
  local body = table.concat({
    "set +e",
    "OUT=" .. sh.shq(out),
    "DONE=" .. sh.shq(done),
    ': > "$OUT"',
    cmd,
    'touch "$DONE"',
  }, "\n")
  local f = io.open(script,"w")
  if not f then Notify.show("error","cannot write job"); return end
  f:write("#!/bin/sh\n" .. body .. "\n"); f:close()
  os.execute("chmod +x " .. sh.shq(script))
  os.execute("setsid sh " .. sh.shq(script) .. " </dev/null >/dev/null 2>&1 &")
  scan_job = { script=script, out=out, done=done, t=0, ttl=ttl or 60 }
end

local function poll_scan(dt)
  if not scan_job then return end
  scan_job.t = scan_job.t + dt
  if scan_job.t > scan_job.ttl then
    os.execute("pkill -f " .. sh.shq(scan_job.script))
    append_log("(timeout)")
    scan_job = nil
    return
  end
  local f = io.open(scan_job.out,"r")
  if f then
    for line in f:lines() do
      if #scan_lines == 0 or scan_lines[#scan_lines] ~= line then
        append_log(line)
      end
    end
    f:close()
  end
  local d = io.open(scan_job.done,"r")
  if d then
    d:close()
    append_log("")
    append_log("== done ==")
    os.remove(scan_job.script)
    os.remove(scan_job.out)
    os.remove(scan_job.done)
    scan_job = nil
    Notify.show("success", "scan complete")
  end
end

-- ── Lifecycle ───────────────────────────────────────────────
function S.enter() reload(); sel = 1 end
function S.leave()
  if scan_job then
    os.execute("pkill -f " .. sh.shq(scan_job.script))
    scan_job = nil
  end
end
function S.update(dt) poll_scan(dt) end

local function move(n)
  if tab == "volumes" then
    sel = math.max(1, math.min(#volumes, sel + n))
  else
    -- scroll log
    scan_lines.scroll = math.max(1, math.min(#scan_lines,
      (scan_lines.scroll or #scan_lines) + n))
  end
end

-- ── Actions ─────────────────────────────────────────────────
local function do_fsck(v)
  Modal.show("fsck.vfat (read-only)",
    "Check " .. v.dev .. " read-only?\n" ..
    "Requires the volume to be unmounted first.\n" ..
    "If mounted, we will first remount read-only.",
    {
      accept_label = "CHECK",
      on_accept = function()
        run_scan("fsck " .. v.dev,
          "fsck.vfat -n " .. sh.shq(v.dev) .. " 2>&1 || true", 30)
      end,
    })
end

local function do_badblocks(v)
  Modal.show("badblocks (read-only)",
    "Scan " .. v.dev .. " for bad sectors?\n" ..
    "Read-only pass. Can take 10+ minutes for large cards.",
    {
      accept_label = "SCAN",
      on_accept = function()
        run_scan("badblocks " .. v.dev,
          "badblocks -sv " .. sh.shq(v.dev) .. " 2>&1 || true", 1800)
      end,
    })
end

local function remount_ro(v)
  Modal.show("Remount read-only",
    "Remount " .. v.mnt .. " read-only?\n" ..
    "This puts the volume in safe mode for inspection.",
    {
      accept_label = "REMOUNT",
      on_accept = function()
        local rc = os.execute("mount -o remount,ro " .. sh.shq(v.mnt) ..
          " 2>/dev/null")
        Notify.show("info", "mount remount rc=" .. tostring(rc))
        reload()
      end,
    })
end

local function remount_rw(v)
  local rc = os.execute("mount -o remount,rw " .. sh.shq(v.mnt) .. " 2>/dev/null")
  Notify.show("info", "remount rw rc=" .. tostring(rc))
  reload()
end

local function free_space_all()
  run_scan("df -h", "df -h 2>&1", 10)
end

local function view_mount_opts(v)
  Modal.show("Mount options",
    v.dev .. " on " .. v.mnt .. "\n" ..
    "fs: " .. v.fs .. "\n" ..
    "opts: " .. v.opts .. "\n" ..
    "free: " .. human(v.free or 0) .. " / " .. human(v.total or 0),
    { cancel_label = "CLOSE", accept_label = "CLOSE" })
end

-- ── Input ───────────────────────────────────────────────────
function S.pad(b)
  if Modal.is_open() then
    if b == Input.A or b == Input.B then Modal.cancel() end
    return
  end
  if     b == Input.B or b == Input.SELECT then State.back()
  elseif b == Input.UP    then move(-1)
  elseif b == Input.DOWN  then move( 1)
  elseif b == Input.L1    then move(-10)
  elseif b == Input.R1    then move( 10)
  elseif b == Input.X     then
    tab = (tab == "volumes") and "log" or "volumes"
    if tab == "volumes" then reload() end
  elseif b == Input.Y     then free_space_all()
  elseif b == Input.START then reload()
  elseif b == Input.A and tab == "volumes" then
    local v = volumes[sel]
    if v then
      Modal.show("Volume actions",
        v.dev .. " on " .. v.mnt .. "\n" ..
        "A: fsck   X: badblocks   Y: remount ro   L1: rw",
        {
          accept_label = "FSCK",
          cancel_label = "CLOSE",
          on_accept = function() do_fsck(v) end,
        })
    end
  end
end

function S.hat(dir)
  if     dir == "up"   then move(-1)
  elseif dir == "down" then move( 1) end
end

function S.key(k)
  if Modal.is_open() then
    if k == "return" or k == "escape" then Modal.cancel() end
    return
  end
  if k == "escape" or k == "backspace" then State.back()
  elseif k == "up"   then move(-1)
  elseif k == "down" then move( 1)
  elseif k == "tab"  then
    tab = (tab == "volumes") and "log" or "volumes"
  end
end

-- ── Draw ────────────────────────────────────────────────────
local function bar(x, y, w, h, frac, col)
  love.graphics.setColor(0.10, 0.08, 0.06, 1)
  love.graphics.rectangle("fill", x, y, w, h)
  love.graphics.setColor(col[1], col[2], col[3], 1)
  love.graphics.rectangle("fill", x, y, w * frac, h)
  love.graphics.setColor(col[1], col[2], col[3], 0.4)
  love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1)
end

function S.draw()
  local th = State.theme
  D.bg()

  -- Tabs
  local f = A.font(A.FONT_BODY_BOLD, 13)
  love.graphics.setFont(f)
  local function tab_at(x, label, active)
    local w = f:getWidth(label) + 16
    love.graphics.setColor(active and th.amber_hi or th.text_dim)
    love.graphics.rectangle("line", x, Frame.TOP_H + 4, w, 16)
    love.graphics.print(label, x + 8, Frame.TOP_H + 7)
    return x + w + 4
  end
  local tx = 10
  tx = tab_at(tx, "VOLUMES", tab == "volumes")
  tx = tab_at(tx, "SCAN LOG", tab == "log")

  love.graphics.setColor(th.text_dim)
  love.graphics.setFont(A.font(A.FONT_MONO, 12))
  love.graphics.printf("X: switch   Y: df -h   START: rescan",
    0, Frame.TOP_H + 7, W - 12, "right")

  if tab == "volumes" then
    local y0 = Frame.TOP_H + 30
    local row_h = 62
    local vis = math.floor((H - y0 - Frame.BOTTOM_H - 6) / row_h)
    local first = math.max(1, sel - math.floor(vis / 2))
    local last  = math.min(#volumes, first + vis - 1)

    if #volumes == 0 then
      love.graphics.setColor(th.text_dim)
      love.graphics.setFont(A.font(A.FONT_BODY, 14))
      love.graphics.printf("no physical volumes found",
        0, H/2, W, "center")
    end

    for i = first, last do
      local v = volumes[i]
      local ry = y0 + (i - first) * row_h
      local focused = (i == sel)

      love.graphics.setColor(focused and 0.06 or 0.025,
                             focused and 0.05 or 0.02,
                             focused and 0.035 or 0.018, 1)
      love.graphics.rectangle("fill", 10, ry, W - 20, row_h - 4, 2, 2)
      if focused then
        love.graphics.setColor(th.amber_hi)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", 10.5, ry + 0.5, W - 21, row_h - 5, 2, 2)
        love.graphics.setLineWidth(1)
      end

      love.graphics.setColor(th.text_bright)
      love.graphics.setFont(A.font(A.FONT_BODY_BOLD, 14))
      love.graphics.print(v.dev, 20, ry + 4)
      love.graphics.setColor(th.amber_hi)
      love.graphics.setFont(A.font(A.FONT_MONO, 12))
      love.graphics.printf(v.fs .. "  on  " .. v.mnt, 0, ry + 4, W - 20, "right")

      -- Space bar
      if v.total and v.total > 0 then
        local frac = v.used / v.total
        local col = frac > 0.9 and th.red_hi or (frac > 0.75 and th.amber_hi or th.green)
        bar(20, ry + 24, W - 200, 8, frac, col)
        love.graphics.setFont(A.font(A.FONT_MONO, 12))
        love.graphics.setColor(th.text)
        love.graphics.printf(human(v.free) .. " free / " .. human(v.total),
          0, ry + 22, W - 20, "right")
      end

      love.graphics.setFont(A.font(A.FONT_BODY, 11))
      love.graphics.setColor(th.text_dim)
      love.graphics.print(v.opts:sub(1,90), 20, ry + 40)
    end
  else
    -- scan log
    local row_h = 12
    local y0 = Frame.TOP_H + 30
    local vis = math.floor((H - y0 - Frame.BOTTOM_H - 4) / row_h)
    local first = math.max(1, #scan_lines - vis + 1)
    local last  = #scan_lines

    if #scan_lines == 0 then
      love.graphics.setColor(th.text_dim)
      love.graphics.setFont(A.font(A.FONT_BODY, 14))
      love.graphics.printf("press A on a volume to run fsck / badblocks",
        0, H/2, W, "center")
    end

    love.graphics.setFont(A.font(A.FONT_MONO, 12))
    for i = first, last do
      local y = y0 + (i - first) * row_h
      local line = scan_lines[i] or ""
      if line:find("error", 1, true) or line:find("Error", 1, true)
         or line:find("bad", 1, true) then
        love.graphics.setColor(th.red_hi)
      elseif line:sub(1,2) == "> " then
        love.graphics.setColor(th.amber_hi)
      elseif line:find("done") then
        love.graphics.setColor(th.green)
      else
        love.graphics.setColor(th.text)
      end
      love.graphics.print(line, 12, y)
    end

    if scan_job then
      love.graphics.setColor(th.amber_hi)
      love.graphics.setFont(A.font(A.FONT_BODY_BOLD, 12))
      love.graphics.printf("RUNNING: " .. scan_name, 0,
        H - Frame.BOTTOM_H - 16, W - 12, "right")
    end
  end

  Frame.draw_top("FGD", "disk_tools")
  Frame.draw_bottom({
    { key = "UP/DN",  label = "Select" },
    { key = "A",      label = "Actions" },
    { key = "Y",      label = "df -h" },
    { key = "X",      label = "Tab" },
    { key = "ST",     label = "Rescan" },
    { key = "B",      label = "Back" },
  })
  Modal.draw()
  D.scanlines(W, H, 0.06)
end

return S
