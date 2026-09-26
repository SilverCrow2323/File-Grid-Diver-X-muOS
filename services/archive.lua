-- services/archive.lua -- archive creation and extraction.
-- Wraps the system tools (zip/unzip, tar, 7z, gzip) if available.
-- All operations are shell-based, all paths are quoted with sh.shq.

local sh = require("core.sh")
local M  = {}

-- -- Tool detection -------------------------------------------------
local tools = nil
local function detect()
  if tools then return tools end
  tools = {}
  for _, t in ipairs({ "zip", "unzip", "tar", "gzip", "bzip2", "xz", "7z" }) do
    local h = io.popen("command -v " .. t .. " 2>/dev/null")
    if h then
      local out = h:read("*a") or ""
      h:close()
      tools[t] = (out ~= "")
    end
  end
  return tools
end

function M.tools() return detect() end

-- -- Type detection -------------------------------------------------
function M.kind(path)
  if not path then return nil end
  local p = path:lower()
  if p:match("%.tar%.gz$") or p:match("%.tgz$")     then return "targz"  end
  if p:match("%.tar%.bz2$") or p:match("%.tbz2?$")  then return "tarbz2" end
  if p:match("%.tar%.xz$") or p:match("%.txz$")     then return "tarxz"  end
  if p:match("%.tar$")                              then return "tar"    end
  if p:match("%.zip$")                              then return "zip"    end
  if p:match("%.7z$")                               then return "7z"     end
  if p:match("%.gz$")                               then return "gz"     end
  return nil
end

function M.is_archive(path) return M.kind(path) ~= nil end

-- -- Listing -------------------------------------------------------
-- Returns a string with the tool output, or nil + error message.
function M.list(path)
  local t = detect()
  local k = M.kind(path)
  if not k then return nil, "not an archive" end
  local cmd
  if k == "zip" and t.unzip then
    cmd = "unzip -l " .. sh.shq(path) .. " 2>&1"
  elseif (k == "tar" or k == "targz" or k == "tarbz2" or k == "tarxz") and t.tar then
    cmd = "tar tf " .. sh.shq(path) .. " 2>&1"
  elseif k == "7z" and t["7z"] then
    cmd = "7z l " .. sh.shq(path) .. " 2>&1"
  else
    return nil, "no tool for " .. k
  end
  return sh.read(cmd), nil
end

-- -- Extraction ----------------------------------------------------
-- Extract archive into its own directory (same folder as the file).
function M.extract_here(path)
  local t = detect()
  local k = M.kind(path)
  if not k then return false, "not an archive" end
  local dir = path:match("^(.*)/[^/]+$") or "."
  local cmd
  if k == "zip" and t.unzip then
    cmd = "cd " .. sh.shq(dir) .. " && unzip -o " ..
          sh.shq(path) .. " 2>&1"
  elseif (k == "tar" or k == "targz" or k == "tarbz2" or k == "tarxz") and t.tar then
    cmd = "cd " .. sh.shq(dir) .. " && tar xf " ..
          sh.shq(path) .. " 2>&1"
  elseif k == "7z" and t["7z"] then
    cmd = "cd " .. sh.shq(dir) .. " && 7z x -y " ..
          sh.shq(path) .. " 2>&1"
  elseif k == "gz" and t.gzip then
    cmd = "cd " .. sh.shq(dir) .. " && gzip -dk " ..
          sh.shq(path) .. " 2>&1"
  else
    return false, "no extractor for " .. k
  end
  return sh.exec(cmd) == 0, nil
end

-- Extract archive into a new directory named after the archive.
function M.extract_into_folder(path)
  local t = detect()
  local k = M.kind(path)
  if not k then return false, "not an archive" end
  local dir = path:match("^(.*)/[^/]+$") or "."
  local name = path:match("([^/]+)$") or "extracted"
  name = name:gsub("%.tar%.gz$", ""):gsub("%.tar%.bz2$", "")
             :gsub("%.tar%.xz$", ""):gsub("%.tgz$", "")
             :gsub("%.tbz2$", ""):gsub("%.txz$", "")
             :gsub("%.tar$", ""):gsub("%.zip$", "")
             :gsub("%.7z$", ""):gsub("%.gz$", "")
  local out = dir .. "/" .. name
  local mk = sh.exec("mkdir -p " .. sh.shq(out))
  if mk ~= 0 then return false, "mkdir failed" end
  local cmd
  if k == "zip" and t.unzip then
    cmd = "unzip -o " .. sh.shq(path) .. " -d " .. sh.shq(out) .. " 2>&1"
  elseif (k == "tar" or k == "targz" or k == "tarbz2" or k == "tarxz") and t.tar then
    cmd = "tar xf " .. sh.shq(path) .. " -C " .. sh.shq(out) .. " 2>&1"
  elseif k == "7z" and t["7z"] then
    cmd = "7z x -y -o" .. sh.shq(out) .. " " .. sh.shq(path) .. " 2>&1"
  else
    return false, "no extractor for " .. k
  end
  return sh.exec(cmd) == 0, nil
end

-- -- Creation ------------------------------------------------------
-- All paths must live in the same directory; we cd there and zip/tar
-- the basenames so the resulting archive has no absolute prefixes.
local function basename(p) return p:match("([^/]+)$") or p end

local function names_in_dir(paths, dir)
  local out = {}
  for _, p in ipairs(paths) do
    -- If a path is not directly in `dir`, walk up to find the prefix.
    if p:sub(1, #dir + 1) == dir .. "/" then
      out[#out + 1] = basename(p)
    else
      out[#out + 1] = p
    end
  end
  return out
end

local function join_names(names)
  local q = {}
  for _, n in ipairs(names) do q[#q + 1] = sh.shq(n) end
  return table.concat(q, " ")
end

function M.create_zip(paths, out, dir)
  if #paths == 0 then return false, "nothing to archive" end
  local t = detect()
  if not t.zip then return false, "zip not installed" end
  dir = dir or (paths[1]:match("^(.*)/[^/]+$") or ".")
  local names = names_in_dir(paths, dir)
  local cmd = "cd " .. sh.shq(dir) .. " && zip -r " ..
              sh.shq(out) .. " " .. join_names(names) .. " 2>&1"
  return sh.exec(cmd) == 0, nil
end

function M.create_targz(paths, out, dir)
  if #paths == 0 then return false, "nothing to archive" end
  local t = detect()
  if not t.tar then return false, "tar not installed" end
  dir = dir or (paths[1]:match("^(.*)/[^/]+$") or ".")
  local names = names_in_dir(paths, dir)
  local cmd = "cd " .. sh.shq(dir) .. " && tar czf " ..
              sh.shq(out) .. " " .. join_names(names) .. " 2>&1"
  return sh.exec(cmd) == 0, nil
end

function M.create_tar(paths, out, dir)
  if #paths == 0 then return false, "nothing to archive" end
  local t = detect()
  if not t.tar then return false, "tar not installed" end
  dir = dir or (paths[1]:match("^(.*)/[^/]+$") or ".")
  local names = names_in_dir(paths, dir)
  local cmd = "cd " .. sh.shq(dir) .. " && tar cf " ..
              sh.shq(out) .. " " .. join_names(names) .. " 2>&1"
  return sh.exec(cmd) == 0, nil
end

function M.create_7z(paths, out, dir)
  if #paths == 0 then return false, "nothing to archive" end
  local t = detect()
  if not t["7z"] then return false, "7z not installed" end
  dir = dir or (paths[1]:match("^(.*)/[^/]+$") or ".")
  local names = names_in_dir(paths, dir)
  local cmd = "cd " .. sh.shq(dir) .. " && 7z a -y " ..
              sh.shq(out) .. " " .. join_names(names) .. " 2>&1"
  return sh.exec(cmd) == 0, nil
end

-- -- Preview (first N entries only) ------------------------------
function M.preview(path, max_lines)
  local out, err = M.list(path)
  if not out then return nil, err end
  max_lines = max_lines or 40
  local lines = {}
  local n = 0
  for line in out:gmatch("[^\r\n]+") do
    n = n + 1
    if n > max_lines then
      lines[#lines + 1] = "..."
      break
    end
    lines[#lines + 1] = line
  end
  return lines, nil
end

return M
