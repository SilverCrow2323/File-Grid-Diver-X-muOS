-- ui/status_overlay.lua -- M / guide overlay.
-- Shows downloads, undo stack, and general system info.
local A     = require("core.assets")
local State = require("core.state")
local D     = require("ui.draw")

local M = {
  open_flag = false,
  t = 0,
  phase = 0,
  scanning = 0,
}

local function col(c, a) love.graphics.setColor(c[1], c[2], c[3], a or 1) end

function M.toggle()
  M.open_flag = not M.open_flag
  M.t = 0
end
function M.open()  M.open_flag = true;  M.t = 0 end
function M.close() M.open_flag = false; M.t = 0 end
function M.is_open() return M.open_flag end

function M.update(dt)
  M.t = M.t + dt
  M.scanning = (M.scanning + dt * 0.6) % 1
  local target = M.open_flag and 1 or 0
  local speed  = 6.5
  if M.phase < target then
    M.phase = math.min(target, M.phase + dt * speed)
  elseif M.phase > target then
    M.phase = math.max(target, M.phase - dt * speed)
  end
end

local function human(n)
  if not n or n <= 0 then return "0 B" end
  local u = {"B","KB","MB","GB","TB"}
  local i = 1
  while n >= 1024 and i < #u do n = n / 1024; i = i + 1 end
  if i == 1 then return string.format("%d %s", n, u[i]) end
  return string.format("%.1f %s", n, u[i])
end

local function read_uptime()
  local f = io.open("/proc/uptime", "r")
  if not f then return "?" end
  local s = f:read("*l") or "0"; f:close()
  local up = math.floor(tonumber(s:match("^(%d+)")) or 0)
  return string.format("%dd %02dh %02dm",
    math.floor(up / 86400),
    math.floor((up % 86400) / 3600),
    math.floor((up % 3600) / 60))
end

local function read_mem()
  local f = io.open("/proc/meminfo", "r")
  if not f then return nil end
  local total, avail = 0, 0
  for line in f:lines() do
    local k, v = line:match("^(%w+):%s+(%d+)")
    if k == "MemTotal" then total = tonumber(v) or 0
    elseif k == "MemAvailable" then avail = tonumber(v) or 0 end
  end
  f:close()
  if total == 0 then return nil end
  return (1 - avail / total) * 100, total * 1024, (total - avail) * 1024
end

local function read_battery()
  for _, p in ipairs({
    "/sys/class/power_supply/battery/capacity",
    "/sys/class/power_supply/BAT0/capacity",
  }) do
    local f = io.open(p, "r")
    if f then
      local v = tonumber(f:read("*l") or ""); f:close()
      if v then return v end
    end
  end
  return nil
end

local function ease(p) return 1 - (1 - p) ^ 3 end

function M.draw()
  if M.phase <= 0.01 then return end

  local W, H = love.graphics.getWidth(), love.graphics.getHeight()
  local th = State.theme
  local p = ease(M.phase)

  -- Backdrop
  love.graphics.setColor(0, 0, 0, 0.55 * p)
  love.graphics.rectangle("fill", 0, 0, W, H)

  -- Panel
  local panel_w = math.min(560, W - 40)
  local panel_h = math.min(400, H - 60)
  local px = (W - panel_w) / 2
  local py = (H - panel_h) / 2 + (1 - p) * 30

  love.graphics.setColor(0.025, 0.020, 0.016, 0.97 * p)
  love.graphics.rectangle("fill", px, py, panel_w, panel_h, 4, 4)

  local acc = th.cyan_hi or {0.48, 0.80, 0.90}
  col(acc, 0.9 * p)
  love.graphics.setLineWidth(1.6)
  love.graphics.rectangle("line", px + 0.5, py + 0.5, panel_w - 1, panel_h - 1, 4, 4)
  love.graphics.setLineWidth(1)
  D.corner_ticks(px + 8, py + 8, panel_w - 16, panel_h - 16, 14, acc, 0.9 * p)

  -- Title
  col(acc, 1 * p)
  love.graphics.setFont(A.font(A.FONT_TITLE, 18))
  love.graphics.print("SYSTEM STATUS", px + 22, py + 16)

  -- Animated scanline
  local scan_y = py + 40 + (M.scanning * (panel_h - 50))
  col(acc, 0.15 * p)
  love.graphics.rectangle("fill", px + 14, scan_y, panel_w - 28, 2)

  col(acc, 0.4 * p)
  love.graphics.rectangle("fill", px + 14, py + 44, panel_w - 28, 1)

  local x0 = px + 24
  local y = py + 60
  local w = panel_w - 48

  -- DOWNLOADS
  col(acc, 1 * p)
  love.graphics.setFont(A.font(A.FONT_BODY_BOLD, 12))
  love.graphics.print("DOWNLOADS", x0, y)
  y = y + 18

  local ok, DL = pcall(require, "services.downloader")
  local jobs = {}
  if ok then jobs = DL.all() end

  -- Also scan data/downloads for plugin downloads
  do
    local ph = io.popen("ls -1 data/downloads/*.progress 2>/dev/null")
    if ph then
      for line in ph:lines() do
        local id = line:match("([^/]+)%.progress$")
        if id then
          local pf = io.open(line, "r")
          if pf then
            local content = pf:read("*l") or ""
            pf:close()
            local cur, tot = content:match("(%d+)|(%d+)")
            cur = tonumber(cur) or 0
            tot = tonumber(tot) or 1
            local pct = math.min(1, cur / math.max(1, tot))

            love.graphics.setFont(A.font(A.FONT_BODY_BOLD, 10))
            col({0.85, 0.75, 1.0}, p)
            love.graphics.print("[plugin] " .. id, x0 + 8, y)

            local bw, bh = w - 16, 6
            local by = y + 13
            col({0.06, 0.06, 0.10}, p)
            love.graphics.rectangle("fill", x0 + 8, by, bw, bh, 2, 2)
            col({0.70, 0.55, 0.92}, p)
            love.graphics.rectangle("fill", x0 + 8, by, bw * pct, bh, 2, 2)

            love.graphics.setFont(A.font(A.FONT_MONO, 9))
            col(th.text_dim, 0.85 * p)
            love.graphics.print(string.format("%.1f / %.1f MB  (%.0f%%)",
              cur / 1048576, tot / 1048576, pct * 100), x0 + 8, by + 9)
            y = y + 34
          end
        end
      end
      ph:close()
    end
  end

  if #jobs == 0 then
    col(th.text_dim, 0.9 * p)
    love.graphics.setFont(A.font(A.FONT_MONO, 10))
    love.graphics.print("no active downloads", x0 + 8, y)
    y = y + 18
  else
    for i, j in ipairs(jobs) do
      if i > 3 then break end
      love.graphics.setFont(A.font(A.FONT_BODY_BOLD, 10))
      col({0.85, 1.0, 0.85}, p)
      love.graphics.print((j.label or j.out or "?"):sub(1, 44), x0 + 8, y)

      local bw, bh = w - 16, 6
      local by = y + 13
      col({0.06, 0.10, 0.06}, p)
      love.graphics.rectangle("fill", x0 + 8, by, bw, bh, 2, 2)
      local cc = j.done
        and (j.rc == 0 and {0.40, 0.95, 0.45} or {0.95, 0.35, 0.30})
        or  {0.40, 0.85, 0.45}
      col(cc, p)
      local pct = j.pct > 0 and j.pct or (j.done and 1 or 0)
      love.graphics.rectangle("fill", x0 + 8, by, bw * pct, bh, 2, 2)

      love.graphics.setFont(A.font(A.FONT_MONO, 9))
      col(th.text_dim, 0.85 * p)
      local status
      if j.done then
        status = j.rc == 0 and "COMPLETE" or ("FAILED rc=" .. tostring(j.rc))
      else
        status = string.format("%s / %s  %s/s",
          human(j.bytes), human(j.total), human(j.speed))
      end
      love.graphics.print(status, x0 + 8, by + 9)
      y = y + 34
    end
  end

  y = y + 6

  -- UNDO STACK
  col(acc, 1 * p)
  love.graphics.setFont(A.font(A.FONT_BODY_BOLD, 12))
  love.graphics.print("UNDO STACK", x0, y)
  y = y + 18

  local ok2, Ops = pcall(require, "services.operations")
  if ok2 then
    local n = Ops.size and Ops.size() or 0
    love.graphics.setFont(A.font(A.FONT_BODY_BOLD, 11))
    col({0.92, 0.85, 0.70}, p)
    love.graphics.print(string.format("%d operation(s) in stack", n), x0 + 8, y)
    y = y + 14
    local peek = Ops.peek and Ops.peek() or nil
    if peek then
      love.graphics.setFont(A.font(A.FONT_MONO, 10))
      col(th.text_dim, 0.85 * p)
      love.graphics.print("last: " .. (peek.label or peek.kind or "?"), x0 + 8, y)
    end
    y = y + 18
  end

  y = y + 6

  -- SYSTEM
  col(acc, 1 * p)
  love.graphics.setFont(A.font(A.FONT_BODY_BOLD, 12))
  love.graphics.print("SYSTEM", x0, y)
  y = y + 18

  love.graphics.setFont(A.font(A.FONT_MONO, 10))
  local function row(k, v)
    col(th.text_dim, 0.85 * p)
    love.graphics.print(k, x0 + 8, y)
    col(th.text_bright, p)
    love.graphics.print(v, x0 + 120, y)
    y = y + 14
  end

  row("UPTIME", read_uptime())
  row("FPS",    string.format("%.0f", love.timer.getFPS()))

  local mem_pct, mem_total, mem_used = read_mem()
  if mem_pct then
    row("RAM", string.format("%.0f%%  (%s / %s)",
      mem_pct, human(mem_used), human(mem_total)))
  end
  local bat = read_battery()
  if bat then row("BATTERY", string.format("%d%%", bat)) end

  col(acc, 0.7 * p)
  love.graphics.setFont(A.font(A.FONT_MONO, 9))
  love.graphics.printf("M / GUIDE  -  close",
    px, py + panel_h - 22, panel_w, "center")
end

return M
