-- screens/grid_helpers.lua - pure helpers for the file manager.
local sh = require("core.sh")

local H = {}

function H.is_hidden(name)
  if not name or name == "" then return false end
  if name == ".." or name == "." then return false end
  return name:sub(1, 1) == "."
end

function H.parent_of(path)
  if not path or path == "" or path == "/" then return "/" end
  path = path:gsub("/+$", "")
  if path == "" then return "/" end
  local p = path:match("^(.*)/[^/]+$")
  if not p or p == "" then return "/" end
  return p
end

function H.basename(p)
  return (p or ""):match("([^/]+)$") or p or ""
end

function H.short_date(mt)
  if not mt or mt == 0 then return "--" end
  return os.date("%m-%d %H:%M", mt)
end

function H.truncate(font, s, maxw)
  if not s then return "" end
  if font:getWidth(s) <= maxw then return s end
  local out = s
  while #out > 1 and font:getWidth(out .. ".") > maxw do
    out = out:sub(1, -2)
  end
  return out .. "."
end

function H.free_space_of(path)
  if not path then return nil end
  local out = sh.read("df -kP " .. sh.shq(path) .. " 2>/dev/null")
  if not out then return nil end
  local line = out:match("[^\n]+\n([^\n]+)")
  if not line then return nil end
  local total, used, free = line:match("%s(%d+)%s+(%d+)%s+(%d+)")
  if not total then return nil end
  return tonumber(total) * 1024, tonumber(used) * 1024, tonumber(free) * 1024
end

function H.human(n)
  if not n or n <= 0 then return "0 B" end
  local u = {"B", "KB", "MB", "GB", "TB"}
  local i = 1
  while n >= 1024 and i < #u do n = n / 1024; i = i + 1 end
  if i == 1 then return string.format("%d %s", n, u[i]) end
  return string.format("%.1f %s", n, u[i])
end

return H
