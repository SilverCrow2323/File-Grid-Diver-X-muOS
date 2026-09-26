-- services/fs.lua — synchronous filesystem operations.
-- Every operation goes through sh.shq. Never builds shell commands
-- without quoting. Safe on paths with spaces, quotes, and unicode.
local sh = require("core.sh")
local LFS = require("core.lfs")
local M  = {}

-- ── Introspection ───────────────────────────────────────────
function M.exists(p)
  if LFS.available then
    local v = LFS.exists(p)
    if v ~= nil then return v end
  end
  return sh.exists(p)
end
function M.is_dir(p)
  if LFS.available then
    local v = LFS.is_dir(p)
    if v ~= nil then return v end
  end
  return sh.is_dir(p)
end


-- Runtime probe: does the system stat support the GNU format we use?
local _stat_supports_gnu = nil
local function probe_stat()
  if _stat_supports_gnu ~= nil then return _stat_supports_gnu end
  local out = sh.read("stat -c '%n|%F|%s|%Y|%A' / 2>/dev/null")
  if out and out:match("^/|") then
    _stat_supports_gnu = true
  else
    _stat_supports_gnu = false
  end
  return _stat_supports_gnu
end

-- Fallback listing: parse "ls -lan" output (BusyBox compatible).
-- Format per line:  perm links owner group size  mon day time|year  name
local function list_via_ls(path)
  local cmd = "ls -lan -- " .. sh.shq(path) .. " 2>/dev/null"
  local lines = sh.lines(cmd)
  local out = {}
  for i, line in ipairs(lines) do
    if i > 1 then -- skip "total N"
      local perm, links, owner, group, size, mo, da, ti, name =
        line:match("^(%S+)%s+(%d+)%s+(%S+)%s+(%S+)%s+(%d+)%s+(%S+)%s+(%S+)%s+(%S+)%s+(.+)$")
      if perm and name then
        if name == "." or name == ".." then
          -- skip
        else
          local is_dir  = perm:sub(1, 1) == "d"
          local is_link = perm:sub(1, 1) == "l"
          local mtime = os.time()  -- ls doesn't give epoch; use now
          out[#out + 1] = {
            path    = path:gsub("/$", "") .. "/" .. name,
            name    = name,
            is_dir  = is_dir,
            is_link = is_link,
            size    = tonumber(size) or 0,
            mtime   = mtime,
            perms   = perm,
            ftype   = is_dir and "directory" or (is_link and "symbolic link" or "regular file"),
          }
        end
      end
    end
  end
  return out
end

local function trim(s)
  if not s then return "" end
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Parse one line of the format:
--   /full/path|regular file|12345|1789800627|-rw-r--r--
local function parse_stat_line(line)
  if not line or line == "" then return nil end
  local path, ftype, size, mtime, perms = line:match("^(.-)|(.-)|(%d+)|(%d+)|(.+)$")
  if not path then return nil end
  local name = path:match("([^/]+)$") or path
  local is_dir = ftype:find("directory") ~= nil
  local is_link = ftype:find("symbolic link") ~= nil
  return {
    path    = path,
    name    = name,
    is_dir  = is_dir,
    is_link = is_link,
    size    = tonumber(size) or 0,
    mtime   = tonumber(mtime) or 0,
    perms   = trim(perms),
    ftype   = ftype,
  }
end

-- List directory contents (names only, fast). Returns array of entries.
function M.list(path)
  if not path or path == "" then return {} end
  if LFS.available then
    local native = LFS.list(path)
    if native then return native end
  end
  if not probe_stat() then
    return list_via_ls(path)
  end
  local cmd = 'find ' .. sh.shq(path) ..
    ' -mindepth 1 -maxdepth 1 -exec stat -c "%n|%F|%s|%Y|%A" {} + 2>/dev/null'
  local lines = sh.lines(cmd)
  local out = {}
  for _, line in ipairs(lines) do
    local e = parse_stat_line(line)
    if e then out[#out + 1] = e end
  end
  return out
end

function M.stat(path)
  if not path or path == "" then return nil end
  if LFS.available then
    local native = LFS.stat(path)
    if native then return native end
  end
  if not probe_stat() then
    -- fallback: derive from parent listing
    local parent = path:match("^(.*)/[^/]+$") or "."
    local base = path:match("([^/]+)$") or path
    for _, e in ipairs(list_via_ls(parent)) do
      if e.name == base then return e end
    end
    return nil
  end
  local line = sh.read('stat -c "%n|%F|%s|%Y|%A" ' .. sh.shq(path) ..
    ' 2>/dev/null')
  return parse_stat_line(line)
end

-- ── Mutations ───────────────────────────────────────────────
function M.mkdir(path)
  if LFS.available then
    local v = LFS.mkdir(path)
    if v == true then return true end
    -- fall through to shell on false (e.g. parent missing)
  end
  return sh.exec("mkdir -p " .. sh.shq(path)) == 0
end

function M.touch(path)
  if LFS.available then
    local v = LFS.touch(path)
    if v ~= nil then return v end
  end
  return sh.exec("touch " .. sh.shq(path)) == 0
end

-- Recursive copy that preserves attributes.
function M.cp(src, dst)
  return sh.exec("cp -a " .. sh.shq(src) .. " " .. sh.shq(dst)) == 0
end

-- Move; falls back to cp+rm across devices.
function M.mv(src, dst)
  if sh.exec("mv " .. sh.shq(src) .. " " .. sh.shq(dst)) == 0 then
    return true
  end
  if M.cp(src, dst) then
    sh.exec("rm -rf " .. sh.shq(src))
    return true
  end
  return false
end

function M.rm(path)
  if not path or path == "/" or path == "" then return false end
  return sh.exec("rm -rf " .. sh.shq(path)) == 0
end

-- Move to trash via services/trash (per-volume .fgd_trash).
-- Kept here for backward compatibility; delegates to the real module.
function M.trash(path)
  if not path or path == "" then return nil end
  local ok, T = pcall(require, "services.trash")
  if not ok or not T or not T.move then return nil end
  local success, stored = T.move(path)
  if success then return stored end
  return nil
end

-- ── Read / write ────────────────────────────────────────────
function M.read(path, max_bytes)
  local f = io.open(path, "rb")
  if not f then return nil end
  local size = f:seek("end")
  f:seek("set", 0)
  if max_bytes and size > max_bytes then
    local content = f:read(max_bytes)
    f:close()
    return content, size, true   -- truncated
  end
  local content = f:read("*a")
  f:close()
  return content, size, false
end

function M.write(path, content)
  return sh.atomic_write(path, content)
end

-- ── Utilities ───────────────────────────────────────────────
function M.human_size(n)
  if not n or n <= 0 then return "0 B" end
  if n < 1024 then return n .. " B" end
  if n < 1024 * 1024 then
    return string.format("%.1f KB", n / 1024)
  end
  if n < 1024 * 1024 * 1024 then
    return string.format("%.1f MB", n / (1024 * 1024))
  end
  return string.format("%.2f GB", n / (1024 * 1024 * 1024))
end

function M.ext_of(name)
  if not name then return "" end
  local e = name:match("%.([^.]+)$")
  if e then return e:lower() end
  return ""
end

-- Classify a file by extension. Returns one of:
-- dir, image, audio, video, text, archive, exe, rom, unknown
function M.classify(e)
  if e.is_dir then return "dir" end
  local ext = M.ext_of(e.name)
  local IMG = { png=1, jpg=1, jpeg=1, webp=1, bmp=1, gif=1,
                tiff=1, tif=1, svg=1, ico=1, heic=1, avif=1 }
  local AUD = { ogg=1, oga=1, mp3=1, wav=1, flac=1, opus=1, m4a=1, aac=1,
                wma=1, ape=1, mid=1, midi=1, mod=1, s3m=1, xm=1, it=1 }
  local VID = { mp4=1, mkv=1, avi=1, webm=1, mov=1, mpg=1, mpeg=1, m4v=1,
                flv=1, wmv=1, ["3gp"]=1, ogv=1, ts=1, m2ts=1 }
  local TXT = { txt=1, md=1, markdown=1, rtf=1, log=1,
                ini=1, conf=1, cfg=1, json=1, toml=1, desktop=1, service=1,
                lua=1, sh=1, bash=1, zsh=1, py=1, rb=1, pl=1, php=1,
                js=1, ts=1, jsx=1, tsx=1, go=1, rs=1, java=1, swift=1, kt=1,
                c=1, h=1, cpp=1, cxx=1, hpp=1,
                csv=1, xml=1, yaml=1, yml=1, gptk=1,
                html=1, htm=1, css=1, scss=1, sass=1, less=1 }
  local ARC = { zip=1, tar=1, gz=1, tgz=1, xz=1, bz2=1, ["7z"]=1, rar=1,
                lz4=1, zst=1, lzma=1, cab=1, arj=1, zipx=1,
                muxapp=1, muxzip=1, muxupd=1, muxthm=1 }
  local ROM = { iso=1, gcm=1, rvz=1, wbfs=1, wia=1, ciso=1, nkit=1, gcz=1,
                nes=1, snes=1, smc=1, gba=1, gbc=1, gb=1, nds=1, cso=1,
                ["3ds"]=1, cia=1, xci=1, nsp=1, nro=1, pbp=1, chd=1, cue=1,
                m3u=1, pce=1, gen=1, smd=1, ["32x"]=1, z64=1, n64=1, v64=1 }
  local EXE = { elf=1, bin=1, deb=1, ipk=1, appimage=1, exe=1, apk=1 }
  local DOC = { pdf=1, epub=1, mobi=1,
                doc=1, docx=1, xls=1, xlsx=1, ppt=1, pptx=1,
                odt=1, ods=1, odp=1 }
  local FONT = { ttf=1, otf=1, woff=1, woff2=1, eot=1 }
  if IMG[ext] then return "image" end
  if AUD[ext] then return "audio" end
  if VID[ext] then return "video" end
  if TXT[ext] then return "text" end
  if ARC[ext] then return "archive" end
  if ROM[ext] then return "rom" end
  if DOC[ext] then return "doc" end
  if FONT[ext] then return "font" end
  if EXE[ext] then return "exe" end
  return "unknown"
end

-- ── Sorting ─────────────────────────────────────────────────
-- key: "name" | "size" | "date" | "type"
-- dirs_first: bool
function M.sort(entries, key, dirs_first)
  key = key or "name"
  table.sort(entries, function(a, b)
    if dirs_first then
      if a.is_dir ~= b.is_dir then return a.is_dir end
    end
    if key == "size" then
      if a.size ~= b.size then return a.size > b.size end
    elseif key == "date" then
      if a.mtime ~= b.mtime then return a.mtime > b.mtime end
    elseif key == "type" then
      local ea = M.ext_of(a.name)
      local eb = M.ext_of(b.name)
      if ea ~= eb then return ea < eb end
    end
    return a.name:lower() < b.name:lower()
  end)
  return entries
end

-- ── Filter ──────────────────────────────────────────────────
-- filter: "all" | "dirs" | "files" | category string (image, audio, ...)
function M.filter(entries, filter)
  if not filter or filter == "all" then return entries end
  local out = {}
  for _, e in ipairs(entries) do
    if filter == "dirs"  and e.is_dir then out[#out+1] = e
    elseif filter == "files" and not e.is_dir then out[#out+1] = e
    elseif filter ~= "dirs" and filter ~= "files" then
      if M.classify(e) == filter then out[#out+1] = e end
    end
  end
  return out
end

function M.fuzzy_match(name, query)
  if not query or query == "" then return true end
  local n = name:lower()
  local q = query:lower()
  local qi = 1
  for i = 1, #n do
    if n:sub(i, i) == q:sub(qi, qi) then
      qi = qi + 1
      if qi > #q then return true end
    end
  end
  return false
end

return M
