-- screens/storage.lua -- unified storage hub.
-- Four sections in a rail: VOLUMES, ANALYZE, DUPLICATES, CLEANUP.
-- Same layout language as GRID-DEV (rail + panel, cyan mecha frame,
-- per-section accent colour). Supersedes storage_peeper, doppel_defier
-- and disk_tools.

local A     = require("core.assets")
local State = require("core.state")
local Input = require("core.input_map")
local Frame = require("ui.frame")
local D     = require("ui.draw")
local Store = require("core.settings_store")
local Notify= require("ui.notify")
local Modal = require("ui.modal")
local sh    = require("core.sh")
local FS    = require("services.fs")

local S = {}
local W, H = 640, 480

local RAIL_W = 130
local PAD    = 10

local function col(c, a) love.graphics.setColor(c[1], c[2], c[3], a or 1) end

local function human(n)
  if not n or n <= 0 then return "0 B" end
  local u = {"B","KB","MB","GB","TB"}
  local i = 1
  while n >= 1024 and i < #u do n = n / 1024; i = i + 1 end
  if i == 1 then return string.format("%d %s", n, u[i]) end
  return string.format("%.1f %s", n, u[i])
end

-- ============================================================
--  Sections
-- ============================================================
local SEC_VOLUMES    = 1
local SEC_ANALYZE    = 2
local SEC_DUPLICATES = 3
local SEC_CLEANUP    = 4
local SEC_COUNT      = 4

local SECS = {
  { tag = "SLOT 01", name = "VOLUMES",    accent = {0.55, 0.85, 0.45} },
  { tag = "SLOT 02", name = "ANALYZE",    accent = {0.95, 0.65, 0.25} },
  { tag = "SLOT 03", name = "DUPLICATES", accent = {0.70, 0.55, 0.92} },
  { tag = "SLOT 04", name = "CLEANUP",    accent = {0.48, 0.80, 0.90} },
}

local cur_sec = SEC_VOLUMES
local t_enter = 0

-- ============================================================
--  Cached FS.is_dir (avoids forks during draw)
-- ============================================================
local _isdir_cache, _isdir_cache_t = {}, 0
local function cached_isdir(path)
  local now = love.timer.getTime()
  if (now - _isdir_cache_t) > 5 then
    _isdir_cache = {}
    _isdir_cache_t = now
  end
  if _isdir_cache[path] == nil then
    _isdir_cache[path] = FS.is_dir(path)
  end
  return _isdir_cache[path]
end

local ROOTS = {
  { key = "SD1",  label = "SD1",  path = "/mnt/mmc" },
  { key = "SD2",  label = "SD2",  path = "/mnt/sdcard" },
  { key = "HOME", label = "HOME", path = os.getenv("HOME") or "/tmp" },
  { key = "TMP",  label = "TMP",  path = "/tmp" },
}

local function available_roots()
  local out = {}
  for _, r in ipairs(ROOTS) do
    if cached_isdir(r.path) then out[#out + 1] = r end
  end
  return out
end

-- ============================================================
--  VOLUMES
-- ============================================================
local volumes = {}
local vol_sel = 1
local vol_refresh_t = 0

local function reload_volumes()
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
  local SKIP = {
    proc=true, sysfs=true, tmpfs=true, devpts=true, cgroup=true,
    cgroup2=true, pstore=true, securityfs=true, debugfs=true,
    tracefs=true, configfs=true, fusectl=true, mqueue=true,
    hugetlbfs=true, binfmt_misc=true, rpc_pipefs=true,
    efivarfs=true, autofs=true, bpf=true, ramfs=true, devtmpfs=true,
  }
  local f = io.open("/proc/mounts", "r")
  if f then
    for line in f:lines() do
      local dev, mnt, fs, opts = line:match("^(%S+)%s+(%S+)%s+(%S+)%s+(%S+)")
      if dev and dev:sub(1, 5) == "/dev/" and not SKIP[fs] then
        local d = dfmap[mnt] or {}
        volumes[#volumes + 1] = {
          dev = dev, mnt = mnt, fs = fs, opts = opts,
          total = d.total, used = d.used, free = d.free,
        }
      end
    end
    f:close()
  end
  if vol_sel > #volumes then vol_sel = math.max(1, #volumes) end
end

local function vol_move(d)
  if #volumes == 0 then return end
  vol_sel = vol_sel + d
  if vol_sel < 1 then vol_sel = 1 end
  if vol_sel > #volumes then vol_sel = #volumes end
end

local function vol_action()
  local v = volumes[vol_sel]
  if not v then return end
  Modal.show("Volume " .. v.mnt,
    v.dev .. "  " .. v.fs .. "\n" ..
    "Free: " .. human(v.free or 0) .. " / " .. human(v.total or 0) .. "\n" ..
    "Opts: " .. v.opts:sub(1, 50),
    { accept_label = "REMOUNT RO", cancel_label = "CLOSE",
      on_accept = function()
        os.execute("mount -o remount,ro " .. sh.shq(v.mnt) .. " 2>/dev/null")
        Notify.show("info", "remounted ro: " .. v.mnt)
        reload_volumes()
      end })
end

local function draw_volumes(accent)
  if #volumes == 0 then
    col(accent, 0.7)
    love.graphics.setFont(A.font(A.FONT_BODY, 12))
    love.graphics.printf("no physical volumes mounted", 0, H/2, W, "center")
    return
  end

  local x0 = PAD + RAIL_W + 20
  local y  = Frame.TOP_H + 80
  local w  = W - x0 - PAD - 20
  local row_h = 64

  for i, v in ipairs(volumes) do
    local ry = y + (i - 1) * (row_h + 6)
    if ry + row_h > H - Frame.BOTTOM_H - 10 then break end
    local focused = (i == vol_sel)

    if focused then
      col({accent[1]*0.18, accent[2]*0.18, accent[3]*0.18}, 0.95)
      love.graphics.rectangle("fill", x0, ry, w, row_h, 3, 3)
      col(accent, 0.9)
      love.graphics.setLineWidth(1.6)
      love.graphics.rectangle("line", x0 + 0.5, ry + 0.5, w - 1, row_h - 1, 3, 3)
      love.graphics.setLineWidth(1)
    else
      col({0.03, 0.04, 0.04}, 0.75)
      love.graphics.rectangle("fill", x0, ry, w, row_h, 3, 3)
      col(accent, 0.25)
      love.graphics.rectangle("line", x0 + 0.5, ry + 0.5, w - 1, row_h - 1, 3, 3)
    end

    love.graphics.setFont(A.font(A.FONT_MONO, 11))
    col(accent, focused and 1 or 0.7)
    love.graphics.print(v.dev, x0 + 12, ry + 8)

    love.graphics.setFont(A.font(A.FONT_BODY, 11))
    col({0.85, 0.90, 0.90}, 1)
    love.graphics.print(v.fs .. "  on  " .. v.mnt, x0 + 12, ry + 26)

    if v.total and v.total > 0 then
      local frac = v.used / v.total
      local bw, bh = w - 24, 6
      local bx, by = x0 + 12, ry + 46
      col({0.06, 0.07, 0.08}, 1)
      love.graphics.rectangle("fill", bx, by, bw, bh, 1, 1)
      local c = frac > 0.9 and {0.95,0.28,0.22}
             or (frac > 0.7 and {0.95,0.72,0.25} or accent)
      col(c, 0.95)
      love.graphics.rectangle("fill", bx + 1, by + 1, (bw - 2) * frac, bh - 2, 1, 1)

      love.graphics.setFont(A.font(A.FONT_MONO, 9))
      col(c, 1)
      love.graphics.printf(human(v.free) .. " free / " .. human(v.total),
        x0, ry + 44, w - 12, "right")
    end
  end
end

-- ============================================================
--  ANALYZE
-- ============================================================
local AN = {
  view = "select",
  target = 1,
  scan_id = nil,
  files = 0,
  cat_sizes = {},
  cat_total = 0,
  recover = { trash = 0, logs = 0, downloads = 0, tmp = 0 },
}
local CATS_AN = {
  { key = "ROM",     colour = {0.42, 0.72, 0.90}, exts = {
      iso=1, gcm=1, rvz=1, wbfs=1, wia=1, ciso=1, nkit=1, gcz=1,
      nes=1, snes=1, smc=1, gba=1, gbc=1, gb=1, nds=1, cso=1,
      ["3ds"]=1, cia=1, xci=1, nsp=1, nro=1, pbp=1, chd=1, cue=1,
      m3u=1, pce=1, gen=1, smd=1, ["32x"]=1, z64=1, n64=1, v64=1,
  } },
  { key = "VIDEO",   colour = {0.85, 0.42, 0.42}, exts = {
      mp4=1, mkv=1, avi=1, webm=1, mov=1, mpg=1, mpeg=1, m4v=1,
      flv=1, wmv=1, ["3gp"]=1, ogv=1, ts=1, m2ts=1,
  } },
  { key = "AUDIO",   colour = {0.90, 0.55, 0.35}, exts = {
      mp3=1, ogg=1, oga=1, wav=1, flac=1, opus=1, m4a=1, aac=1,
      wma=1, ape=1, mid=1, midi=1, mod=1, s3m=1, xm=1, it=1,
  } },
  { key = "IMAGE",   colour = {0.29, 0.62, 0.72}, exts = {
      png=1, jpg=1, jpeg=1, webp=1, bmp=1, gif=1, tiff=1, tif=1,
      svg=1, ico=1, heic=1, avif=1,
  } },
  { key = "ARCHIVE", colour = {0.60, 0.50, 0.80}, exts = {
      zip=1, rar=1, ["7z"]=1, tar=1, gz=1, bz2=1, xz=1, tgz=1,
      lz4=1, zst=1, lzma=1, cab=1, arj=1, zipx=1,
      muxapp=1, muxzip=1, muxupd=1, muxthm=1,
  } },
  { key = "OTHER",   colour = {0.55, 0.55, 0.60}, exts = {} },
}

local function an_category_of(name)
  local ext = name:match("%.([^%.]+)$")
  if ext then ext = ext:lower() end
  if not ext then return "OTHER" end
  for _, cat in ipairs(CATS_AN) do
    if cat.exts[ext] then return cat.key end
  end
  return "OTHER"
end

local function an_du_kb(path)
  if not path then return 0 end
  local r = sh.read("du -sk " .. sh.shq(path) .. " 2>/dev/null | cut -f1")
  return (tonumber(r or "0") or 0) * 1024
end

local function an_target_path()
  local roots = available_roots()
  if #roots == 0 then return nil end
  if AN.target > #roots then AN.target = 1 end
  return roots[AN.target].path
end

local function an_start()
  local path = an_target_path()
  if not path then
    Notify.show("warning", "no target available"); return
  end
  AN.view = "scanning"
  AN.scan_id = tostring(os.time()) .. "_" .. tostring(math.random(1000,9999))
  AN.files = 0
  AN.cat_sizes = {}
  for _, c in ipairs(CATS_AN) do AN.cat_sizes[c.key] = 0 end
  AN.cat_total = 0

  local id     = AN.scan_id
  local out    = "/tmp/str_an_" .. id .. ".out"
  local done   = "/tmp/str_an_" .. id .. ".done"
  local script = "/tmp/str_an_" .. id .. ".sh"

  local body = table.concat({
    "set +e",
    "OUT=" .. sh.shq(out),
    "DONE=" .. sh.shq(done),
    ': > "$OUT"',
    "if ! find " .. sh.shq(path) .. " -type f -printf '%s\\t%p\\n' 2>/dev/null > \"$OUT\"; then",
    "  find " .. sh.shq(path) .. " -type f -exec stat -c '%s|%n' {} + 2>/dev/null | tr '|' '\\t' > \"$OUT\"",
    "fi",
    'touch "$DONE"',
  }, "\n")

  local f = io.open(script, "w")
  if not f then AN.view = "select"; return end
  f:write("#!/bin/sh\n" .. body); f:close()
  os.execute("chmod +x " .. sh.shq(script))
  os.execute("setsid sh " .. sh.shq(script) .. " </dev/null >/dev/null 2>&1 &")
end

local function an_poll()
  if not AN.scan_id then return end
  local id = AN.scan_id
  local done = "/tmp/str_an_" .. id .. ".done"
  if not io.open(done, "r") then return end

  local out = "/tmp/str_an_" .. id .. ".out"
  local f = io.open(out, "r")
  if f then
    for line in f:lines() do
      local sz, path = line:match("^(%d+)%s+(.+)$")
      if not sz then sz, path = line:match("^(%d+)|(.+)$") end
      if sz and path then
        AN.files = AN.files + 1
        local c = an_category_of(path)
        AN.cat_sizes[c] = (AN.cat_sizes[c] or 0) + (tonumber(sz) or 0)
        AN.cat_total = AN.cat_total + (tonumber(sz) or 0)
      end
    end
    f:close()
  end

  os.remove(out); os.remove(done)
  os.remove("/tmp/str_an_" .. id .. ".sh")
  AN.scan_id = nil
  AN.view = "results"

  AN.recover.trash     = an_du_kb("data/trash")
  AN.recover.logs      = an_du_kb("data/logs") + an_du_kb(".desktopbase/logs")
  AN.recover.downloads = an_du_kb("data/downloads")
  local tmp_out = sh.read("find /tmp -maxdepth 1 \\( -name 'fgd_*' -o -name 'str_*' -o -name 'dup_*' \\) 2>/dev/null | xargs -r stat -c %s 2>/dev/null | awk '{s+=$1} END {print s+0}'")
  AN.recover.tmp = tonumber(tmp_out or "0") or 0

  Notify.show("success", AN.files .. " files analyzed")
end

local function draw_analyze_results(accent)
  local x0 = PAD + RAIL_W + 20
  local y  = Frame.TOP_H + 80
  local w  = W - x0 - PAD - 20

  local rank = {}
  for _, c in ipairs(CATS_AN) do
    rank[#rank + 1] = { key = c.key, colour = c.colour, size = AN.cat_sizes[c.key] or 0 }
  end
  table.sort(rank, function(a, b) return a.size > b.size end)

  local max_sz = math.max(1, (rank[1] and rank[1].size) or 1)
  local row_h = 26
  for i = 1, math.min(6, #rank) do
    local r = rank[i]
    local ry = y + (i - 1) * row_h
    love.graphics.setFont(A.font(A.FONT_BODY_BOLD, 11))
    col(r.colour, 1)
    love.graphics.print(string.format("%d. %s", i, r.key), x0, ry)

    local bar_x, bar_w, bar_h = x0 + 110, w - 210, 8
    col({0.06, 0.07, 0.08}, 1)
    love.graphics.rectangle("fill", bar_x, ry + 4, bar_w, bar_h, 2, 2)
    col(r.colour, 0.9)
    love.graphics.rectangle("fill", bar_x + 1, ry + 5,
      (bar_w - 2) * (r.size / max_sz), bar_h - 2, 1, 1)

    love.graphics.setFont(A.font(A.FONT_MONO, 11))
    col(r.colour, 1)
    love.graphics.printf(human(r.size), x0, ry, w, "right")
  end

  local ry = y + 6 * row_h + 10
  col({0.10, 0.12, 0.14}, 0.9)
  love.graphics.rectangle("fill", x0, ry, w, 60, 3, 3)
  col(accent, 0.85)
  love.graphics.rectangle("line", x0 + 0.5, ry + 0.5, w - 1, 59, 3, 3)

  local total = AN.recover.trash + AN.recover.logs
             + AN.recover.downloads + AN.recover.tmp
  love.graphics.setFont(A.font(A.FONT_TITLE, 20))
  col(accent, 1)
  love.graphics.print(human(total), x0 + 16, ry + 12)

  love.graphics.setFont(A.font(A.FONT_BODY, 10))
  col(0.75, 0.80, 0.82, 1)
  love.graphics.print("can be freed by CLEANUP", x0 + 16, ry + 38)
end

-- ============================================================
--  DUPLICATES
-- ============================================================
local DU = {
  view = "select",
  target = 1,
  scan_id = nil,
  groups = {},
  bytes_saved = 0,
  group_sel = 1,
  file_sel = 1,
  keep = {},
}

local function du_target_path()
  local roots = available_roots()
  if #roots == 0 then return nil end
  if DU.target > #roots then DU.target = 1 end
  return roots[DU.target].path
end

local function du_start()
  local path = du_target_path()
  if not path then
    Notify.show("warning", "no target available"); return
  end
  DU.view = "scanning"
  DU.groups = {}
  DU.keep = {}
  DU.bytes_saved = 0
  DU.scan_id = tostring(os.time()) .. "_" .. tostring(math.random(1000,9999))

  local id     = DU.scan_id
  local out    = "/tmp/str_du_" .. id .. ".out"
  local done   = "/tmp/str_du_" .. id .. ".done"
  local script = "/tmp/str_du_" .. id .. ".sh"
  local inv    = "/tmp/str_du_inv_" .. id .. ".txt"
  local sizes  = "/tmp/str_du_sz_"  .. id .. ".txt"

  local body = table.concat({
    "set +e",
    "OUT="   .. sh.shq(out),
    "DONE="  .. sh.shq(done),
    "INV="   .. sh.shq(inv),
    "SIZES=" .. sh.shq(sizes),
    ': > "$OUT"',
    "if ! find " .. sh.shq(path) .. " -type f -printf '%s\\t%p\\n' 2>/dev/null > \"$INV\"; then",
    "  : > \"$INV\"",
    "  find " .. sh.shq(path) .. " -type f -exec stat -c '%s|%n' {} + 2>/dev/null | tr '|' '\\t' > \"$INV\"",
    "fi",
    "cut -f1 \"$INV\" | sort | uniq -d > \"$SIZES\"",
    "while IFS= read -r sz; do",
    "  [ -z \"$sz\" ] && continue",
    "  awk -F'\\t' -v s=\"$sz\" '$1 == s { print $2 }' \"$INV\" | while IFS= read -r f; do",
    "    [ -f \"$f\" ] || continue",
    "    H=$(md5sum \"$f\" 2>/dev/null | cut -d' ' -f1)",
    "    [ -n \"$H\" ] && printf '%s|%s|%s\\n' \"$sz\" \"$H\" \"$f\" >> \"$OUT\"",
    "  done",
    "done < \"$SIZES\"",
    "touch \"$DONE\"",
    "rm -f \"$INV\" \"$SIZES\"",
  }, "\n")

  local f = io.open(script, "w")
  if not f then DU.view = "select"; return end
  f:write("#!/bin/sh\n" .. body); f:close()
  os.execute("chmod +x " .. sh.shq(script))
  os.execute("setsid sh " .. sh.shq(script) .. " </dev/null >/dev/null 2>&1 &")
end

local function du_poll()
  if not DU.scan_id then return end
  local id = DU.scan_id
  local done = "/tmp/str_du_" .. id .. ".done"
  if not io.open(done, "r") then return end

  local out = "/tmp/str_du_" .. id .. ".out"
  local buckets = {}
  local f = io.open(out, "r")
  if f then
    for line in f:lines() do
      local sz, hash, path = line:match("^(%d+)|(%x+)|(.+)$")
      if sz and hash and path then
        local key = sz .. "|" .. hash
        buckets[key] = buckets[key] or { size = tonumber(sz), hash = hash, paths = {} }
        buckets[key].paths[#buckets[key].paths + 1] = path
      end
    end
    f:close()
  end

  local groups = {}
  for _, g in pairs(buckets) do
    if #g.paths > 1 then
      table.sort(g.paths)
      groups[#groups + 1] = g
    end
  end
  table.sort(groups, function(a, b) return a.size > b.size end)

  local bytes = 0
  for _, g in ipairs(groups) do
    bytes = bytes + g.size * (#g.paths - 1)
  end

  DU.groups = groups
  DU.bytes_saved = bytes
  for _, g in ipairs(groups) do DU.keep[g.paths[1]] = true end

  DU.view = (#groups == 0) and "select" or "groups"
  DU.group_sel = 1
  DU.file_sel = 1

  os.remove(out); os.remove(done)
  os.remove("/tmp/str_du_" .. id .. ".sh")
  DU.scan_id = nil

  Notify.show("success", #groups .. " duplicate group(s)")
end

local function du_apply_group()
  local g = DU.groups[DU.group_sel]
  if not g then return end
  local n = 0
  local Trash = require("services.trash")
  for _, p in ipairs(g.paths) do
    if not DU.keep[p] then
      if Trash.move(p) then n = n + 1 end
    end
  end
  Notify.show("info", n .. " moved to trash")
  for i, gg in ipairs(DU.groups) do
    if gg == g then table.remove(DU.groups, i); break end
  end
  if DU.group_sel > #DU.groups then DU.group_sel = math.max(1, #DU.groups) end
  if #DU.groups == 0 then DU.view = "select" end
end

local function draw_du_groups(accent)
  local x0 = PAD + RAIL_W + 20
  local y  = Frame.TOP_H + 80
  local w  = W - x0 - PAD - 20

  col(accent, 1)
  love.graphics.setFont(A.font(A.FONT_BODY_BOLD, 12))
  love.graphics.printf(#DU.groups .. " group(s) - " .. human(DU.bytes_saved) .. " reclaimable",
    0, y - 30, W - PAD, "center")

  if #DU.groups == 0 then
    col(0.85, 0.90, 0.90, 1)
    love.graphics.setFont(A.font(A.FONT_BODY, 12))
    love.graphics.printf("no duplicates found", 0, H/2, W, "center")
    return
  end

  local row_h = 28
  local first = math.max(1, DU.group_sel - 6)
  local last  = math.min(#DU.groups, first + 12)
  for i = first, last do
    local g = DU.groups[i]
    local ry = y + (i - first) * row_h
    local focused = (i == DU.group_sel)

    if focused then
      col({accent[1]*0.20, accent[2]*0.20, accent[3]*0.20}, 0.95)
      love.graphics.rectangle("fill", x0, ry, w, row_h - 2, 3, 3)
    end

    love.graphics.setFont(A.font(A.FONT_BODY_BOLD, 11))
    col(focused and {1,1,1} or {0.85,0.88,0.88}, 1)
    local name = g.paths[1]:match("([^/]+)$") or "?"
    love.graphics.print(name:sub(1, 44), x0 + 10, ry + 6)

    love.graphics.setFont(A.font(A.FONT_MONO, 9))
    col(accent, focused and 1 or 0.65)
    love.graphics.printf(#g.paths .. " x  " .. human(g.size),
      x0, ry + 7, w - 10, "right")
  end
end

local function draw_du_detail(accent)
  local g = DU.groups[DU.group_sel]
  if not g then DU.view = "groups"; return end

  local x0 = PAD + RAIL_W + 20
  local y  = Frame.TOP_H + 80
  local w  = W - x0 - PAD - 20

  col(accent, 1)
  love.graphics.setFont(A.font(A.FONT_MONO, 10))
  love.graphics.printf("MD5 " .. g.hash:sub(1, 16) .. "...",
    0, y - 24, W - PAD, "center")

  local row_h = 36
  local first = math.max(1, DU.file_sel - 5)
  local last  = math.min(#g.paths, first + 10)
  for i = first, last do
    local p = g.paths[i]
    local ry = y + (i - first) * row_h
    local focused = (i == DU.file_sel)
    local kept = DU.keep[p]
    local c = kept and {0.40, 0.85, 0.50} or {0.95, 0.35, 0.30}

    col({c[1]*0.20, c[2]*0.20, c[3]*0.20}, focused and 0.95 or 0.5)
    love.graphics.rectangle("fill", x0, ry, w, row_h - 3, 3, 3)
    col(c, focused and 1 or 0.55)
    love.graphics.rectangle("line", x0 + 0.5, ry + 0.5, w - 1, row_h - 4, 3, 3)

    local icx, icy = x0 + 22, ry + row_h/2 - 2
    col(c, 1)
    love.graphics.setLineWidth(2.4)
    if kept then
      love.graphics.line(icx - 6, icy, icx - 1, icy + 5, icx + 7, icy - 6)
    else
      love.graphics.line(icx - 6, icy - 6, icx + 6, icy + 6)
      love.graphics.line(icx - 6, icy + 6, icx + 6, icy - 6)
    end
    love.graphics.setLineWidth(1)

    love.graphics.setFont(A.font(A.FONT_BODY_BOLD, 10))
    col(c, 1)
    love.graphics.print((p:match("([^/]+)$") or p):sub(1, 42), x0 + 38, ry + 4)

    love.graphics.setFont(A.font(A.FONT_MONO, 9))
    col({0.72,0.76,0.80}, 0.85)
    love.graphics.print(p:sub(1, 90), x0 + 38, ry + 20)
  end
end

-- ============================================================
--  CLEANUP
-- ============================================================
local CL = {
  sel = 1,
  items = {
    { key = "trash",     label = "Trash contents",     path = "data/trash",     btn = "WIPE" },
    { key = "logs",      label = "Application logs",   path = "data/logs",      btn = "WIPE" },
    { key = "downloads", label = "Downloaded files",   path = "data/downloads", btn = "WIPE" },
    { key = "tmp",       label = "Temp working files", path = "/tmp",           btn = "WIPE" },
    { key = "snapshots", label = "System snapshots",   path = "data/snapshots", btn = "WIPE" },
  },
}

local function cl_do(item)
  local cmd
  if item.key == "trash" then
    local Trash = require("services.trash")
    Trash.purge_all()
    Notify.show("warning", "trash cleared")
  elseif item.key == "logs" then
    os.execute("rm -f data/logs/*.log .desktopbase/logs/*.log 2>/dev/null")
    Notify.show("warning", "logs cleared")
  elseif item.key == "downloads" then
    os.execute("rm -f data/downloads/* 2>/dev/null")
    Notify.show("warning", "downloads cleared")
  elseif item.key == "tmp" then
    os.execute("rm -rf /tmp/fgd_* /tmp/str_* /tmp/dup_* /tmp/sp_* 2>/dev/null")
    Notify.show("warning", "temp cleared")
  elseif item.key == "snapshots" then
    os.execute("rm -f data/snapshots/*.txt data/snapshots/*.log 2>/dev/null")
    Notify.show("warning", "snapshots cleared")
  end
end

local _cl_size_cache = {}
local _cl_size_cache_t = 0
local CL_SIZE_TTL = 5

local function cl_size_of(item)
  local now = love.timer.getTime()
  if (now - _cl_size_cache_t) > CL_SIZE_TTL then
    _cl_size_cache = {}
    _cl_size_cache_t = now
  end
  if _cl_size_cache[item.key] ~= nil then
    return _cl_size_cache[item.key]
  end
  local sz
  if item.key == "trash" then
    local Trash = require("services.trash")
    sz = Trash.size()
  else
    local r = sh.read("du -sk " .. sh.shq(item.path) .. " 2>/dev/null | cut -f1")
    sz = (tonumber(r or "0") or 0) * 1024
  end
  _cl_size_cache[item.key] = sz
  return sz
end

local function draw_cleanup(accent)
  local x0 = PAD + RAIL_W + 20
  local y  = Frame.TOP_H + 80
  local w  = W - x0 - PAD - 20
  local row_h = 44

  col({0.85, 0.90, 0.90}, 1)
  love.graphics.setFont(A.font(A.FONT_BODY, 11))
  love.graphics.printf("Quick cleanup of caches and temporary data",
    0, y - 30, W - PAD, "center")

  for i, item in ipairs(CL.items) do
    local ry = y + (i - 1) * (row_h + 4)
    local focused = (i == CL.sel)

    if focused then
      col({accent[1]*0.20, accent[2]*0.20, accent[3]*0.20}, 0.95)
      love.graphics.rectangle("fill", x0, ry, w, row_h, 3, 3)
      col(accent, 0.9)
      love.graphics.setLineWidth(1.6)
      love.graphics.rectangle("line", x0 + 0.5, ry + 0.5, w - 1, row_h - 1, 3, 3)
      love.graphics.setLineWidth(1)
    else
      col({0.03, 0.04, 0.05}, 0.75)
      love.graphics.rectangle("fill", x0, ry, w, row_h, 3, 3)
      col(accent, 0.25)
      love.graphics.rectangle("line", x0 + 0.5, ry + 0.5, w - 1, row_h - 1, 3, 3)
    end

    love.graphics.setFont(A.font(A.FONT_BODY_BOLD, 12))
    col(accent, focused and 1 or 0.75)
    love.graphics.print(item.label, x0 + 16, ry + 8)

    local sz = cl_size_of(item)
    love.graphics.setFont(A.font(A.FONT_MONO, 10))
    col({0.75,0.80,0.82}, focused and 1 or 0.6)
    love.graphics.print(human(sz), x0 + 16, ry + 24)

    local bw, bh = 70, 20
    local bx = x0 + w - bw - 10
    local by = ry + (row_h - bh) / 2
    col({accent[1]*0.22, accent[2]*0.22, accent[3]*0.22}, 1)
    love.graphics.rectangle("fill", bx, by, bw, bh, 3, 3)
    col(accent, focused and 0.95 or 0.55)
    love.graphics.rectangle("line", bx + 0.5, by + 0.5, bw - 1, bh - 1, 3, 3)
    love.graphics.setFont(A.font(A.FONT_MONO, 9))
    col(accent, focused and 1 or 0.75)
    love.graphics.printf(item.btn, bx, by + 5, bw, "center")
  end
end

-- ============================================================
--  Shared: select-root panel (used by ANALYZE and DUPLICATES)
-- ============================================================
local function draw_select_root(roots, target)
  col({0.85, 0.90, 0.90}, 1)
  love.graphics.setFont(A.font(A.FONT_BODY, 12))
  love.graphics.printf("Select a target to scan",
    0, Frame.TOP_H + 68, W - PAD, "center")

  local x0 = PAD + RAIL_W + 40
  local w  = W - x0 - PAD - 40
  local row_h = 36
  local y0 = Frame.TOP_H + 110
  for i, r in ipairs(roots) do
    local y = y0 + (i - 1) * (row_h + 6)
    local focused = (i == target)
    local accent = SECS[cur_sec].accent

    if focused then
      col({accent[1]*0.20, accent[2]*0.20, accent[3]*0.20}, 0.95)
      love.graphics.rectangle("fill", x0, y, w, row_h, 3, 3)
      col(accent, 0.9)
      love.graphics.setLineWidth(1.6)
      love.graphics.rectangle("line", x0 + 0.5, y + 0.5, w - 1, row_h - 1, 3, 3)
      love.graphics.setLineWidth(1)
    else
      col({0.03, 0.04, 0.05}, 0.75)
      love.graphics.rectangle("fill", x0, y, w, row_h, 3, 3)
      col(accent, 0.30)
      love.graphics.rectangle("line", x0 + 0.5, y + 0.5, w - 1, row_h - 1, 3, 3)
    end

    love.graphics.setFont(A.font(A.FONT_BODY_BOLD, 13))
    col(accent, focused and 1 or 0.75)
    love.graphics.print(r.label, x0 + 16, y + 10)

    love.graphics.setFont(A.font(A.FONT_MONO, 10))
    col({0.75, 0.80, 0.82}, focused and 0.9 or 0.6)
    love.graphics.print(r.path, x0 + 90, y + 12)
  end
end

local function draw_spinner(label, sec)
  local accent = SECS[sec].accent
  col(accent, 1)
  love.graphics.setFont(A.font(A.FONT_TITLE, 22))
  love.graphics.printf(label, 0, H/2 - 40, W, "center")

  local pulse = 0.3 + 0.7 * math.abs(math.sin(t_enter * 3))
  local bw = 280
  local bx = (W - bw) / 2
  col(accent, 0.9)
  love.graphics.rectangle("fill", bx, H/2 + 6, bw * pulse, 4)

  col(accent, 0.7)
  love.graphics.setFont(A.font(A.FONT_BODY, 11))
  love.graphics.printf("[B] cancel", 0, H/2 + 30, W, "center")
end

-- ============================================================
--  Lifecycle
-- ============================================================
function S.enter()
  t_enter = 0
  cur_sec = State.storage_section or SEC_VOLUMES
  State.storage_section = nil
  reload_volumes()
  vol_sel = 1
  AN.view = "select"; AN.target = 1
  DU.view = "select"; DU.target = 1
  CL.sel = 1
end
function S.leave() end

function S.update(dt)
  t_enter = t_enter + dt
  vol_refresh_t = vol_refresh_t + dt
  if vol_refresh_t > 2 then
    vol_refresh_t = 0
    if cur_sec == SEC_VOLUMES then reload_volumes() end
  end
  if AN.view == "scanning" then an_poll() end
  if DU.view == "scanning" then du_poll() end
end

-- ============================================================
--  Input
-- ============================================================
local function sec_switch(d)
  cur_sec = ((cur_sec - 1 + d) % SEC_COUNT) + 1
end

function S.pad(b)
  if Modal.is_open() then
    if b == Input.A then Modal.accept()
    elseif b == Input.B then Modal.cancel() end
    return
  end

  if b == Input.L1 then sec_switch(-1); return end
  if b == Input.R1 then sec_switch( 1); return end

  if cur_sec == SEC_VOLUMES then
    if     b == Input.UP    then vol_move(-1)
    elseif b == Input.DOWN  then vol_move( 1)
    elseif b == Input.A     then vol_action()
    elseif b == Input.START then reload_volumes(); Notify.show("info", "reloaded")
    elseif b == Input.B or b == Input.SELECT then State.back() end

  elseif cur_sec == SEC_ANALYZE then
    if AN.view == "select" then
      local roots = available_roots()
      if     b == Input.UP   then AN.target = math.max(1, math.min(#roots, AN.target - 1))
      elseif b == Input.DOWN then AN.target = math.max(1, math.min(#roots, AN.target + 1))
      elseif b == Input.A    then an_start()
      elseif b == Input.B or b == Input.SELECT then State.back() end
    elseif AN.view == "results" then
      if b == Input.A then an_start() end
      if b == Input.START then AN.view = "select" end
      if b == Input.B or b == Input.SELECT then AN.view = "select" end
    elseif AN.view == "scanning" then
      if b == Input.B then
        if AN.scan_id then
          os.execute("pkill -f 'str_an_" .. AN.scan_id .. "' 2>/dev/null")
          AN.scan_id = nil
        end
        AN.view = "select"
      end
    end

  elseif cur_sec == SEC_DUPLICATES then
    if DU.view == "select" then
      local roots = available_roots()
      if     b == Input.UP   then DU.target = math.max(1, math.min(#roots, DU.target - 1))
      elseif b == Input.DOWN then DU.target = math.max(1, math.min(#roots, DU.target + 1))
      elseif b == Input.A    then du_start()
      elseif b == Input.B or b == Input.SELECT then State.back() end
    elseif DU.view == "groups" then
      if     b == Input.UP   then DU.group_sel = math.max(1, DU.group_sel - 1)
      elseif b == Input.DOWN then DU.group_sel = math.min(#DU.groups, DU.group_sel + 1)
      elseif b == Input.A    then
        if #DU.groups > 0 then DU.view = "detail"; DU.file_sel = 1 end
      elseif b == Input.B or b == Input.SELECT then DU.view = "select" end
    elseif DU.view == "detail" then
      local g = DU.groups[DU.group_sel]
      if g then
        if     b == Input.UP   then DU.file_sel = math.max(1, DU.file_sel - 1)
        elseif b == Input.DOWN then DU.file_sel = math.min(#g.paths, DU.file_sel + 1)
        elseif b == Input.A or b == Input.X then
          local p = g.paths[DU.file_sel]
          if p then DU.keep[p] = (not DU.keep[p]) or nil end
        elseif b == Input.Y then
          Modal.show("Delete duplicates", "Move unmarked files to trash?",
            { accept_label = "DELETE", cancel_label = "CANCEL",
              on_accept = du_apply_group })
        elseif b == Input.B or b == Input.SELECT then DU.view = "groups" end
      end
    elseif DU.view == "scanning" then
      if b == Input.B then
        if DU.scan_id then
          os.execute("pkill -f 'str_du_" .. DU.scan_id .. "' 2>/dev/null")
          DU.scan_id = nil
        end
        DU.view = "select"
      end
    end

  elseif cur_sec == SEC_CLEANUP then
    if     b == Input.UP   then CL.sel = math.max(1, CL.sel - 1)
    elseif b == Input.DOWN then CL.sel = math.min(#CL.items, CL.sel + 1)
    elseif b == Input.A    then
      local item = CL.items[CL.sel]
      if item then
        Modal.show("Clean " .. item.label,
          "Delete everything under " .. item.path .. "?",
          { accept_label = "CLEAN", cancel_label = "CANCEL",
            on_accept = function() cl_do(item) end })
      end
    elseif b == Input.B or b == Input.SELECT then State.back() end
  end
end

function S.hat(dir)
  if Modal.is_open() then return end
  if dir == "up" then S.pad(Input.UP)
  elseif dir == "down" then S.pad(Input.DOWN) end
end

function S.key(k)
  if Modal.is_open() then
    if k == "return" then Modal.accept()
    elseif k == "escape" then Modal.cancel() end
    return
  end
  if     k == "q" then sec_switch(-1); return end
  if     k == "e" then sec_switch( 1); return end
  if     k == "up"   then S.pad(Input.UP)
  elseif k == "down" then S.pad(Input.DOWN)
  elseif k == "return" or k == "space" then S.pad(Input.A)
  elseif k == "escape" or k == "backspace" then S.pad(Input.B) end
end

-- ============================================================
--  Rail
-- ============================================================
local function draw_rail()
  local x, y = PAD, Frame.TOP_H + 8
  local w, h = RAIL_W, H - Frame.BOTTOM_H - y - 8

  col({0.020, 0.024, 0.026}, 0.95)
  love.graphics.rectangle("fill", x, y, w, h, 3, 3)
  col({0.55, 0.95, 1.0}, 0.30)
  love.graphics.setLineWidth(1)
  love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, 3, 3)

  col({0.55, 0.95, 1.0}, 0.90)
  love.graphics.setFont(A.font(A.FONT_MONO, 9))
  love.graphics.print("SECTIONS", x + 10, y + 8)
  col({0.55, 0.95, 1.0}, 0.30)
  love.graphics.rectangle("fill", x + 10, y + 22, w - 20, 1)

  local slot_h = 46
  local start_y = y + 34
  for i, sec in ipairs(SECS) do
    local cy = start_y + (i - 1) * (slot_h + 4)
    local focused = (i == cur_sec)
    local c = sec.accent

    if focused then
      col({c[1]*0.28, c[2]*0.28, c[3]*0.28}, 0.95)
      love.graphics.rectangle("fill", x + 6, cy, w - 12, slot_h, 3, 3)
      col(c, 0.90)
      love.graphics.setLineWidth(1.6)
      love.graphics.rectangle("line", x + 6.5, cy + 0.5, w - 13, slot_h - 1, 3, 3)
      love.graphics.setLineWidth(1)
      col(c, 1)
      love.graphics.rectangle("fill", x + 6, cy, 3, slot_h)
    else
      col({0.05, 0.06, 0.06}, 0.55)
      love.graphics.rectangle("fill", x + 6, cy, w - 12, slot_h, 3, 3)
      col(c, 0.35)
      love.graphics.rectangle("line", x + 6.5, cy + 0.5, w - 13, slot_h - 1, 3, 3)
    end

    love.graphics.setFont(A.font(A.FONT_MONO, 8))
    col(c, focused and 1 or 0.60)
    love.graphics.print(sec.tag, x + 14, cy + 6)

    love.graphics.setFont(A.font(A.FONT_BODY_BOLD, focused and 12 or 11))
    col(focused and {1,1,1} or {0.75,0.80,0.82}, 1)
    love.graphics.print(sec.name, x + 14, cy + 24)
  end
end

local function draw_panel()
  local sec = SECS[cur_sec]
  local accent = sec.accent

  local x = PAD + RAIL_W + 8
  local y = Frame.TOP_H + 8
  local w = W - PAD - x
  local h = H - Frame.BOTTOM_H - y - 8

  col({0.020, 0.024, 0.026}, 0.95)
  love.graphics.rectangle("fill", x, y, w, h, 3, 3)
  col(accent, 0.55)
  love.graphics.setLineWidth(1.4)
  love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, 3, 3)
  love.graphics.setLineWidth(1)
  D.corner_ticks(x + 8, y + 8, w - 16, h - 16, 10, accent, 0.85)

  love.graphics.setFont(A.font(A.FONT_TITLE, 16))
  col(accent, 1)
  love.graphics.print(sec.name, x + 18, y + 12)

  love.graphics.setFont(A.font(A.FONT_MONO, 9))
  col(accent, 0.75)
  love.graphics.print(sec.tag, x + 18, y + 34)

  local pulse = 0.5 + 0.5 * math.sin(love.timer.getTime() * 3)
  col(accent, 0.25 + 0.35 * pulse)
  love.graphics.circle("fill", x + w - 22, y + 22, 7)
  col(accent, 0.95)
  love.graphics.circle("fill", x + w - 22, y + 22, 3)

  col(accent, 0.30)
  love.graphics.rectangle("fill", x + 14, y + 52, w - 28, 1)

  if cur_sec == SEC_VOLUMES then
    draw_volumes(accent)
  elseif cur_sec == SEC_ANALYZE then
    if AN.view == "select" then draw_select_root(available_roots(), AN.target)
    elseif AN.view == "scanning" then draw_spinner("ANALYZING", SEC_ANALYZE)
    elseif AN.view == "results" then draw_analyze_results(accent) end
  elseif cur_sec == SEC_DUPLICATES then
    if DU.view == "select" then draw_select_root(available_roots(), DU.target)
    elseif DU.view == "scanning" then draw_spinner("HASHING", SEC_DUPLICATES)
    elseif DU.view == "groups" then draw_du_groups(accent)
    elseif DU.view == "detail" then draw_du_detail(accent) end
  elseif cur_sec == SEC_CLEANUP then
    draw_cleanup(accent)
  end
end

function S.draw()
  D.bg()
  local accent = SECS[cur_sec].accent

  col(accent, 0.05)
  for y = Frame.TOP_H, H - Frame.BOTTOM_H, 20 do
    for x = 0, W, 20 do
      love.graphics.rectangle("fill", x, y, 1, 1)
    end
  end

  D.corner_ticks(6, Frame.TOP_H + 4, W - 12,
    H - Frame.TOP_H - Frame.BOTTOM_H - 8, 18, {0.55, 0.95, 1.0}, 0.35)

  draw_rail()
  draw_panel()

  local hints
  if cur_sec == SEC_VOLUMES then
    hints = {
      { key="up",   label="Select" }, { key="a", label="Actions" },
      { key="start",label="Reload" }, { key="l1", label="Prev" },
      { key="r1",   label="Next" },   { key="b", label="Back" },
    }
  elseif cur_sec == SEC_ANALYZE then
    hints = {
      { key="up", label="Select" }, { key="a", label="Scan" },
      { key="l1", label="Prev" },   { key="r1", label="Next" },
      { key="b",  label="Back" },
    }
  elseif cur_sec == SEC_DUPLICATES then
    hints = {
      { key="up", label="Move" }, { key="a", label="Open" },
      { key="y",  label="Apply" },{ key="l1", label="Prev" },
      { key="r1", label="Next" }, { key="b", label="Back" },
    }
  else
    hints = {
      { key="up", label="Select" }, { key="a", label="Clean" },
      { key="l1", label="Prev" },   { key="r1", label="Next" },
      { key="b",  label="Back" },
    }
  end

  Frame.draw_top("FGD", "storage")
  Frame.draw_bottom(hints)
  Modal.draw()
  D.scanlines(W, H, 0.06)
  D.vignette(W, H, 0.55)
end

return S
