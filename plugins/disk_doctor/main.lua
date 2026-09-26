-- plugins/disk_doctor/main.lua -- Disk Doctor.
-- Guided 4-step wizard: OVERVIEW -> SCAN -> CLEAN -> DONE.
local A     = require("core.assets")
local State = require("core.state")
local Input = require("core.input_map")
local Frame = require("ui.frame")
local D     = require("ui.draw")
local sh    = require("core.sh")
local Notify= require("ui.notify")
local Modal = require("ui.modal")
local Trash = require("services.trash")

local S = {}
local W, H = 640, 480

local ACC    = {0.30, 0.85, 0.95}
local ACC_HI = {0.60, 0.95, 1.00}
local ACC_LO = {0.05, 0.30, 0.40}
local RED    = {0.95, 0.32, 0.25}
local GRN    = {0.35, 0.95, 0.45}
local AMB    = {0.95, 0.70, 0.30}

local STEPS = { "OVERVIEW", "SCAN", "CLEAN", "DONE" }
local step       = 1
local t          = 0

local overview = { path = "/mnt/mmc", total = 0, used = 0, free = 0, pct = 0 }
local scan_phase  = 0
local scan_job    = nil
local scan_results = {}
local scan_bytes   = 0
local freed_bytes  = 0
local before_free  = 0

local function col(c, a) love.graphics.setColor(c[1], c[2], c[3], a or 1) end
local function human(n)
  if not n or n <= 0 then return "0 B" end
  local u = {"B","KB","MB","GB","TB"}; local i = 1
  while n >= 1024 and i < #u do n = n / 1024; i = i + 1 end
  if i == 1 then return string.format("%d %s", n, u[i]) end
  return string.format("%.1f %s", n, u[i])
end

local function detect_main_volume()
  for _, p in ipairs({ "/mnt/mmc", "/mnt/sdcard", "/" }) do
    if sh.is_dir(p) then return p end
  end
  return "/"
end

local function read_df(path)
  local r = sh.read("df -kP " .. sh.shq(path) .. " 2>/dev/null")
  if not r then return nil end
  local line = r:match("[^\n]+\n([^\n]+)")
  if not line then return nil end
  local total, used, free = line:match("%s(%d+)%s+(%d+)%s+(%d+)")
  if not total then return nil end
  total, used, free = tonumber(total)*1024, tonumber(used)*1024, tonumber(free)*1024
  local pct = (total > 0) and (used / total) or 0
  return total, used, free, pct
end

local SCAN_TARGETS = {
  { key="trash",     label="Trash",            path="data/trash",        hint="files moved to the app trash" },
  { key="logs",      label="Application logs", path="data/logs",         hint="per-session log files" },
  { key="logs_desk", label="Desktop logs",     path=".desktopbase/logs", hint="development session logs" },
  { key="downloads", label="Downloads",        path="data/downloads",    hint="files fetched by the downloader" },
  { key="snapshots", label="Snapshots",        path="data/snapshots",    hint="diagnostic snapshots saved" },
  { key="tmp",       label="Temporary files",  path="/tmp",              hint="session working residue" },
}

local function start_scan()
  scan_phase = 1
  scan_results = {}
  scan_bytes = 0

  local id = tostring(os.time()) .. "_" .. tostring(math.random(1000, 9999))
  local script = "/tmp/fgd_dd_" .. id .. ".sh"
  local out    = "/tmp/fgd_dd_" .. id .. ".out"
  local done   = "/tmp/fgd_dd_" .. id .. ".done"

  local lines = {
    "set +e",
    "OUT=" .. sh.shq(out),
    "DONE=" .. sh.shq(done),
    ': > "$OUT"',
  }
  for _, tgt in ipairs(SCAN_TARGETS) do
    lines[#lines + 1] = "SZ=$(du -sk " .. sh.shq(tgt.path) ..
      " 2>/dev/null | cut -f1); [ -z \"$SZ\" ] && SZ=0"
    lines[#lines + 1] = 'echo "' .. tgt.key .. '|$SZ" >> "$OUT"'
  end
  lines[#lines + 1] = 'touch "$DONE"'

  local f = io.open(script, "w")
  if not f then scan_phase = 0; return end
  f:write("#!/bin/sh\n" .. table.concat(lines, "\n") .. "\n")
  f:close()
  os.execute("chmod +x " .. sh.shq(script))
  os.execute("setsid sh " .. sh.shq(script) .. " </dev/null >/dev/null 2>&1 &")

  scan_job = { id=id, script=script, out=out, done=done, t=0 }
end

local function poll_scan(dt)
  if scan_phase ~= 1 or not scan_job then return end
  scan_job.t = scan_job.t + dt
  if scan_job.t > 60 then
    os.execute("pkill -f " .. sh.shq(scan_job.script))
    scan_job = nil
    scan_phase = 2
    return
  end
  local df = io.open(scan_job.done, "r")
  if not df then return end
  df:close()

  local sizes = {}
  local f = io.open(scan_job.out, "r")
  if f then
    for line in f:lines() do
      local k, kb = line:match("^(%w+)|(%d+)$")
      if k and kb then sizes[k] = tonumber(kb) * 1024 end
    end
    f:close()
  end

  scan_results = {}
  for _, tgt in ipairs(SCAN_TARGETS) do
    local sz = sizes[tgt.key] or 0
    scan_results[#scan_results + 1] = {
      key = tgt.key, label = tgt.label, path = tgt.path,
      hint = tgt.hint, size = sz,
      selected = (sz > 0 and tgt.key ~= "snapshots" and tgt.key ~= "downloads"),
    }
    scan_bytes = scan_bytes + sz
  end

  os.remove(scan_job.script)
  os.remove(scan_job.out)
  os.remove(scan_job.done)
  scan_job = nil
  scan_phase = 2
end

local function count_selected()
  local n, bytes = 0, 0
  for _, r in ipairs(scan_results) do
    if r.selected then n = n + 1; bytes = bytes + r.size end
  end
  return n, bytes
end

local function execute_cleanup()
  freed_bytes = 0
  for _, r in ipairs(scan_results) do
    if r.selected and r.size > 0 then
      if r.key == "trash" then
        Trash.purge_all()
      elseif r.key == "tmp" then
        os.execute("rm -rf /tmp/fgd_* /tmp/str_* /tmp/dup_* /tmp/dd_* 2>/dev/null")
      elseif r.key == "snapshots" then
        os.execute("rm -f data/snapshots/*.txt data/snapshots/*.log 2>/dev/null")
      else
        os.execute("rm -rf " .. sh.shq(r.path) .. "/* 2>/dev/null")
      end
      freed_bytes = freed_bytes + r.size
    end
  end
  local _, _, free2 = read_df(overview.path)
  if free2 then
    freed_bytes = math.max(freed_bytes, free2 - before_free)
  end
end

local function goto_step(n)
  step = math.max(1, math.min(#STEPS, n))
  if step == 2 and scan_phase == 0 then
    start_scan()
  end
end

function S.enter()
  step = 1
  t = 0
  freed_bytes = 0
  scan_phase = 0
  scan_job = nil
  scan_results = {}
  scan_bytes = 0
  overview.path = detect_main_volume()
  local total, used, free, pct = read_df(overview.path)
  overview.total = total or 0
  overview.used  = used  or 0
  overview.free  = free  or 0
  overview.pct   = pct   or 0
  before_free = overview.free
end

function S.leave()
  if scan_job then
    os.execute("pkill -f " .. sh.shq(scan_job.script) .. " 2>/dev/null")
    os.remove(scan_job.script); os.remove(scan_job.out); os.remove(scan_job.done)
    scan_job = nil
  end
end

function S.update(dt)
  t = t + dt
  poll_scan(dt)
end

local clean_sel = 1

local function clean_move(d)
  if #scan_results == 0 then return end
  clean_sel = clean_sel + d
  local total = #scan_results + 1
  if clean_sel < 1 then clean_sel = 1 end
  if clean_sel > total then clean_sel = total end
end

local function ask_clean()
  local n, bytes = count_selected()
  if n == 0 then
    Notify.show("warning", "nothing selected")
    return
  end
  Modal.show("Confirm cleanup",
    string.format("About %s will be freed.\nProceed?", human(bytes)),
    { accept_label = "CLEAN",
      on_accept = function()
        execute_cleanup()
        goto_step(4)
      end })
end

function S.pad(b)
  if Modal.is_open() then
    if b == Input.A then Modal.accept()
    elseif b == Input.B then Modal.cancel() end
    return
  end

  if b == Input.B or b == Input.SELECT then
    if step == 1 then State.back()
    else goto_step(step - 1) end
    return
  end

  if step == 1 then
    if b == Input.A then goto_step(2) end
  elseif step == 2 then
    if b == Input.A and scan_phase == 2 then goto_step(3) end
  elseif step == 3 then
    if b == Input.UP then clean_move(-1)
    elseif b == Input.DOWN then clean_move(1)
    elseif b == Input.Y then ask_clean()
    elseif b == Input.A then
      if clean_sel <= #scan_results then
        local r = scan_results[clean_sel]
        r.selected = not r.selected
      else
        ask_clean()
      end
    end
  elseif step == 4 then
    if b == Input.A or b == Input.B then goto_step(1) end
  end
end

function S.hat(d)
  if step == 3 then
    if d == "up" then clean_move(-1)
    elseif d == "down" then clean_move(1) end
  end
end

function S.key(k)
  if Modal.is_open() then
    if k == "return" then Modal.accept()
    elseif k == "escape" then Modal.cancel() end
    return
  end
  if k == "escape" or k == "backspace" then S.pad(Input.B)
  elseif k == "y" then S.pad(Input.Y)
  elseif k == "return" or k == "space" then S.pad(Input.A)
  elseif k == "up" then S.pad(Input.UP)
  elseif k == "down" then S.pad(Input.DOWN) end
end

local function draw_header()
  local margin = 20
  local gap = 6
  local total_w = W - margin * 2
  local pw = (total_w - gap * (#STEPS - 1)) / #STEPS
  local py = Frame.TOP_H + 8
  local ph = 22

  for i, name in ipairs(STEPS) do
    local px = margin + (i - 1) * (pw + gap)
    local active = (i == step)
    local done   = (i < step)

    if active then
      col(ACC, 0.20)
      love.graphics.rectangle("fill", px, py, pw, ph, 3, 3)
      col(ACC_HI, 0.95)
      love.graphics.setLineWidth(1.6)
      love.graphics.rectangle("line", px + 0.5, py + 0.5, pw - 1, ph - 1, 3, 3)
      love.graphics.setLineWidth(1)
    elseif done then
      col(GRN, 0.12)
      love.graphics.rectangle("fill", px, py, pw, ph, 3, 3)
      col(GRN, 0.70)
      love.graphics.rectangle("line", px + 0.5, py + 0.5, pw - 1, ph - 1, 3, 3)
    else
      col({0.06, 0.08, 0.10}, 0.7)
      love.graphics.rectangle("fill", px, py, pw, ph, 3, 3)
      col(ACC_LO, 0.55)
      love.graphics.rectangle("line", px + 0.5, py + 0.5, pw - 1, ph - 1, 3, 3)
    end

    love.graphics.setFont(A.font(A.FONT_MONO, 10))
    if done then col(GRN, 0.95)
    elseif active then col(ACC_HI, 1)
    else col(ACC_LO, 0.7) end
    love.graphics.printf(string.format("%d. %s", i, name), px, py + 5, pw, "center")
  end
end

local function draw_disk_bar(x, y, w, label)
  local total, used, free, pct = overview.total, overview.used, overview.free, overview.pct

  love.graphics.setFont(A.font(A.FONT_BODY_BOLD, 12))
  col(ACC_HI, 1)
  love.graphics.print(label or "MAIN DISK", x, y)
  love.graphics.setFont(A.font(A.FONT_MONO, 10))
  col(ACC_LO, 0.9)
  love.graphics.printf(overview.path, x, y, w, "right")
  y = y + 18

  local bh = 22
  col({0.05, 0.08, 0.10}, 1)
  love.graphics.rectangle("fill", x, y, w, bh, 3, 3)
  local cbar = pct > 0.9 and RED or (pct > 0.7 and AMB or GRN)
  col(cbar, 0.95)
  love.graphics.rectangle("fill", x + 1, y + 1, (w - 2) * pct, bh - 2, 2, 2)
  col(cbar, 0.5)
  love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, bh - 1, 3, 3)

  y = y + bh + 4
  love.graphics.setFont(A.font(A.FONT_MONO, 11))
  col(ACC_HI, 1)
  love.graphics.print(string.format("%s free", human(free)), x, y)
  col(ACC_LO, 0.9)
  love.graphics.printf(string.format("used %s / %s  (%.0f%%)",
    human(used), human(total), pct * 100), x, y, w, "right")
end

local function draw_step1()
  local x, y = 30, Frame.TOP_H + 50
  local w = W - 60

  love.graphics.setFont(A.font(A.FONT_TITLE, 22))
  col(ACC_HI, 1)
  love.graphics.print("DISK DOCTOR", x, y)
  love.graphics.setFont(A.font(A.FONT_BODY, 11))
  col({0.80, 0.90, 0.92}, 0.9)
  love.graphics.printf("A guided path to reclaim space, safely.",
    x, y + 28, w, "left")
  y = y + 60

  draw_disk_bar(x, y, w)
  y = y + 70

  local facts = {
    { "STATUS", overview.pct > 0.9 and "CRITICAL" or
                (overview.pct > 0.7 and "NEEDS CLEANUP" or "HEALTHY") },
    { "FREE", human(overview.free) },
    { "CAPACITY", human(overview.total) },
  }
  local fw = (w - 20) / 3
  for i, f in ipairs(facts) do
    local bx = x + (i - 1) * (fw + 10)
    col(ACC_LO, 0.25)
    love.graphics.rectangle("fill", bx, y, fw, 52, 3, 3)
    col(ACC, 0.70)
    love.graphics.rectangle("line", bx + 0.5, y + 0.5, fw - 1, 51, 3, 3)
    love.graphics.setFont(A.font(A.FONT_MONO, 9))
    col(ACC_LO, 0.9)
    love.graphics.print(f[1], bx + 10, y + 8)
    love.graphics.setFont(A.font(A.FONT_BODY_BOLD, 14))
    col(ACC_HI, 1)
    love.graphics.print(f[2], bx + 10, y + 24)
  end
  y = y + 76

  love.graphics.setFont(A.font(A.FONT_BODY_BOLD, 12))
  col(ACC_HI, 1)
  love.graphics.print("Press A to begin the scan", x, y)
  love.graphics.setFont(A.font(A.FONT_BODY, 10))
  col({0.75, 0.82, 0.85}, 0.9)
  love.graphics.print(
    "We will measure trash, logs, downloads, temporary and snapshot folders.",
    x, y + 18)
end

local function draw_step2()
  local x, y = 30, Frame.TOP_H + 50
  local w = W - 60

  love.graphics.setFont(A.font(A.FONT_TITLE, 20))
  col(ACC_HI, 1)
  love.graphics.print("SCANNING", x, y)
  y = y + 32

  if scan_phase == 1 then
    local p = (math.sin(t * 3) + 1) * 0.5
    col(ACC, 0.2 + 0.3 * p)
    love.graphics.rectangle("fill", x, y, w, 8, 3, 3)
    col(ACC_HI, 0.9)
    love.graphics.rectangle("fill", x, y, w * (0.1 + 0.8 * p), 8, 3, 3)
    love.graphics.setFont(A.font(A.FONT_MONO, 11))
    col(ACC_HI, 0.95)
    love.graphics.printf("Measuring...", x, y + 20, w, "center")
    y = y + 50
    love.graphics.setFont(A.font(A.FONT_BODY, 10))
    col({0.7, 0.8, 0.85}, 0.9)
    love.graphics.printf(
      "Trash, logs, downloads, temporary files, snapshots.", x, y, w, "center")
  elseif scan_phase == 2 then
    local max_sz = 1
    for _, r in ipairs(scan_results) do
      if r.size > max_sz then max_sz = r.size end
    end
    local row_h = 30
    for i, r in ipairs(scan_results) do
      local ry = y + (i - 1) * row_h
      love.graphics.setFont(A.font(A.FONT_BODY_BOLD, 11))
      col(ACC_HI, 1)
      love.graphics.print(r.label, x, ry)
      love.graphics.setFont(A.font(A.FONT_MONO, 10))
      col(ACC_LO, 0.85)
      love.graphics.print(r.hint, x, ry + 14)

      local bx = x + 220
      local bw = w - 220 - 90
      col({0.05, 0.08, 0.10}, 1)
      love.graphics.rectangle("fill", bx, ry + 4, bw, 12, 2, 2)
      local pct = r.size / max_sz
      col(ACC, 0.9)
      love.graphics.rectangle("fill", bx + 1, ry + 5, (bw - 2) * pct, 10, 1, 1)

      love.graphics.setFont(A.font(A.FONT_MONO, 11))
      col(ACC_HI, 1)
      love.graphics.printf(human(r.size), x, ry, w, "right")
    end
    y = y + #scan_results * row_h + 16
    love.graphics.setFont(A.font(A.FONT_BODY_BOLD, 12))
    col(ACC_HI, 1)
    love.graphics.printf(string.format("Total found: %s", human(scan_bytes)),
      x, y, w, "center")
    y = y + 22
    col(GRN, 1)
    love.graphics.printf("Press A to continue to cleanup", x, y, w, "center")
  end
end

local function draw_step3()
  local x, y = 30, Frame.TOP_H + 50
  local w = W - 60

  love.graphics.setFont(A.font(A.FONT_TITLE, 20))
  col(ACC_HI, 1)
  love.graphics.print("SELECT WHAT TO CLEAN", x, y)
  love.graphics.setFont(A.font(A.FONT_BODY, 10))
  col({0.75, 0.85, 0.90}, 0.9)
  love.graphics.printf("A toggles. Y executes.", x, y + 24, w, "left")
  y = y + 48

  local row_h = 40
  for i, r in ipairs(scan_results) do
    local ry = y + (i - 1) * (row_h + 4)
    local focused = (i == clean_sel)
    local sel = r.selected

    if focused then
      col(ACC, 0.15)
      love.graphics.rectangle("fill", x, ry, w, row_h, 3, 3)
      col(ACC_HI, 0.9)
      love.graphics.setLineWidth(1.6)
      love.graphics.rectangle("line", x + 0.5, ry + 0.5, w - 1, row_h - 1, 3, 3)
      love.graphics.setLineWidth(1)
    else
      col(ACC_LO, 0.18)
      love.graphics.rectangle("fill", x, ry, w, row_h, 3, 3)
      col(ACC_LO, 0.55)
      love.graphics.rectangle("line", x + 0.5, ry + 0.5, w - 1, row_h - 1, 3, 3)
    end

    local cbx = x + 16
    local cby = ry + row_h / 2
    if sel then
      col(GRN, 1)
      love.graphics.rectangle("fill", cbx - 8, cby - 8, 16, 16, 2, 2)
      col({0.02, 0.05, 0.02}, 1)
      love.graphics.setLineWidth(2.4)
      love.graphics.line(cbx - 4, cby, cbx - 1, cby + 3, cbx + 5, cby - 4)
      love.graphics.setLineWidth(1)
    else
      col(ACC, 0.55)
      love.graphics.rectangle("line", cbx - 8, cby - 8, 16, 16, 2, 2)
    end

    love.graphics.setFont(A.font(A.FONT_BODY_BOLD, 12))
    col(ACC_HI, 1)
    love.graphics.print(r.label, x + 36, ry + 6)
    love.graphics.setFont(A.font(A.FONT_MONO, 10))
    col({0.75, 0.85, 0.90}, 0.85)
    love.graphics.print(r.hint, x + 36, ry + 22)

    love.graphics.setFont(A.font(A.FONT_MONO, 12))
    col(sel and GRN or ACC_LO, 1)
    love.graphics.printf(human(r.size), x, ry + 12, w - 16, "right")
  end
  y = y + #scan_results * (row_h + 4) + 12

  local bx = x + w/2 - 110
  local bw = 220
  local bh = 30
  local focused = (clean_sel == #scan_results + 1)
  local _, sel_bytes = count_selected()
  local enabled = sel_bytes > 0

  if enabled then
    col(GRN, focused and 0.30 or 0.15)
    love.graphics.rectangle("fill", bx, y, bw, bh, 4, 4)
    col(GRN, focused and 1 or 0.7)
    love.graphics.setLineWidth(focused and 2 or 1.4)
    love.graphics.rectangle("line", bx + 0.5, y + 0.5, bw - 1, bh - 1, 4, 4)
    love.graphics.setLineWidth(1)
    love.graphics.setFont(A.font(A.FONT_BODY_BOLD, 13))
    col({1, 1, 1}, 1)
    love.graphics.printf(string.format("RUN CLEANUP (%s)", human(sel_bytes)),
      bx, y + 8, bw, "center")
  else
    col({0.10, 0.12, 0.14}, 0.85)
    love.graphics.rectangle("fill", bx, y, bw, bh, 4, 4)
    col(ACC_LO, 0.5)
    love.graphics.rectangle("line", bx + 0.5, y + 0.5, bw - 1, bh - 1, 4, 4)
    love.graphics.setFont(A.font(A.FONT_BODY_BOLD, 13))
    col(ACC_LO, 0.7)
    love.graphics.printf("SELECT SOMETHING", bx, y + 8, bw, "center")
  end
end

local function draw_step4()
  local x, y = 30, Frame.TOP_H + 70
  local w = W - 60

  local cx, cy = W/2, y + 40
  D.glow(cx, cy, 140, GRN, 0.7)
  col(GRN, 0.95)
  love.graphics.setLineWidth(6)
  love.graphics.line(cx - 30, cy, cx - 6, cy + 24, cx + 34, cy - 20)
  love.graphics.setLineWidth(1)

  y = y + 110
  love.graphics.setFont(A.font(A.FONT_TITLE, 26))
  col(GRN, 1)
  love.graphics.printf("CLEANUP COMPLETE", x, y, w, "center")
  y = y + 46

  love.graphics.setFont(A.font(A.FONT_BODY, 12))
  col({0.85, 0.92, 0.88}, 0.95)
  love.graphics.printf(string.format("You freed about %s", human(freed_bytes)),
    x, y, w, "center")
  y = y + 30

  local _, _, free2 = read_df(overview.path)
  if free2 then
    love.graphics.setFont(A.font(A.FONT_MONO, 11))
    col(ACC_HI, 0.95)
    love.graphics.printf(string.format("Before: %s free   -->   Now: %s free",
      human(before_free), human(free2)), x, y, w, "center")
  end

  y = y + 50
  love.graphics.setFont(A.font(A.FONT_BODY_BOLD, 12))
  col(ACC_HI, 1)
  love.graphics.printf("Press A to return to the overview", x, y, w, "center")
end

function S.draw()
  D.bg()

  col(ACC, 0.05)
  for y = Frame.TOP_H, H - Frame.BOTTOM_H, 16 do
    for x = 0, W, 16 do love.graphics.rectangle("fill", x, y, 1, 1) end
  end

  D.corner_ticks(6, Frame.TOP_H + 4, W - 12,
    H - Frame.TOP_H - Frame.BOTTOM_H - 8, 20, ACC, 0.5)

  draw_header()

  if step == 1 then draw_step1()
  elseif step == 2 then draw_step2()
  elseif step == 3 then draw_step3()
  elseif step == 4 then draw_step4() end

  local hints
  if step == 1 then
    hints = { {key="a", label="Start"}, {key="b", label="Back"} }
  elseif step == 2 then
    hints = { {key="a", label="Continue"}, {key="b", label="Back"} }
  elseif step == 3 then
    hints = { {key="up", label="Move"}, {key="a", label="Toggle"},
              {key="y", label="Run"}, {key="b", label="Back"} }
  else
    hints = { {key="a", label="Restart"}, {key="b", label="Back"} }
  end

  Frame.draw_top("FGD", "plugins")
  Frame.draw_bottom(hints)
  Modal.draw()
  D.scanlines(W, H, 0.06)
  D.vignette(W, H, 0.55)
end

return S
