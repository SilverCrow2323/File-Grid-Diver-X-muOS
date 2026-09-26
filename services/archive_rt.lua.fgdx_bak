-- services/archive_rt.lua -- "Archive Rt" archive engine.
-- Detects, lists and extracts zip / tar / tar.gz / tar.bz2 / tar.xz / 7z / gz.
-- Parses native tool output to produce a clean entry list.
local sh = require("core.sh")
local M  = {}

-- ============================================================
--  Detection
-- ============================================================
local KINDS = {
  { ext = "tar.gz",  kind = "targz"  },
  { ext = "tgz",     kind = "targz"  },
  { ext = "tar.bz2", kind = "tarbz2" },
  { ext = "tbz2",    kind = "tarbz2" },
  { ext = "tar.xz",  kind = "tarxz"  },
  { ext = "txz",     kind = "tarxz"  },
  { ext = "tar",     kind = "tar"    },
  { ext = "zip",     kind = "zip"    },
  { ext = "7z",      kind = "7z"     },
  { ext = "gz",      kind = "gz"     },
  { ext = "rar",     kind = "rar"    },
  { ext = "cbr",     kind = "rar"    },
  { ext = "iso",     kind = "7z"     },
  { ext = "img",     kind = "7z"     },
  { ext = "dmg",     kind = "7z"     },
}

function M.detect(path)
  if not path then return nil end
  local lower = path:lower()
  for _, k in ipairs(KINDS) do
    if lower:sub(-#k.ext - 1) == "." .. k.ext then return k.kind end
  end
  return nil
end

function M.kind_label(kind)
  local labels = {
    zip="ZIP", targz="TAR.GZ", tarbz2="TAR.BZ2", tarxz="TAR.XZ",
    tar="TAR", ["7z"]="7-ZIP", gz="GZIP", rar="RAR", rar="RAR", rar="RAR", rar="RAR",
  }
  return labels[kind] or (kind or "?")
end

local function tool_available(tool)
  local h = io.popen("command -v " .. tool .. " 2>/dev/null")
  if not h then return false end
  local r = h:read("*a") or ""
  h:close()
  return r ~= ""
end

-- ============================================================
--  Listing
-- ============================================================
local function parse_zip(out)
  local entries = {}
  for line in out:gmatch("[^\n]+") do
    local size, date, time, name = line:match("^%s*(%d+)%s+(%d+-%d+-%d+)%s+(%d+:%d+)%s+(.+)$")
    if name then
      local is_dir = name:sub(-1) == "/"
      entries[#entries+1] = {
        name = name:gsub("/+$", ""),
        raw_name = name,
        size = tonumber(size) or 0,
        date = date .. " " .. time,
        is_dir = is_dir,
      }
    end
  end
  return entries
end

local function parse_tar(out)
  local entries = {}
  for line in out:gmatch("[^\n]+") do
    local perms, size, date, time, name =
      line:match("^(%S+)%s+%S+%s+(%d+)%s+(%d+-%d+-%d+)%s+(%d+:%d+)%s+(.+)$")
    if not name then
      -- fallback: some tars skip user/group
      size, date, time, name =
        line:match("^%S+%s+(%d+)%s+(%d+-%d+-%d+)%s+(%d+:%d+)%s+(.+)$")
    end
    if name then
      local is_dir = (perms and perms:sub(1,1) == "d") or name:sub(-1) == "/"
      entries[#entries+1] = {
        name = name:gsub("/+$", ""),
        raw_name = name,
        size = tonumber(size) or 0,
        date = date .. " " .. time,
        is_dir = is_dir,
      }
    end
  end
  return entries
end

local function parse_7z(out)
  local entries = {}
  local cur = {}
  for line in out:gmatch("[^\n]+") do
    if line:sub(1, 1) == "-" then
      if cur.Path then
        entries[#entries+1] = {
          name = cur.Path,
          raw_name = cur.Path,
          size = tonumber(cur.Size) or 0,
          date = (cur.Modified or ""):sub(1, 16),
          is_dir = cur.Folder == "+",
        }
      end
      cur = {}
    else
      local k, v = line:match("^([^=]+)%s*=%s*(.+)$")
      if k then cur[k] = v end
    end
  end
  if cur.Path then
    entries[#entries+1] = {
      name = cur.Path,
      raw_name = cur.Path,
      size = tonumber(cur.Size) or 0,
      date = (cur.Modified or ""):sub(1, 16),
      is_dir = cur.Folder == "+",
    }
  end
  return entries
end

function M.list(path)
  local kind = M.detect(path)
  if not kind then return nil, "not an archive" end

  if kind == "zip" then
    if not tool_available("unzip") then return nil, "unzip missing" end
    local out = sh.read("unzip -l " .. sh.shq(path) .. " 2>/dev/null")
    if not out then return nil, "unzip failed" end
    return parse_zip(out)
  elseif kind == "tar" or kind == "targz" or kind == "tarbz2" or kind == "tarxz" then
    if not tool_available("tar") then return nil, "tar missing" end
    local out = sh.read("tar tvf " .. sh.shq(path) .. " 2>/dev/null")
    if not out then return nil, "tar failed" end
    return parse_tar(out)
  elseif kind == "7z" then
    if not tool_available("7z") then return nil, "7z missing" end
    local out = sh.read("7z l -slt " .. sh.shq(path) .. " 2>/dev/null")
    if not out then return nil, "7z failed" end
    return parse_7z(out)
  elseif kind == "rar" then
    -- RAR/CBR: unrar primario, 7z fallback
    if tool_available("unrar") then
      local out = sh.read("unrar lb -c- " .. sh.shq(path) .. " 2>/dev/null")
      if out then
        local entries = {}
        for line in out:gmatch("[^\n]+") do
          if line ~= "" then
            entries[#entries+1] = { name = line, is_dir = false, size = 0 }
          end
        end
        if #entries > 0 then return entries end
      end
    end
    if tool_available("7z") then
      local out = sh.read("7z l -slt " .. sh.shq(path) .. " 2>/dev/null")
      if out then return parse_7z(out) end
    end
    return nil, "no rar tool available"
  elseif kind == "rar" then
    -- .rar / .cbr: prova unrar prima, 7z come fallback
    if tool_available("unrar") then
      local out = sh.read("unrar lb -c- " .. sh.shq(path) .. " 2>/dev/null")
      if out then
        local entries = {}
        for line in out:gmatch("[^\n]+") do
          if line ~= "" then
            entries[#entries+1] = { name = line, is_dir = false, size = 0, raw_name = line }
          end
        end
        if #entries > 0 then return entries end
      end
    end
    if tool_available("7z") then
      local out = sh.read("7z l -slt " .. sh.shq(path) .. " 2>/dev/null")
      if out then return parse_7z(out) end
    end
    return nil, "no rar tool"
  elseif kind == "gz" then
    -- gz is single-file
    return { { name = (path:match("([^/]+)$") or "file"):gsub("%.gz$", ""),
               size = 0, date = "", is_dir = false } }
  end
  return nil, "unsupported kind"
end

-- ============================================================
--  Extraction
-- ============================================================
-- opts = { to = "/absolute/path", selected = { set or nil } }
-- If selected is nil, extract all. Otherwise only listed names.
function M.extract(path, opts)
  opts = opts or {}
  local kind = M.detect(path)
  if not kind then return false, "not an archive" end
  local dir = opts.to or (path:match("^(.*)/[^/]+$") or ".")
  sh.exec("mkdir -p " .. sh.shq(dir))

  local sel = opts.selected
  if kind == "zip" then
    if not tool_available("unzip") then return false, "unzip missing" end
    if sel and #sel > 0 then
      local files = {}
      for _, n in ipairs(sel) do files[#files+1] = sh.shq(n) end
      local cmd = "cd " .. sh.shq(dir) .. " && unzip -o " ..
        sh.shq(path) .. " " .. table.concat(files, " ") .. " 2>&1"
      return sh.exec(cmd) == 0
    else
      local cmd = "cd " .. sh.shq(dir) .. " && unzip -o " ..
        sh.shq(path) .. " 2>&1"
      return sh.exec(cmd) == 0
    end
  elseif kind == "tar" or kind == "targz" or kind == "tarbz2" or kind == "tarxz" then
    if not tool_available("tar") then return false, "tar missing" end
    if sel and #sel > 0 then
      local files = {}
      for _, n in ipairs(sel) do files[#files+1] = sh.shq(n) end
      local cmd = "tar xf " .. sh.shq(path) .. " -C " ..
        sh.shq(dir) .. " " .. table.concat(files, " ") .. " 2>&1"
      return sh.exec(cmd) == 0
    else
      local cmd = "tar xf " .. sh.shq(path) .. " -C " .. sh.shq(dir) .. " 2>&1"
      return sh.exec(cmd) == 0
    end
  elseif kind == "7z" then
    if not tool_available("7z") then return false, "7z missing" end
    if sel and #sel > 0 then
      local files = {}
      for _, n in ipairs(sel) do files[#files+1] = sh.shq(n) end
      local cmd = "7z x -y -o" .. sh.shq(dir) .. " " ..
        sh.shq(path) .. " " .. table.concat(files, " ") .. " 2>&1"
      return sh.exec(cmd) == 0
    else
      local cmd = "7z x -y -o" .. sh.shq(dir) .. " " .. sh.shq(path) .. " 2>&1"
      return sh.exec(cmd) == 0
    end
  elseif kind == "rar" then
    if not tool_available("unrar") then return false, "unrar missing" end
    if sel and #sel > 0 then
      local files = {}
      for _, n in ipairs(sel) do files[#files+1] = sh.shq(n) end
      local cmd = "unrar x -o+ " .. sh.shq(path) .. " " ..
        table.concat(files, " ") .. " " .. sh.shq(dir .. "/") .. " 2>&1"
      return sh.exec(cmd) == 0
    else
      local cmd = "unrar x -o+ " .. sh.shq(path) .. " " .. sh.shq(dir .. "/") .. " 2>&1"
      return sh.exec(cmd) == 0
    end
  elseif kind == "rar" then
    if not tool_available("unrar") then return false, "unrar missing" end
    if sel and #sel > 0 then
      local files = {}
      for _, n in ipairs(sel) do files[#files+1] = sh.shq(n) end
      local cmd = "unrar x -o+ " .. sh.shq(path) .. " " ..
        table.concat(files, " ") .. " " .. sh.shq(dir .. "/") .. " 2>&1"
      return sh.exec(cmd) == 0
    else
      local cmd = "unrar x -o+ " .. sh.shq(path) .. " " .. sh.shq(dir .. "/") .. " 2>&1"
      return sh.exec(cmd) == 0
    end
  elseif kind == "gz" then
    local cmd = "gzip -dk -c " .. sh.shq(path) .. " > " ..
      sh.shq(dir .. "/" .. ((path:match("([^/]+)$") or "file"):gsub("%.gz$", "")))
    return sh.exec(cmd) == 0
  end
  return false, "unsupported kind"
end

-- Build a tree from the flat entry list.
-- Returns a node: { name, is_dir, size, children = {}, depth }
function M.build_tree(entries)
  local root = { name = "", is_dir = true, size = 0, children = {}, depth = 0 }
  local by_path = { [""] = root }

  local function ensure(path, is_dir, size)
    if by_path[path] then return by_path[path] end
    local parent_path = path:match("^(.*)/[^/]+$") or ""
    local parent = by_path[parent_path]
    if not parent then
      -- Create parent as directory
      parent = ensure(parent_path, true, 0)
    end
    local node = {
      name = path:match("([^/]+)$") or path,
      path = path, is_dir = is_dir, size = size or 0,
      children = {}, depth = (parent.depth or 0) + 1,
      parent = parent,
    }
    parent.children[#parent.children+1] = node
    by_path[path] = node
    return node
  end

  for _, e in ipairs(entries or {}) do
    if e.name and e.name ~= "" then
      ensure(e.name, e.is_dir, e.size)
    end
  end

  -- Sort children: dirs first, then name
  local function sort_node(node)
    table.sort(node.children, function(a, b)
      if a.is_dir ~= b.is_dir then return a.is_dir end
      return a.name:lower() < b.name:lower()
    end)
    for _, c in ipairs(node.children) do sort_node(c) end
  end
  sort_node(root)
  return root
end

return M
