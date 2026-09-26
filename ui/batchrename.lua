-- ui/batchrename.lua -- batch rename via simple patterns.
-- Patterns (case-insensitive):
--   {n}     -> index (1, 2, 3 ...)
--   {nn}    -> zero-padded index (01, 02 ...)
--   {nnn}   -> zero-padded to 3 digits
--   {name}  -> original name without extension
--   {ext}   -> original extension including dot
--   {lower} -> lowercase {name}
--   {upper} -> uppercase {name}
local M = {}

local function parse(pattern, name, ext, idx)
  local out = pattern
  out = out:gsub("{name}",  name)
  out = out:gsub("{ext}",   ext)
  out = out:gsub("{lower}", name:lower())
  out = out:gsub("{upper}", name:upper())
  out = out:gsub("{nnn}",   string.format("%03d", idx))
  out = out:gsub("{nn}",    string.format("%02d", idx))
  out = out:gsub("{n}",     tostring(idx))
  return out
end

-- Returns list of { old = path, new = path, newname = name }
function M.plan(paths, pattern)
  local plan = {}
  for i, p in ipairs(paths) do
    local full = p:match("([^/]+)$") or p
    local dir  = p:match("^(.*)/[^/]+$") or "."
    local name, ext
    if full:match("%.%w+$") then
      name, ext = full:match("^(.*)(%.[^%.]+)$")
    else
      name, ext = full, ""
    end
    local newname = parse(pattern, name, ext, i)
    plan[#plan + 1] = {
      old = p,
      new = dir .. "/" .. newname,
      newname = newname,
    }
  end
  return plan
end

function M.apply(plan)
  local sh = require("core.sh")
  -- two-pass rename to avoid collisions
  local tmp = {}
  for i, e in ipairs(plan) do
    local t = e.old .. ".fgd_tmp_" .. i
    if sh.exec("mv " .. sh.shq(e.old) .. " " .. sh.shq(t)) == 0 then
      tmp[#tmp + 1] = { t = t, final = e.new }
    end
  end
  local ok = 0
  for _, e in ipairs(tmp) do
    if sh.exec("mv " .. sh.shq(e.t) .. " " .. sh.shq(e.final)) == 0 then
      ok = ok + 1
    else
      -- restore as a fallback
      sh.exec("mv " .. sh.shq(e.t) .. " " .. sh.shq(e.final .. ".undone"))
    end
  end
  return ok
end

return M
