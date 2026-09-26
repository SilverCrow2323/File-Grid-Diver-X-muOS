-- ui/properties.lua -- file properties overlay.
local A     = require("core.assets")
local D     = require("ui.draw")

local M = { item = nil, t = 0, chmod_mode = false }

function M.show(path, entry)
  M.item = { path = path, entry = entry or {}, info = {} }
  M.t = 0
  M.chmod_mode = false
  -- gather extra info
  local sh = require("core.sh")
  local out = sh.read("stat -c '%A|%U|%G|%s|%Y|%n' " ..
    sh.shq(path) .. " 2>/dev/null")
  if out then
    local perm, owner, group, size, mtime = out:match("^(.-)|(.-)|(.-)|(%d+)|(%d+)")
    M.item.info.perm  = perm
    M.item.info.owner = owner
    M.item.info.group = group
    M.item.info.size  = tonumber(size)
    M.item.info.mtime = tonumber(mtime)
  end
  -- link target if symlink
  M.item.info.target = sh.read("readlink " .. sh.shq(path) .. " 2>/dev/null")
  M.item.info.target = M.item.info.target and M.item.info.target:gsub("\n", "") or nil
end

function M.close() M.item = nil end
function M.is_open() return M.item ~= nil end

function M.update(dt)
  if M.item then M.t = M.t + dt end
end

local function human(n)
  if not n or n <= 0 then return "0 B" end
  local u = { "B", "KB", "MB", "GB", "TB" }
  local i = 1
  while n >= 1024 and i < #u do n = n / 1024; i = i + 1 end
  if i == 1 then return string.format("%d %s", n, u[i]) end
  return string.format("%.1f %s", n, u[i])
end

local function row(x, y, key, val, th)
  love.graphics.setFont(A.font(A.FONT_MONO, 13))
  love.graphics.setColor(th.text_dim)
  love.graphics.print(key, x, y)
  love.graphics.setFont(A.font(A.FONT_BODY, 14))
  love.graphics.setColor(th.text_bright)
  love.graphics.print(val or "-", x + 100, y)
end

function M.draw()
  if not M.item then return end
  local ok, State = pcall(require, "core.state")
  local th = ok and State.theme or {
    text = {0.85, 0.82, 0.76}, text_dim = {0.44, 0.42, 0.38},
    panel = {0.05, 0.05, 0.04}, amber = {0.94, 0.66, 0.35},
    amber_hi = {0.94, 0.66, 0.35}, amber_lo = {0.35, 0.22, 0.10},
  }
  local W = love.graphics.getWidth()
  local H = love.graphics.getHeight()
  local ease = math.min(1, M.t / 0.14)
  ease = 1 - (1 - ease) ^ 3

  love.graphics.setColor(0, 0, 0, 0.78 * ease)
  love.graphics.rectangle("fill", 0, 0, W, H)

  local w, h = 460, 300
  local x = math.floor((W - w) / 2)
  local y = math.floor((H - h) / 2) + (1 - ease) * 20

  love.graphics.setColor(th.panel)
  love.graphics.rectangle("fill", x, y, w, h)
  love.graphics.setColor(th.amber_lo[1], th.amber_lo[2], th.amber_lo[3], 0.9)
  love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1)
  D.corner_ticks(x + 6, y + 6, w - 12, h - 12, 14, th.amber_hi, 0.95)

  if ease < 0.5 then return end

  love.graphics.setColor(th.amber_hi)
  love.graphics.setFont(A.font(A.FONT_BODY_BOLD, 14))
  local name = M.item.path:match("([^/]+)$") or M.item.path
  love.graphics.print("> PROPERTIES", x + 20, y + 16)

  love.graphics.setColor(th.text_dim)
  love.graphics.setFont(A.font(A.FONT_BODY, 14))
  love.graphics.print(name, x + 20, y + 36)
  love.graphics.setColor(th.amber_lo[1], th.amber_lo[2], th.amber_lo[3], 0.4)
  love.graphics.line(x + 20, y + 54, x + w - 20, y + 54)

  local i = M.item.info
  local ry = y + 68
  local step = 20
  row(x + 20, ry, "PATH",  M.item.path, th); ry = ry + step
  row(x + 20, ry, "TYPE",  M.item.entry.is_dir and "directory" or "file", th); ry = ry + step
  row(x + 20, ry, "SIZE",  human(i.size or M.item.entry.size or 0), th); ry = ry + step
  row(x + 20, ry, "PERM",  i.perm or M.item.entry.perms or "-", th); ry = ry + step
  row(x + 20, ry, "OWNER", (i.owner or "?") .. ":" .. (i.group or "?"), th); ry = ry + step
  local mt = i.mtime or M.item.entry.mtime
  row(x + 20, ry, "MODIFIED",
    mt and os.date("%Y-%m-%d %H:%M:%S", mt) or "-", th); ry = ry + step
  if i.target and i.target ~= "" then
    row(x + 20, ry, "SYMLINK TO", i.target, th); ry = ry + step
  end

  -- chmod quick row
  love.graphics.setColor(th.amber_lo[1], th.amber_lo[2], th.amber_lo[3], 0.3)
  love.graphics.line(x + 20, y + h - 60, x + w - 20, y + h - 60)

  love.graphics.setColor(th.amber_hi)
  love.graphics.setFont(A.font(A.FONT_BODY_BOLD, 13))
  love.graphics.print("CHMOD:", x + 20, y + h - 48)

  local perms = i.perm or M.item.entry.perms or "---------"
  -- perms format: -rwxr-xr-x
  local flags = {
    { k = "u+r", on = perms:sub(2, 2) == "r" },
    { k = "u+w", on = perms:sub(3, 3) == "w" },
    { k = "u+x", on = perms:sub(4, 4) == "x" },
    { k = "g+r", on = perms:sub(5, 5) == "r" },
    { k = "g+w", on = perms:sub(6, 6) == "w" },
    { k = "g+x", on = perms:sub(7, 7) == "x" },
    { k = "o+r", on = perms:sub(8, 8) == "r" },
    { k = "o+w", on = perms:sub(9, 9) == "w" },
    { k = "o+x", on = perms:sub(10,10) == "x" },
  }
  love.graphics.setFont(A.font(A.FONT_MONO, 12))
  local fx = x + 20
  for _, f in ipairs(flags) do
    love.graphics.setColor(f.on and th.green or th.text_dark)
    love.graphics.rectangle("line", fx, y + h - 32, 8, 8)
    if f.on then love.graphics.rectangle("fill", fx + 2, y + h - 30, 4, 4) end
    love.graphics.setColor(th.text)
    love.graphics.print(f.k, fx + 12, y + h - 34)
    fx = fx + 50
  end

  love.graphics.setColor(th.text_dim)
  love.graphics.setFont(A.font(A.FONT_BODY_BOLD, 13))
  love.graphics.print("[B] close   [X] chmod +x   [Y] chmod -x   [A] checksum",
    x + 20, y + h - 18)
end

-- Compute checksum and show it inside the overlay
function M.show_checksum(algo)
  if not M.item then return end
  local C = require("services.checksum")
  local h, err = C.compute(M.item.path, algo or "md5")
  if h then
    M.item.info.checksum = (algo or "md5"):upper() .. ": " .. h
  else
    M.item.info.checksum = "error: " .. tostring(err)
  end
end

function M.chmod(mode)
  if not M.item then return false end
  local sh = require("core.sh")
  return sh.exec("chmod " .. mode .. " " .. sh.shq(M.item.path)) == 0
end

return M
