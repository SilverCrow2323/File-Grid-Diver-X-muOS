-- core/native.lua -- configure package.cpath and probe native modules.
--
-- Loaded once at startup (before any other core module). It appends
-- the app's lib/<arch>/ directory to package.cpath so that compiled
-- modules like lfs.so and cjson.so are found without having to be
-- placed next to main.lua.
--
-- Supported arch directories:
--   lib/arm64/       -- LuaJIT reports this on most aarch64 builds
--   lib/aarch64/     -- fallback for builds that report the Linux name
--   lib/x86_64/      -- desktop / MX Linux
--   lib/host/        -- symlink or drop-in for whatever you build locally

local M = { report = {} }

local function append_path(dir)
  if not dir or dir == "" then return end
  if not package.cpath:find(dir, 1, true) then
    package.cpath = package.cpath .. ";" .. dir .. "/?.so"
  end
end

-- Candidate arch directories, in priority order.
local arch = (jit and jit.arch) or ""
local candidates = {
  "lib/host",
  "lib/" .. arch,
}
if arch == "arm64" then
  candidates[#candidates + 1] = "lib/aarch64"
elseif arch == "aarch64" then
  candidates[#candidates + 1] = "lib/arm64"
end
candidates[#candidates + 1] = "lib/x86_64"
candidates[#candidates + 1] = "."

for _, dir in ipairs(candidates) do
  append_path(dir)
end

-- Probe the two we care about.
local function probe(name)
  local ok, mod = pcall(require, name)
  if ok and mod then
    M[name] = mod
    return "loaded"
  end
  return "missing"
end

M.report.lfs   = probe("lfs")
M.report.cjson = probe("cjson")
if M.report.cjson == "missing" then
  -- Some distributions ship cjson under a namespaced name.
  local ok, mod = pcall(require, "cjson.safe")
  if ok and mod then
    M.cjson = mod
    M.report.cjson = "loaded (cjson.safe)"
  end
end

-- Print a one-line summary so it shows up in the runtime log.
local f = io.open("data/fgd_runtime.log", "a")
if f then
  f:write(os.date("%Y-%m-%d %H:%M:%S ") ..
    "[native] arch=" .. (arch ~= "" and arch or "?") ..
    " lfs=" .. M.report.lfs ..
    " cjson=" .. M.report.cjson .. "\n")
  f:close()
end

-- Also print to stdout for the launcher log.
print("[native] arch=" .. (arch ~= "" and arch or "?"))
print("[native] lfs  = " .. M.report.lfs)
print("[native] cjson= " .. M.report.cjson)

return M
