local M = {}

function M.shq(s)
  if s == nil then return "''" end
  return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function norm(a, b, c)
  if type(a) == "number" then return a end
  if a == true  then return tonumber(c) or 0 end
  if a == false then return tonumber(c) or 1 end
  return 0
end

function M.exec(cmd) return norm(os.execute(cmd)) end

function M.read(cmd)
  local h = io.popen(cmd .. " 2>/dev/null")
  if not h then return nil end
  local out = h:read("*a") or ""
  h:close()
  return out
end

function M.lines(cmd)
  local out = M.read(cmd)
  if not out then return {} end
  local t = {}
  for line in out:gmatch("[^\r\n]+") do
    if line ~= "" then t[#t + 1] = line end
  end
  return t
end

function M.exists(p)
  if not p or p == "" then return false end
  local f = io.open(p, "rb")
  if f then f:close(); return true end
  return M.exec("[ -e " .. M.shq(p) .. " ]") == 0
end

function M.is_dir(p)
  if not p or p == "" then return false end
  return M.exec("[ -d " .. M.shq(p) .. " ]") == 0
end

function M.mkdir_p(p)
  if not p or p == "" then return false end
  return M.exec("mkdir -p " .. M.shq(p)) == 0
end

function M.atomic_write(path, content)
  local tmp = path .. ".tmp"
  local f = io.open(tmp, "w")
  if not f then return false end
  f:write(content)
  f:close()
  if os.rename(tmp, path) then return true end
  if M.exec("cp " .. M.shq(tmp) .. " " .. M.shq(path)) == 0 then
    os.remove(tmp); return true
  end
  os.remove(tmp)
  return false
end

return M
