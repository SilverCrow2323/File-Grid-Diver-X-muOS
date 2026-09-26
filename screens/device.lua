-- screens/device.lua -- System Cockpit v2 (definitive).
-- Layout: left rail (7 sections) + right panel. Cyberpunk terminal style.
-- Sections: COCKPIT, DEVICE, STORAGE (+ disk tools), NETWORK, THERMAL,
--           PROCESSES, ACTIONS.
local A     = require("core.assets")
local State = require("core.state")
local Input = require("core.input_map")
local Frame = require("ui.frame")
local D     = require("ui.draw")
local Notify= require("ui.notify")
local Modal = require("ui.modal")
local sh    = require("core.sh")

local S = {}
local W, H = 640, 480
local RAIL_W = 132
local PAD    = 8
local ROW_H  = 22

-- ============================================================
--  Palette
-- ============================================================
local AMB    = {0.94, 0.66, 0.35}
local AMB_HI = {1.00, 0.78, 0.45}
local CYA    = {0.48, 0.80, 0.90}
local CYA_HI = {0.62, 0.92, 1.00}
local GRN    = {0.55, 0.85, 0.45}
local BLU    = {0.55, 0.75, 0.95}
local ORG    = {0.95, 0.55, 0.30}
local PUR    = {0.70, 0.55, 0.92}
local YEL    = {0.95, 0.80, 0.30}
local RED    = {0.95, 0.30, 0.25}
local GRY    = {0.45, 0.45, 0.50}

local function col(c, a) love.graphics.setColor(c[1], c[2], c[3], a or 1) end

local function human(n)
  if not n or n <= 0 then return "0 B" end
  local u = {"B","KB","MB","GB","TB"}; local i = 1
  while n >= 1024 and i < #u do n = n / 1024; i = i + 1 end
  if i == 1 then return string.format("%d %s", n, u[i]) end
  return string.format("%.1f %s", n, u[i])
end

local function read_line(p)
  local f = io.open(p, "r"); if not f then return nil end
  local v = f:read("*l"); f:close(); return v
end

local function trunc(font, s, maxw)
  if not s then return "" end
  if font:getWidth(s) <= maxw then return s end
  local out = s
  while #out > 1 and font:getWidth(out .. ".") > maxw do out = out:sub(1,-2) end
  return out .. "."
end

-- ============================================================
--  Sections definition
-- ============================================================
local SECTIONS = {
  { id="cockpit",   label="COCKPIT",   tag="01", accent=AMB,  icon="gauge"  },
  { id="device",    label="DEVICE",    tag="02", accent=CYA,  icon="chip"   },
  { id="storage",   label="STORAGE",   tag="03", accent=GRN,  icon="disk"   },
  { id="network",   label="NETWORK",   tag="04", accent=BLU,  icon="wifi"   },
  { id="thermal",   label="THERMAL",   tag="05", accent=ORG,  icon="temp"   },
  { id="processes", label="PROCESSES", tag="06", accent=PUR,  icon="proc"   },
  { id="actions",   label="ACTIONS",   tag="07", accent=YEL,  icon="bolt"   },
}
local NSEC = #SECTIONS

local cur_sec = 1
local t_enter = 0
local sel_map = {}   -- per-section selection index
local scroll_map = {}

-- ============================================================
--  Live data
-- ============================================================
local hist = { cpu = {}, ram = {}, temp = {}, dl = {}, ul = {} }
local MAX_HIST = 60
local last_net = { rx = 0, tx = 0, t = 0 }
local last_cores = nil
local sample_t = 0
local SAMPLE = 0.4

local data = {
  model = "?", kern = "?", host = "?", uptime = "?",
  mounts = {}, net = {}, procs = {}, sensors = {}, volumes = {},
  core_usage = {}, last_dl = 0, last_ul = 0,
  battery = nil, mem_pct = 0, mem_total = 0, mem_used = 0,
  temp = 0, bench = nil, log_lines = {},
}

local function read_cpu_cores()
  local cores = {}
  local f = io.open("/proc/stat", "r"); if not f then return cores end
  for line in f:lines() do
    local n, vals = line:match("^cpu(%d+)%s+(.+)$")
    if n then
      local nums = {}
      for v in vals:gmatch("%d+") do nums[#nums+1] = tonumber(v) end
      if #nums >= 4 then
        local u, ni, s, i = nums[1], nums[2], nums[3], nums[4]
        local io_ = nums[5] or 0
        local iq  = nums[6] or 0
        local sq  = nums[7] or 0
        cores[#cores+1] = {
          id = tonumber(n),
          active = u + ni + s + iq + sq,
          total  = u + ni + s + i + io_ + iq + sq,
        }
      end
    else break end
  end
  f:close()
  return cores
end

local function compute_cores(cores)
  if not last_cores then last_cores = cores; return {} end
  local out = {}
  for i, c in ipairs(cores) do
    local lc = last_cores[i]
    if lc and lc.id == c.id then
      local da = c.active - lc.active
      local dt = c.total - lc.total
      out[#out+1] = (dt > 0) and (da / dt * 100) or 0
    else out[#out+1] = 0 end
  end
  last_cores = cores
  return out
end

local function read_mem()
  local f = io.open("/proc/meminfo", "r"); if not f then return 0,0,0 end
  local tot, avail = 0, 0
  for line in f:lines() do
    local k, v = line:match("^(%w+):%s+(%d+)")
    if k == "MemTotal" then tot = tonumber(v) or 0
    elseif k == "MemAvailable" then avail = tonumber(v) or 0 end
  end
  f:close()
  if tot == 0 then return 0, 0, 0 end
  return (tot - avail) / tot * 100, tot * 1024, (tot - avail) * 1024
end

local function read_temp()
  for i = 0, 4 do
    local v = tonumber(read_line("/sys/class/thermal/thermal_zone" .. i .. "/temp"))
    if v then
      if v > 1000 then v = v / 1000 end
      return v
    end
  end
  return 0
end

local function read_battery()
  for _, p in ipairs({
    "/sys/class/power_supply/battery/capacity",
    "/sys/class/power_supply/BAT0/capacity",
    "/sys/class/power_supply/BAT1/capacity",
  }) do
    local v = tonumber(read_line(p)); if v then return v end
  end
  return nil
end

local function read_net()
  local f = io.open("/proc/net/dev", "r"); if not f then return 0,0 end
  local rx, tx = 0, 0
  for line in f:lines() do
    local iface, rest = line:match("^%s*([%w%.]+):%s*(.+)$")
    if iface and iface ~= "lo" then
      local r, t = rest:match("^(%d+)%s+%d+%s+%d+%s+%d+%s+%d+%s+%d+%s+%d+%s+%d+%s+(%d+)")
      if r then
        rx = rx + (tonumber(r) or 0)
        tx = tx + (tonumber(t) or 0)
      end
    end
  end
  f:close()
  return rx, tx
end

local function net_rates()
  local rx, tx = read_net()
  local now = love.timer.getTime()
  local dl, ul = 0, 0
  if last_net.t > 0 then
    local dt = now - last_net.t
    if dt > 0 then
      dl = (rx - last_net.rx) / dt
      ul = (tx - last_net.tx) / dt
      if dl < 0 then dl = 0 end
      if ul < 0 then ul = 0 end
    end
  end
  last_net = { rx = rx, tx = tx, t = now }
  return dl, ul, rx, tx
end

local function reload_volumes()
  data.volumes = {}
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
  local SKIP = {
    proc=true, sysfs=true, tmpfs=true, devpts=true, cgroup=true, cgroup2=true,
    pstore=true, securityfs=true, debugfs=true, tracefs=true, configfs=true,
    fusectl=true, mqueue=true, hugetlbfs=true, binfmt_misc=true, rpc_pipefs=true,
    efivarfs=true, autofs=true, bpf=true, ramfs=true, devtmpfs=true,
  }
  local f = io.open("/proc/mounts", "r")
  if f then
    for line in f:lines() do
      local dev, mnt, fs, opts = line:match("^(%S+)%s+(%S+)%s+(%S+)%s+(%S+)")
      if dev and dev:sub(1,5) == "/dev/" and not SKIP[fs] then
        local d = dfmap[mnt] or {}
        data.volumes[#data.volumes+1] = {
          dev=dev, mnt=mnt, fs=fs, opts=opts,
          total=d.total, used=d.used, free=d.free,
        }
      end
    end
    f:close()
  end
  if #data.volumes == 0 then
    for _, m in ipairs({"/mnt/mmc","/mnt/sdcard"}) do
      local d = dfmap[m]
      if d then
        data.volumes[#data.volumes+1] = {
          dev="?", mnt=m, fs="?", opts="rw",
          total=d.total, used=d.used, free=d.free,
        }
      end
    end
  end
end

local function refresh_slow()
  -- CPU model
  data.model = "unknown"
  local f = io.open("/proc/cpuinfo", "r")
  if f then
    for line in f:lines() do
      local m = line:match("^model name%s*:%s*(.+)$")
             or line:match("^Hardware%s*:%s*(.+)$")
      if m then data.model = m; break end
    end
    f:close()
  end
  local h = io.popen("uname -srm 2>/dev/null")
  data.kern = (h and h:read("*l")) or "?"
  if h then h:close() end
  h = io.popen("hostname 2>/dev/null")
  data.host = (h and h:read("*l")) or "?"
  if h then h:close() end

  local c = 0
  local f2 = io.open("/proc/cpuinfo", "r")
  if f2 then
    for line in f2:lines() do if line:match("^processor") then c = c + 1 end end
    f2:close()
  end
  data.ncpu = c > 0 and c or 1

  local s = read_line("/proc/uptime")
  if s then
    local up = math.floor(tonumber(s:match("^(%d+)")) or 0)
    data.uptime = string.format("%dd %02dh %02dm",
      math.floor(up / 86400),
      math.floor((up % 86400) / 3600),
      math.floor((up % 3600) / 60))
  else data.uptime = "?" end

  data.battery = read_battery()

  -- memory
  local pct, tot, used = read_mem()
  data.mem_pct = pct
  data.mem_total = tot
  data.mem_used = used

  -- mounts
  reload_volumes()

  -- network interfaces
  data.net = {}
  local h3 = io.popen("ls /sys/class/net/ 2>/dev/null")
  if h3 then
    for name in h3:lines() do
      if name ~= "lo" then
        local st = read_line("/sys/class/net/" .. name .. "/operstate") or "?"
        local addr = "-"
        local ah = io.popen("ip -4 addr show " .. name ..
          " 2>/dev/null | grep -oE 'inet [0-9.]+' | head -1")
        if ah then
          local l = ah:read("*l") or ""; ah:close()
          local a = l:match("inet%s+([%d%.]+)")
          if a then addr = a end
        end
        data.net[#data.net+1] = { name=name, state=st, addr=addr }
      end
    end
    h3:close()
  end

  -- processes
  data.procs = {}
  local ph = io.popen("ps -eo pid,comm,rss,pcpu 2>/dev/null | tail -n +2 | sort -k3 -n -r | head -12")
  if ph then
    for line in ph:lines() do
      local pid, name, rss, cpu = line:match("^%s*(%d+)%s+(%S+)%s+(%d+)%s+([%d%.]+)")
      if pid then
        data.procs[#data.procs+1] = {
          pid=pid, name=name, rss=tonumber(rss)*1024, cpu=tonumber(cpu),
        }
      end
    end
    ph:close()
  end

  -- thermal zones
  data.sensors = {}
  for i = 0, 4 do
    local v = tonumber(read_line("/sys/class/thermal/thermal_zone" .. i .. "/temp"))
    local t = read_line("/sys/class/thermal/thermal_zone" .. i .. "/type")
    if v then
      if v > 1000 then v = v / 1000 end
      data.sensors[#data.sensors+1] = { name=t or ("zone"..i), value=v }
    end
  end
end

-- ============================================================
--  Snapshots and actions
-- ============================================================
local function push_log(line)
  data.log_lines[#data.log_lines+1] = line
  if #data.log_lines > 200 then table.remove(data.log_lines, 1) end
end

local function save_snapshot()
  os.execute("mkdir -p data/snapshots")
  local ts = os.date("%Y%m%d_%H%M%S")
  local path = "data/snapshots/" .. ts .. ".txt"
  local f = io.open(path, "w")
  if not f then
    Notify.show("error", "snapshot failed")
    return
  end
  f:write("=== File-GD X -- system snapshot ===\n")
  f:write("Time:   " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n")
  f:write("Host:   " .. (data.host or "?") .. "\n")
  f:write("Kernel: " .. (data.kern or "?") .. "\n")
  f:write("CPU:    " .. (data.model or "?") .. "\n")
  f:write("RAM:    " .. string.format("%.1f%%", data.mem_pct or 0) .. "\n")
  f:write("Temp:   " .. string.format("%.1f C", data.temp or 0) .. "\n")
  f:write("Uptime: " .. (data.uptime or "?") .. "\n")
  f:write("\n-- Mounts --\n")
  for _, m in ipairs(data.volumes or {}) do
    f:write(string.format("  %-14s %-16s %s free / %s\n",
      m.fs or "?", m.mnt or "?", human(m.free or 0), human(m.total or 0)))
  end
  f:write("\n-- Network --\n")
  for _, n in ipairs(data.net or {}) do
    f:write("  " .. n.name .. "  " .. n.state .. "  " .. n.addr .. "\n")
  end
  f:write("\n-- Processes --\n")
  for _, p in ipairs(data.procs or {}) do
    f:write(string.format("  %6s  %-16s  RSS %-10s  CPU %s%%\n",
      p.pid, (p.name or "?"):sub(1,16), human(p.rss), p.cpu))
  end
  f:close()
  Notify.show("success", "snapshot: " .. ts .. ".txt")
end

local function run_cmd_async(name, cmd)
  local ts = os.date("%H%M%S")
  local script = "/tmp/fgd_sys_" .. ts .. ".sh"
  local out    = "/tmp/fgd_sys_" .. ts .. ".out"
  local done   = "/tmp/fgd_sys_" .. ts .. ".done"
  local f = io.open(script, "w")
  if not f then return end
  f:write("#!/bin/sh\n")
  f:write("set +e\n")
  f:write(cmd .. " > " .. sh.shq(out) .. " 2>&1\n")
  f:write("touch " .. sh.shq(done) .. "\n")
  f:close()
  os.execute("chmod +x " .. sh.shq(script))
  os.execute("(setsid sh " .. sh.shq(script) .. " </dev/null >/dev/null 2>&1 &) " ..
    "|| (nohup sh " .. sh.shq(script) .. " >/dev/null 2>&1 &) " ..
    "|| (sh " .. sh.shq(script) .. " >/dev/null 2>&1 &)")
  push_log("> " .. name)
  push_log("> " .. cmd)
  push_log("")
  S._pending_cmd = { name = name, out = out, done = done, script = script, t = 0 }
end

local function poll_cmd(dt)
  local p = S._pending_cmd
  if not p then return end
  p.t = p.t + dt
  if p.t > 300 then
    os.execute("pkill -f " .. sh.shq(p.script) .. " 2>/dev/null")
    push_log("(timeout)")
    S._pending_cmd = nil
    return
  end
  local f = io.open(p.done, "r")
  if not f then
    -- stream output progressively
    local of = io.open(p.out, "r")
    if of then
      local all = of:read("*a") or ""
      of:close()
      -- only append lines we haven't already
      local n = 0
      for _ in all:gmatch("[^\n]+") do n = n + 1 end
      local cur = 0
      for _ in table.concat(data.log_lines, "\n"):gmatch("[^\n]+") do cur = cur + 1 end
      if n > cur then
        local skip = cur
        local i = 0
        for line in all:gmatch("[^\n]+") do
          i = i + 1
          if i > skip then push_log(line) end
        end
      end
    end
    return
  end
  f:close()
  -- final flush
  local of = io.open(p.out, "r")
  if of then
    local all = of:read("*a") or ""
    of:close()
    local cur = 0
    for _ in table.concat(data.log_lines, "\n"):gmatch("[^\n]+") do cur = cur + 1 end
    local i = 0
    for line in all:gmatch("[^\n]+") do
      i = i + 1
      if i > cur then push_log(line) end
    end
  end
  push_log("== done ==")
  os.remove(p.out); os.remove(p.done); os.remove(p.script)
  S._pending_cmd = nil
end

local function run_benchmark()
  Notify.show("info", "benchmark in corso...")
  local t0 = love.timer.getTime()
  local n = 0
  local acc = 0
  while love.timer.getTime() - t0 < 1.0 do
    for i = 1, 5000 do
      acc = acc + math.sin(i) * math.cos(i) + math.sqrt(i)
      n = n + 1
    end
  end
  local dt = love.timer.getTime() - t0
  local score = math.floor(n / dt)
  data.bench = { score = score, acc = acc, dt = dt }
  Notify.show("success", "bench: " .. score .. " ops/s")
end

local function sync_now()
  os.execute("sync")
  Notify.show("success", "sync completato")
end

local function drop_caches()
  os.execute("sync; echo 3 > /proc/sys/vm/drop_caches 2>/dev/null")
  Notify.show("info", "page cache svuotata")
  refresh_slow()
end

local function reload_all()
  refresh_slow()
  Notify.show("info", "system reload")
end

-- ============================================================
--  Disk tools (per volume)
-- ============================================================
local function vol_action(v, kind)
  if not v then return end
  local dev = v.dev
  local mnt = v.mnt
  if kind == "fsck" then
    Modal.show("FSCK " .. dev,
      "Check " .. dev .. " read-only?\nIl volume deve essere smontato o in ro.",
      { accept_label = "CHECK", cancel_label = "CANCEL",
        on_accept = function()
          local cmd
          if v.fs == "vfat" or v.fs == "msdos" then
            cmd = "fsck.vfat -n " .. sh.shq(dev)
          elseif v.fs == "exfat" then
            cmd = "fsck.exfat -n " .. sh.shq(dev) .. " 2>&1 || fsck -n " .. sh.shq(dev)
          else
            cmd = "fsck -n " .. sh.shq(dev)
          end
          run_cmd_async("fsck " .. dev, cmd)
        end })
  elseif kind == "badblocks" then
    Modal.show("badblocks " .. dev,
      "Scansione read-only per settori danneggiati.\nPuò durare molto.",
      { accept_label = "SCAN", cancel_label = "CANCEL",
        on_accept = function()
          run_cmd_async("badblocks " .. dev, "badblocks -sv " .. sh.shq(dev))
        end })
  elseif kind == "remount_ro" then
    Modal.show("Remount RO",
      "Rimontare " .. mnt .. " in sola lettura?",
      { accept_label = "REMOUNT", cancel_label = "CANCEL",
        on_accept = function()
          os.execute("mount -o remount,ro " .. sh.shq(mnt) .. " 2>/dev/null")
          Notify.show("info", "remount ro: " .. mnt)
          refresh_slow()
        end })
  elseif kind == "remount_rw" then
    os.execute("mount -o remount,rw " .. sh.shq(mnt) .. " 2>/dev/null")
    Notify.show("info", "remount rw: " .. mnt)
    refresh_slow()
  elseif kind == "opts" then
    Modal.show("Mount options",
      v.dev .. " on " .. v.mnt .. "\n" ..
      "fs: " .. v.fs .. "\n" ..
      "opts: " .. v.opts .. "\n" ..
      "free: " .. human(v.free or 0) .. " / " .. human(v.total or 0),
      { accept_label = "OK", hide_cancel = true })
  end
end

-- ============================================================
--  Lifecycle
-- ============================================================
function S.enter()
  t_enter = 0
  hist = { cpu = {}, ram = {}, temp = {}, dl = {}, ul = {} }
  sample_t = 0
  last_net = { rx = 0, tx = 0, t = 0 }
  last_cores = nil
  sel_map = {}
  scroll_map = {}
  refresh_slow()
  if State.system_section then
    cur_sec = math.max(1, math.min(NSEC, State.system_section))
    State.system_section = nil
  end
end

function S.leave()
  if S._pending_cmd then
    os.execute("pkill -f " .. sh.shq(S._pending_cmd.script) .. " 2>/dev/null")
    S._pending_cmd = nil
  end
end

function S.update(dt)
  t_enter = t_enter + dt
  sample_t = sample_t + dt
  if sample_t >= SAMPLE then
    sample_t = 0
    local cores = read_cpu_cores()
    local usage = compute_cores(cores)
    local avg = 0
    if #usage > 0 then
      for _, v in ipairs(usage) do avg = avg + v end
      avg = avg / #usage
    end
    data.core_usage = usage
    hist.cpu[#hist.cpu+1] = avg
    local ram = read_mem()
    hist.ram[#hist.ram+1] = ram
    local temp = read_temp()
    hist.temp[#hist.temp+1] = temp
    data.temp = temp
    local dl, ul = net_rates()
    hist.dl[#hist.dl+1] = dl
    hist.ul[#hist.ul+1] = ul
    data.last_dl = dl
    data.last_ul = ul
    for _, v in pairs(hist) do
      while #v > MAX_HIST do table.remove(v, 1) end
    end
    local pct, tot, used = read_mem()
    data.mem_pct = pct; data.mem_total = tot; data.mem_used = used
  end
  poll_cmd(dt)
end

-- ============================================================
--  Input
-- ============================================================
local function scroll_of(id) return scroll_map[id] or 0 end
local function sel_of(id)    return sel_map[id] or 1 end

local function set_scroll(id, v) scroll_map[id] = v end
local function set_sel(id, v)    sel_map[id] = v end

local function move_in_section(d)
  local id = SECTIONS[cur_sec].id
  local s = sel_of(id)
  local n = 0
  if id == "cockpit" then n = 0
  elseif id == "device" then n = 0
  elseif id == "storage" then n = #data.volumes + 5  -- volumes + 5 azioni
  elseif id == "network" then n = #data.net
  elseif id == "thermal" then n = #data.sensors
  elseif id == "processes" then n = #data.procs
  elseif id == "actions" then n = 7
  end
  if n == 0 then return end
  s = s + d
  if s < 1 then s = n end
  if s > n then s = 1 end
  set_sel(id, s)
end

local function activate()
  local id = SECTIONS[cur_sec].id
  if id == "storage" then
    local s = sel_of(id)
    if s <= #data.volumes then
      vol_action(data.volumes[s], "opts")
    else
      local a = s - #data.volumes
      if a == 1 then
        local v = data.volumes[sel_of(id)] or data.volumes[1]
        if v then vol_action(v, "fsck") end
      elseif a == 2 then
        local v = data.volumes[sel_of(id)] or data.volumes[1]
        if v then vol_action(v, "badblocks") end
      elseif a == 3 then
        local v = data.volumes[sel_of(id)] or data.volumes[1]
        if v then vol_action(v, "remount_ro") end
      elseif a == 4 then
        local v = data.volumes[sel_of(id)] or data.volumes[1]
        if v then vol_action(v, "remount_rw") end
      elseif a == 5 then
        run_cmd_async("df -h", "df -h")
      end
    end
  elseif id == "actions" then
    local s = sel_of(id)
    if     s == 1 then save_snapshot()
    elseif s == 2 then run_benchmark()
    elseif s == 3 then sync_now()
    elseif s == 4 then drop_caches()
    elseif s == 5 then run_cmd_async("df -h", "df -h")
    elseif s == 6 then run_cmd_async("mount", "cat /proc/mounts")
    elseif s == 7 then
      data.log_lines = {}
      Notify.show("info", "log cleared")
    end
  end
end

local function cycle_sec(d)
  cur_sec = cur_sec + d
  if cur_sec < 1 then cur_sec = NSEC end
  if cur_sec > NSEC then cur_sec = 1 end
end

function S.pad(b)
  if Modal.is_open() then
    if b == Input.A then Modal.accept()
    elseif b == Input.B then Modal.cancel() end
    return
  end
  if     b == Input.UP    then move_in_section(-1)
  elseif b == Input.DOWN  then move_in_section( 1)
  elseif b == Input.L1    then cycle_sec(-1)
  elseif b == Input.R1    then cycle_sec( 1)
  elseif b == Input.A     then activate()
  elseif b == Input.X     then save_snapshot()
  elseif b == Input.Y     then run_benchmark()
  elseif b == Input.START then reload_all()
  elseif b == Input.B or b == Input.SELECT then State.back() end
end

function S.hat(dir)
  if Modal.is_open() then return end
  if     dir == "up"   then move_in_section(-1)
  elseif dir == "down" then move_in_section( 1)
  elseif dir == "left" then cycle_sec(-1)
  elseif dir == "right" then cycle_sec( 1) end
end

function S.key(k)
  if Modal.is_open() then
    if k == "return" then Modal.accept()
    elseif k == "escape" then Modal.cancel() end
    return
  end
  if     k == "up"    then move_in_section(-1)
  elseif k == "down"  then move_in_section( 1)
  elseif k == "left"  then cycle_sec(-1)
  elseif k == "right" then cycle_sec( 1)
  elseif k == "return" or k == "space" then activate()
  elseif k == "x"    then save_snapshot()
  elseif k == "y"    then run_benchmark()
  elseif k == "r"    then reload_all()
  elseif k == "escape" or k == "backspace" then State.back() end
end

-- ============================================================
--  Drawing primitives
-- ============================================================
local function gauge(cx, cy, r, value, maxv, colour, label, unit)
  local a0 = math.rad(135)
  local sw = math.rad(270)
  local pct = math.max(0, math.min(1, value / maxv))
  col({0.05, 0.05, 0.06}, 1)
  love.graphics.circle("line", cx, cy, r)
  col({0.02, 0.03, 0.03}, 1)
  love.graphics.circle("fill", cx, cy, r - 1)
  col({0.10, 0.10, 0.11}, 1)
  love.graphics.setLineWidth(5)
  love.graphics.arc("line", "open", cx, cy, r - 6, a0, a0 + sw)
  col(colour, 0.95)
  love.graphics.setLineWidth(5)
  love.graphics.arc("line", "open", cx, cy, r - 6, a0, a0 + sw * pct)
  col({0.35, 0.35, 0.38}, 1)
  love.graphics.setLineWidth(1)
  for i = 0, 10 do
    local a = a0 + sw * (i / 10)
    local major = (i % 5 == 0)
    local r1 = r - 12
    local r2 = r - (major and 18 or 15)
    love.graphics.line(
      cx + math.cos(a) * r1, cy + math.sin(a) * r1,
      cx + math.cos(a) * r2, cy + math.sin(a) * r2)
  end
  local na = a0 + sw * pct
  col(colour, 1)
  love.graphics.setLineWidth(2.4)
  love.graphics.line(cx, cy,
    cx + math.cos(na) * (r - 14),
    cy + math.sin(na) * (r - 14))
  col({0.10, 0.10, 0.10}, 1)
  love.graphics.circle("fill", cx, cy, 4)
  col(colour, 1)
  love.graphics.circle("fill", cx, cy, 2)
  love.graphics.setFont(A.font(A.FONT_MONO, 15))
  col({1, 1, 1}, 1)
  local vtxt = string.format("%.0f%s", value, unit or "")
  local vw = love.graphics.getFont():getWidth(vtxt)
  love.graphics.print(vtxt, cx - vw/2, cy + r * 0.42)
  love.graphics.setFont(A.font(A.FONT_MONO, 9))
  col(colour, 1)
  local lw = love.graphics.getFont():getWidth(label)
  love.graphics.print(label, cx - lw/2, cy - r * 0.80)
end

local function sparkline(x, y, w, h, arr, colour, maxv)
  if not arr or #arr < 2 then return end
  maxv = maxv or 100
  col(colour, 0.75)
  love.graphics.setLineWidth(1.4)
  local pts = {}
  for i, v in ipairs(arr) do
    local px = x + (i - 1) / (MAX_HIST - 1) * w
    local py = y + h - math.max(0, math.min(1, v / maxv)) * h
    pts[#pts+1] = px; pts[#pts+1] = py
  end
  love.graphics.line(pts)
  love.graphics.setLineWidth(1)
end

local function small_bar(x, y, w, h, pct, colour)
  col({0.08, 0.08, 0.09}, 1)
  love.graphics.rectangle("fill", x, y, w, h, 1, 1)
  col(colour, 1)
  love.graphics.rectangle("fill", x, y, w * math.max(0, math.min(1, pct)), h, 1, 1)
  col(colour, 0.4)
  love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, 1, 1)
end

local function cpu_col(p)
  if p < 50 then return GRN end
  if p < 80 then return YEL end
  return RED
end

local function temp_col(t)
  if t < 50 then return GRN end
  if t < 70 then return YEL end
  return RED
end

local function panel_box(x, y, w, h, accent, focused)
  col({0.025, 0.024, 0.030}, 0.96)
  love.graphics.rectangle("fill", x, y, w, h, 4, 4)
  if focused then
    col(accent, 0.95)
    love.graphics.setLineWidth(2)
  else
    col(accent, 0.35)
    love.graphics.setLineWidth(1)
  end
  love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, 4, 4)
  love.graphics.setLineWidth(1)
  D.corner_ticks(x + 6, y + 6, w - 12, h - 12, 10, accent, focused and 0.9 or 0.35)
end

local function section_header(x, y, w, label, accent)
  love.graphics.setFont(A.font(A.FONT_MONO, 10))
  col(accent, 0.9)
  love.graphics.print(label, x, y)
  col(accent, 0.3)
  love.graphics.rectangle("fill", x, y + 14, w, 1)
end

-- ============================================================
--  Rail
-- ============================================================
local function draw_rail()
  local x, y = PAD, Frame.TOP_H + 6
  local w = RAIL_W
  local h = H - Frame.BOTTOM_H - y - 6
  col({0.018, 0.020, 0.024}, 0.95)
  love.graphics.rectangle("fill", x, y, w, h, 3, 3)
  col(CYA_HI, 0.30)
  love.graphics.setLineWidth(1)
  love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, 3, 3)
  love.graphics.setLineWidth(1)

  love.graphics.setFont(A.font(A.FONT_MONO, 9))
  col(CYA_HI, 0.9)
  love.graphics.print("SECTIONS", x + 10, y + 8)
  col(CYA_HI, 0.3)
  love.graphics.rectangle("fill", x + 10, y + 22, w - 20, 1)

  local slot_h = 40
  local sy = y + 32
  for i, sec in ipairs(SECTIONS) do
    local cy = sy + (i - 1) * (slot_h + 3)
    local focused = (i == cur_sec)
    local c = sec.accent

    if focused then
      col({c[1]*0.25, c[2]*0.25, c[3]*0.25}, 0.95)
      love.graphics.rectangle("fill", x + 6, cy, w - 12, slot_h, 3, 3)
      col(c, 0.95)
      love.graphics.setLineWidth(1.6)
      love.graphics.rectangle("line", x + 6.5, cy + 0.5, w - 13, slot_h - 1, 3, 3)
      love.graphics.setLineWidth(1)
      col(c, 1)
      love.graphics.rectangle("fill", x + 6, cy, 3, slot_h)
    else
      col({0.04, 0.05, 0.06}, 0.55)
      love.graphics.rectangle("fill", x + 6, cy, w - 12, slot_h, 3, 3)
      col(c, 0.35)
      love.graphics.rectangle("line", x + 6.5, cy + 0.5, w - 13, slot_h - 1, 3, 3)
    end

    love.graphics.setFont(A.font(A.FONT_MONO, 8))
    col(c, focused and 1 or 0.60)
    love.graphics.print(sec.tag, x + 14, cy + 5)

    love.graphics.setFont(A.font(A.FONT_BODY_BOLD, focused and 11 or 10))
    col(focused and {1,1,1} or {0.75,0.80,0.82}, 1)
    love.graphics.print(sec.label, x + 14, cy + 20)
  end
end

-- ============================================================
--  Content: COCKPIT
-- ============================================================
local function draw_cockpit(x, y, w, h)
  local acc = SECTIONS[1].accent
  section_header(x, y, w, "REAL-TIME METRICS", acc)
  y = y + 24

  local cpu_avg = 0
  if #hist.cpu > 0 then cpu_avg = hist.cpu[#hist.cpu] end
  local ram_pct = data.mem_pct or 0
  local temp = data.temp or 0
  local dl = data.last_dl or 0
  local ul = data.last_ul or 0

  local cy = y + 64
  local r = 34
  local spacing = w / 4
  gauge(x + spacing * 0.5, cy, r, cpu_avg, 100, cpu_col(cpu_avg), "CPU", "%")
  gauge(x + spacing * 1.5, cy, r, ram_pct, 100, cpu_col(ram_pct), "RAM", "%")
  gauge(x + spacing * 2.5, cy, r, temp, 100, temp_col(temp), "TEMP", "C")

  local net_max_kb = 5 * 1024 * 1024 / 1024  -- 5 MB/s in KB
  local net_val = math.max(dl, ul) / 1024
  gauge(x + spacing * 3.5, cy, r, net_val, net_max_kb,
    BLU, "NET", "K/s")

  love.graphics.setFont(A.font(A.FONT_MONO, 8))
  col(GRN, 1)
  love.graphics.print("D " .. human(dl) .. "/s",
    x + spacing * 3.5 - 38, cy + r + 6)
  col(ORG, 1)
  love.graphics.print("U " .. human(ul) .. "/s",
    x + spacing * 3.5 - 38, cy + r + 16)

  y = y + 130

  -- Per-core bars
  local usage = data.core_usage or {}
  if #usage > 0 then
    section_header(x, y, w, "CPU CORES (" .. #usage .. ")", acc)
    y = y + 22
    local nbars = #usage
    local cols = math.min(8, nbars)
    local rows = math.ceil(nbars / cols)
    local cw = (w - (cols - 1) * 8) / cols
    for i, v in ipairs(usage) do
      local cx = ((i - 1) % cols) * (cw + 8)
      local cyy = math.floor((i - 1) / cols) * 26
      small_bar(x + cx, y + cyy, cw, 12, v / 100, cpu_col(v))
      love.graphics.setFont(A.font(A.FONT_MONO, 8))
      col(GRY, 0.9)
      love.graphics.print(string.format("%02d %.0f%%", i, v),
        x + cx + 2, y + cyy + 14)
    end
    y = y + rows * 26 + 8
  end

  -- History sparklines
  section_header(x, y, w, "HISTORY (60 samples)", acc)
  y = y + 22
  local sh_h = 18
  love.graphics.setFont(A.font(A.FONT_MONO, 9))
  col(GRY, 1)
  love.graphics.print("CPU%", x, y + 4)
  sparkline(x + 46, y, w - 46, sh_h, hist.cpu, AMB, 100)
  y = y + 22
  love.graphics.print("RAM%", x, y + 4)
  sparkline(x + 46, y, w - 46, sh_h, hist.ram, CYA, 100)
  y = y + 22
  love.graphics.print("TEMP", x, y + 4)
  sparkline(x + 46, y, w - 46, sh_h, hist.temp, ORG, 100)
end

-- ============================================================
--  Content: DEVICE
-- ============================================================
local function draw_device(x, y, w, h)
  local acc = SECTIONS[2].accent
  section_header(x, y, w, "HARDWARE", acc)
  y = y + 24

  local function kv(k, v, col_k, col_v)
    love.graphics.setFont(A.font(A.FONT_MONO, 10))
    col(col_k or GRY, 0.9)
    love.graphics.print(k, x, y)
    love.graphics.setFont(A.font(A.FONT_BODY_BOLD, 11))
    col(col_v or {0.95,0.95,0.95}, 1)
    love.graphics.print(v or "?", x + 110, y - 1)
    y = y + 18
  end
  kv("MODEL",  (data.model or "?"):sub(1, 48))
  kv("KERNEL", data.kern or "?")
  kv("HOST",   data.host or "?")
  kv("CPU",    (data.ncpu or "?") .. " cores")
  kv("UPTIME", data.uptime or "?")

  y = y + 8
  section_header(x, y, w, "POWER & MEMORY", acc)
  y = y + 24
  if data.battery then
    local c = data.battery > 55 and GRN or (data.battery > 20 and YEL or RED)
    kv("BATTERY", string.format("%d%%", data.battery), GRY, c)
  else
    kv("BATTERY", "n/a")
  end
  local mem_pct = data.mem_pct or 0
  local c = mem_pct < 50 and GRN or (mem_pct < 75 and YEL or RED)
  kv("MEMORY", string.format("%.1f%%  %s / %s",
    mem_pct, human(data.mem_used or 0), human(data.mem_total or 0)),
    GRY, c)

  y = y + 8
  section_header(x, y, w, "BENCHMARK", acc)
  y = y + 24
  if data.bench then
    love.graphics.setFont(A.font(A.FONT_TITLE, 20))
    col(acc, 1)
    love.graphics.print(string.format("%d", data.bench.score), x, y)
    love.graphics.setFont(A.font(A.FONT_MONO, 9))
    col(GRY, 0.9)
    love.graphics.print("ops/s", x + 100, y + 6)
  else
    love.graphics.setFont(A.font(A.FONT_BODY, 11))
    col(GRY, 0.7)
    love.graphics.print("premi Y per eseguire il benchmark", x, y)
  end
end

-- ============================================================
--  Content: STORAGE
-- ============================================================
local function draw_storage(x, y, w, h)
  local acc = SECTIONS[3].accent
  section_header(x, y, w, "VOLUMES", acc)
  y = y + 24

  if #data.volumes == 0 then
    col(GRY, 0.8)
    love.graphics.setFont(A.font(A.FONT_BODY, 11))
    love.graphics.print("no volumes", x, y)
    y = y + 20
  else
    local row_h = 46
    for i, v in ipairs(data.volumes) do
      local focused = (sel_of("storage") == i)
      local ry = y + (i - 1) * (row_h + 4)
      if focused then
        col(acc, 0.15)
        love.graphics.rectangle("fill", x - 2, ry - 1, w + 4, row_h + 2, 3, 3)
        col(acc, 0.9)
        love.graphics.setLineWidth(1.4)
        love.graphics.rectangle("line", x - 1.5, ry - 0.5, w + 3, row_h + 1, 3, 3)
        love.graphics.setLineWidth(1)
      end
      love.graphics.setFont(A.font(A.FONT_BODY_BOLD, 11))
      col(focused and {1,1,1} or State.theme.text, 1)
      love.graphics.print(v.mnt:sub(1, 22), x, ry + 2)
      love.graphics.setFont(A.font(A.FONT_MONO, 9))
      col(GRY, 0.9)
      love.graphics.print(v.dev:sub(1, 22) .. "  " .. (v.fs or "?"),
        x, ry + 18)
      local pct = (v.total and v.total > 0) and (v.used / v.total) or 0
      local c = pct > 0.9 and RED or (pct > 0.7 and YEL or GRN)
      small_bar(x + w - 200, ry + 4, 190, 8, pct, c)
      love.graphics.setFont(A.font(A.FONT_MONO, 9))
      col(c, 1)
      love.graphics.printf(human(v.free or 0) .. " free",
        x + w - 200, ry + 16, 190, "right")
    end
    y = y + #data.volumes * (row_h + 4) + 6
  end

  section_header(x, y, w, "DISK TOOLS", acc)
  y = y + 24

  local actions = {
    { id="fsck",      label="FSCK (read-only)" },
    { id="badblocks", label="BADBLOCKS (read-only)" },
    { id="remount_ro",label="REMOUNT READ-ONLY" },
    { id="remount_rw",label="REMOUNT READ-WRITE" },
    { id="df",        label="DF -H (all volumes)" },
  }
  local base = #data.volumes
  for i, a in ipairs(actions) do
    local focused = (sel_of("storage") == base + i)
    local ry = y + (i - 1) * 22
    if focused then
      col(acc, 0.2)
      love.graphics.rectangle("fill", x - 2, ry, w + 4, 20, 3, 3)
      col(acc, 0.9)
      love.graphics.rectangle("line", x - 1.5, ry + 0.5, w + 3, 19, 3, 3)
      love.graphics.rectangle("fill", x - 2, ry + 3, 3, 14)
    end
    love.graphics.setFont(A.font(A.FONT_MONO, 11))
    col(focused and {1,1,1} or State.theme.text, 1)
    love.graphics.print("> " .. a.label, x + 4, ry + 3)
  end
  y = y + #actions * 22 + 8

  -- Log panel
  section_header(x, y, w, "LOG", acc)
  y = y + 18
  local max_lines = 8
  local first = math.max(1, #data.log_lines - max_lines + 1)
  love.graphics.setFont(A.font(A.FONT_MONO, 9))
  for i = first, #data.log_lines do
    local line = data.log_lines[i] or ""
    if line:find("error", 1, true) or line:find("Error", 1, true) then
      col(RED, 0.95)
    elseif line:sub(1,2) == "> " then
      col(acc, 1)
    elseif line:find("done") then
      col(GRN, 1)
    else
      col(State.theme.text, 0.9)
    end
    love.graphics.print(line:sub(1, 70), x, y + (i - first) * 11)
  end
end

-- ============================================================
--  Content: NETWORK
-- ============================================================
local function draw_network(x, y, w, h)
  local acc = SECTIONS[4].accent
  section_header(x, y, w, "INTERFACES", acc)
  y = y + 24
  if #data.net == 0 then
    col(GRY, 0.7)
    love.graphics.setFont(A.font(A.FONT_BODY, 11))
    love.graphics.print("no interfaces", x, y)
    return
  end
  for i, n in ipairs(data.net) do
    local focused = (sel_of("network") == i)
    local ry = y + (i - 1) * 26
    if focused then
      col(acc, 0.15)
      love.graphics.rectangle("fill", x - 2, ry - 1, w + 4, 24, 3, 3)
    end
    local up = (n.state == "up")
    col(up and GRN or GRY, 1)
    love.graphics.circle("fill", x + 8, ry + 11, 5)
    love.graphics.setFont(A.font(A.FONT_MONO, 11))
    col(State.theme.text_bright, 1)
    love.graphics.print(n.name, x + 22, ry + 2)
    col(CYA, 0.95)
    love.graphics.print(n.addr, x + 110, ry + 2)
    col(GRY, 0.9)
    love.graphics.printf(up and "UP" or "DOWN", x, ry + 2, w, "right")
  end

  y = y + #data.net * 26 + 12
  section_header(x, y, w, "TRAFFIC", acc)
  y = y + 22
  love.graphics.setFont(A.font(A.FONT_MONO, 11))
  col(GRN, 1)
  love.graphics.print("DOWN  " .. human(data.last_dl or 0) .. "/s", x, y)
  col(ORG, 1)
  love.graphics.print("UP    " .. human(data.last_ul or 0) .. "/s", x, y + 18)
end

-- ============================================================
--  Content: THERMAL
-- ============================================================
local function draw_thermal(x, y, w, h)
  local acc = SECTIONS[5].accent
  section_header(x, y, w, "THERMAL ZONES", acc)
  y = y + 24
  if #data.sensors == 0 then
    col(GRY, 0.7)
    love.graphics.setFont(A.font(A.FONT_BODY, 11))
    love.graphics.print("no sensors", x, y)
    return
  end
  for i, s in ipairs(data.sensors) do
    local focused = (sel_of("thermal") == i)
    local ry = y + (i - 1) * 34
    if focused then
      col(acc, 0.15)
      love.graphics.rectangle("fill", x - 2, ry - 1, w + 4, 32, 3, 3)
    end
    love.graphics.setFont(A.font(A.FONT_MONO, 10))
    col(State.theme.text_dim, 0.9)
    love.graphics.print((s.name or "?"):sub(1, 24), x, ry + 2)
    local c = temp_col(s.value)
    love.graphics.setFont(A.font(A.FONT_BODY_BOLD, 13))
    col(c, 1)
    love.graphics.printf(string.format("%.1f C", s.value), x, ry + 2, w, "right")
    small_bar(x, ry + 20, w, 6, s.value / 100, c)
  end
end

-- ============================================================
--  Content: PROCESSES
-- ============================================================
local function draw_processes(x, y, w, h)
  local acc = SECTIONS[6].accent
  section_header(x, y, w, "TOP PROCESSES", acc)
  y = y + 22
  love.graphics.setFont(A.font(A.FONT_MONO, 9))
  col(GRY, 1)
  love.graphics.print("PID", x, y)
  love.graphics.print("NAME", x + 60, y)
  love.graphics.printf("RSS", x, y, w - 100, "right")
  love.graphics.printf("CPU", x, y, w, "right")
  y = y + 14

  if #data.procs == 0 then
    col(GRY, 0.7)
    love.graphics.setFont(A.font(A.FONT_BODY, 11))
    love.graphics.print("no processes", x, y)
    return
  end

  for i, p in ipairs(data.procs) do
    local focused = (sel_of("processes") == i)
    local ry = y + (i - 1) * 16
    if focused then
      col(acc, 0.15)
      love.graphics.rectangle("fill", x - 2, ry - 1, w + 4, 15, 2, 2)
    end
    love.graphics.setFont(A.font(A.FONT_MONO, 10))
    col(State.theme.text, 0.95)
    love.graphics.print(p.pid, x, ry)
    love.graphics.print((p.name or "?"):sub(1, 18), x + 60, ry)
    col(acc, 0.9)
    love.graphics.printf(human(p.rss or 0), x, ry, w - 100, "right")
    col((p.cpu or 0) > 5 and RED or GRN, 1)
    love.graphics.printf(string.format("%.1f%%", p.cpu or 0),
      x, ry, w, "right")
  end
end

-- ============================================================
--  Content: ACTIONS
-- ============================================================
local function draw_actions(x, y, w, h)
  local acc = SECTIONS[7].accent
  section_header(x, y, w, "SYSTEM ACTIONS", acc)
  y = y + 26

  local actions = {
    { id="snapshot", label="SAVE SNAPSHOT",
      desc="state to data/snapshots/*.txt" },
    { id="bench",    label="RUN BENCHMARK",
      desc="1 second CPU test" },
    { id="sync",     label="SYNC FILESYSTEM",
      desc="flush write cache to disk" },
    { id="drop",     label="DROP PAGE CACHE",
      desc="free memory (requires root)" },
    { id="df",       label="DF -H",
      desc="disk usage of all volumes" },
    { id="mount",    label="LIST MOUNTS",
      desc="cat /proc/mounts" },
    { id="clearlog", label="CLEAR LOG PANEL",
      desc="wipe the log buffer" },
  }

  for i, a in ipairs(actions) do
    local focused = (sel_of("actions") == i)
    local ry = y + (i - 1) * 32
    if focused then
      col(acc, 0.18)
      love.graphics.rectangle("fill", x - 2, ry - 1, w + 4, 30, 3, 3)
      col(acc, 0.95)
      love.graphics.setLineWidth(1.4)
      love.graphics.rectangle("line", x - 1.5, ry - 0.5, w + 3, 29, 3, 3)
      love.graphics.setLineWidth(1)
      love.graphics.rectangle("fill", x - 2, ry + 4, 3, 22)
    end
    love.graphics.setFont(A.font(A.FONT_BODY_BOLD, 12))
    col(focused and {1,1,1} or State.theme.text, 1)
    love.graphics.print(a.label, x + 4, ry + 2)
    love.graphics.setFont(A.font(A.FONT_MONO, 9))
    col(GRY, 0.9)
    love.graphics.print(a.desc, x + 4, ry + 17)
  end
end

-- ============================================================
--  Main draw
-- ============================================================
function S.draw()
  D.bg()

  local sec = SECTIONS[cur_sec]
  local acc = sec.accent

  -- dots
  col(acc, 0.05)
  for y = Frame.TOP_H, H - Frame.BOTTOM_H, 20 do
    for x = 0, W, 20 do
      love.graphics.rectangle("fill", x, y, 1, 1)
    end
  end
  D.corner_ticks(4, Frame.TOP_H + 2, W - 8,
    H - Frame.TOP_H - Frame.BOTTOM_H - 4, 18, acc, 0.35)

  draw_rail()

  -- panel
  local x = PAD + RAIL_W + 6
  local y = Frame.TOP_H + 6
  local w = W - x - PAD
  local h = H - Frame.BOTTOM_H - y - 6
  panel_box(x, y, w, h, acc, true)

  -- panel header
  love.graphics.setFont(A.font(A.FONT_TITLE, 16))
  col(acc, 1)
  love.graphics.print(sec.label, x + 18, y + 10)
  love.graphics.setFont(A.font(A.FONT_MONO, 9))
  col(acc, 0.7)
  love.graphics.print("SLOT " .. sec.tag, x + 18, y + 32)

  -- live dot
  local pulse = 0.5 + 0.5 * math.sin(t_enter * 3)
  col(GRN, 0.3 + 0.5 * pulse)
  love.graphics.circle("fill", x + w - 22, y + 18, 8)
  col(GRN, 1)
  love.graphics.circle("fill", x + w - 22, y + 18, 3)

  col(acc, 0.3)
  love.graphics.rectangle("fill", x + 14, y + 50, w - 28, 1)

  local content_x = x + 14
  local content_y = y + 60
  local content_w = w - 28
  local content_h = h - 70

  love.graphics.setScissor(content_x, content_y, content_w, content_h)

  local id = sec.id
  if id == "cockpit" then
    draw_cockpit(content_x, content_y, content_w, content_h)
  elseif id == "device" then
    draw_device(content_x, content_y, content_w, content_h)
  elseif id == "storage" then
    draw_storage(content_x, content_y, content_w, content_h)
  elseif id == "network" then
    draw_network(content_x, content_y, content_w, content_h)
  elseif id == "thermal" then
    draw_thermal(content_x, content_y, content_w, content_h)
  elseif id == "processes" then
    draw_processes(content_x, content_y, content_w, content_h)
  elseif id == "actions" then
    draw_actions(content_x, content_y, content_w, content_h)
  end

  love.graphics.setScissor()

  Frame.draw_top("FGD", "device")
  Frame.draw_bottom({
    { key = "up",  label = "Move" },
    { key = "l1",  label = "Sec -" },
    { key = "r1",  label = "Sec +" },
    { key = "a",   label = "Run" },
    { key = "x",   label = "Snap" },
    { key = "y",   label = "Bench" },
    { key = "b",   label = "Back" },
  })
  Modal.draw()
  D.scanlines(W, H, 0.05)
  D.vignette(W, H, 0.55)
end

return S
