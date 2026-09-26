-- services/checksum.lua -- hashes via system tools (md5sum, sha*sum).
local sh = require("core.sh")
local M  = {}

local function has(tool)
  local h = io.popen("command -v " .. tool .. " 2>/dev/null")
  if not h then return false end
  local out = h:read("*a") or ""
  h:close()
  return out ~= ""
end

local TOOLS = {
  md5    = "md5sum",
  sha1   = "sha1sum",
  sha256 = "sha256sum",
}

function M.compute(path, algo)
  algo = algo or "md5"
  local tool = TOOLS[algo]
  if not tool or not has(tool) then return nil, "tool missing: " .. tostring(tool) end
  local out = sh.read(tool .. " " .. sh.shq(path) .. " 2>/dev/null")
  if not out then return nil, "no output" end
  return out:match("^(%x+)")
end

function M.available()
  local t = {}
  for k, v in pairs(TOOLS) do t[k] = has(v) end
  return t
end

return M
