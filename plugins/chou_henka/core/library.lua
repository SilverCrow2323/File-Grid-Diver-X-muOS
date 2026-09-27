-- core/library.lua -- media scanner + metadata + watchstate.
local CFG  = require("plugins.chou_henka.core.config")
local sh   = require("core.sh")
local META = require("plugins.chou_henka.core.metadata")
local WS   = require("plugins.chou_henka.core.watchstate")

local M = {}
M.DB_PATH = "data/chou_henka_library.json"

M.CAT_ORDER = { "audio","video","image","comic","book","doc","other" }
M.categories = {
  audio = { label="Music",  colour={0.90,0.55,0.35} },
  video = { label="Videos", colour={0.85,0.42,0.42} },
  image = { label="Images", colour={0.29,0.62,0.72} },
  comic = { label="Comics", colour={0.95,0.75,0.35} },
  book  = { label="Books",  colour={0.55,0.72,0.50} },
  doc   = { label="Docs",   colour={0.85,0.45,0.55} },
  other = { label="Other",  colour={0.44,0.42,0.38} },
}

local EXT = {
  mp3="audio", ogg="audio", oga="audio", wav="audio", flac="audio",
  opus="audio", m4a="audio", aac="audio", wma="audio", ape="audio",
  alac="audio", mid="audio", midi="audio", mod="audio", s3m="audio",
  xm="audio", it="audio",
  mp4="video", mkv="video", avi="video", webm="video", mov="video",
  mpg="video", mpeg="video", m4v="video", flv="video", wmv="video",
  ["3gp"]="video", ogv="video", ts="video", m2ts="video", vob="video",
  png="image", jpg="image", jpeg="image", webp="image", bmp="image",
  gif="image", tiff="image", tif="image", svg="image", ico="image",
  heic="image", avif="image",
  cbz="comic", cbr="comic", cb7="comic", cbt="comic",
  epub="book", mobi="book", pdf="book",
  doc="doc", docx="doc", xls="doc", xlsx="doc", ppt="doc", pptx="doc",
  odt="doc", ods="doc", odp="doc", rtf="doc",
}

local function ext_of(p)
  local e = p:match("%.([^.]+)$")
  return e and e:lower() or ""
end

function M.categorize(p) return EXT[ext_of(p)] or "other" end

local db = { tracks = {}, scanned_at = 0, stats = {} }

function M.load()
  local f = io.open(M.DB_PATH, "r")
  if not f then return end
  local c = f:read("*a"); f:close()
  local JSON = require("core.json")
  local ok, d = pcall(JSON.decode, c)
  if ok and type(d) == "table" then
    db.tracks = d.tracks or {}
    db.scanned_at = d.scanned_at or 0
    db.stats = d.stats or {}
  end
end

function M.save()
  pcall(function() os.execute("mkdir -p data") end)
  local JSON = require("core.json")
  local f = io.open(M.DB_PATH, "w")
  if not f then return end
  local ok, s = pcall(JSON.encode, db)
  if ok then f:write(s) end
  f:close()
end

function M.tracks() return db.tracks end
function M.scanned_at() return db.scanned_at end

function M.count_by_cat()
  local c = { audio=0, video=0, image=0, comic=0, book=0, doc=0, other=0 }
  for _, t in ipairs(db.tracks) do c[t.cat] = (c[t.cat] or 0) + 1 end
  return c
end

function M.clear()
  db.tracks = {}
  db.scanned_at = 0
  db.stats = {}
  M.save()
end

function M.is_enabled(cat)
  local d = CFG.get("library", "disabled_categories") or {}
  return d[cat] ~= true
end

function M.set_enabled(cat, on)
  local d = CFG.get("library", "disabled_categories") or {}
  if on then d[cat] = nil else d[cat] = true end
  CFG.set("library", "disabled_categories", d)
  CFG.save()
end

function M.enabled_categories()
  local out = {}
  for _, k in ipairs(M.CAT_ORDER) do
    if M.is_enabled(k) then out[#out+1] = k end
  end
  return out
end

local scan_job = nil

function M.is_scanning() return scan_job ~= nil end

function M.start_scan()
  if scan_job then return false, "already scanning" end
  local sources = CFG.get("sources") or {}
  if #sources == 0 then return false, "no sources" end

  local id = tostring(os.time()) .. "_" .. tostring(math.random(1000,9999))
  local out    = "/tmp/ch_" .. id .. ".out"
  local done   = "/tmp/ch_" .. id .. ".done"
  local script = "/tmp/ch_" .. id .. ".sh"
  local depth  = CFG.get("library", "scan_max_depth") or 6

  local L = {
    "#!/bin/sh", "set +e",
    "OUT=" .. sh.shq(out),
    "DONE=" .. sh.shq(done),
    ': > "$OUT"',
  }
  for _, src in ipairs(sources) do
    if src and src ~= "" then
      L[#L+1] = "find " .. sh.shq(src) .. " -maxdepth " .. depth ..
        " -type f -exec stat -c '%s|%Y|%n' {} + 2>/dev/null | tr '|' '\\t' >> \"$OUT\" || true"
    end
  end
  L[#L+1] = 'touch "$DONE"'

  local f = io.open(script, "w")
  if not f then return false, "cannot write scan script" end
  f:write(table.concat(L, "\n") .. "\n")
  f:close()

  pcall(function()
    os.execute("chmod +x " .. sh.shq(script))
    os.execute("setsid sh " .. sh.shq(script) .. " </dev/null >/dev/null 2>&1 &")
  end)

  scan_job = { id=id, script=script, out=out, done=done, t=0 }
  return true
end

function M.poll_scan(dt)
  if not scan_job then return false end
  scan_job.t = scan_job.t + (dt or 0)
  if scan_job.t > 180 then
    M.cancel_scan()
    return true
  end
  local f = io.open(scan_job.done, "r")
  if not f then return false end
  f:close()

  db.tracks = {}
  local of = io.open(scan_job.out, "r")
  if of then
    for line in of:lines() do
      local size, mt, path = line:match("^(%d+)%s+([%d%.]+)%s+(.+)$")
      if path and size then
        local cat = M.categorize(path)
        local tr = {
          path  = path,
          name  = path:match("([^/]+)$") or path,
          ext   = ext_of(path),
          cat   = cat,
          size  = tonumber(size) or 0,
          mtime = tonumber(mt) or 0,
        }
        local mt_data = META.get(path)
        if mt_data then
          tr.title  = mt_data.title
          tr.plot   = mt_data.plot
          tr.year   = mt_data.year
          tr.rating = mt_data.rating
          tr.genre  = mt_data.genre
          tr.poster = mt_data.poster
          tr.fanart = mt_data.fanart
          tr.thumb  = mt_data.thumb
        end
        db.tracks[#db.tracks+1] = tr
      end
    end
    of:close()
  end

  db.scanned_at = os.time()
  db.stats = M.count_by_cat()
  M.save()
  M.cancel_scan()
  return true
end

function M.cancel_scan()
  if not scan_job then return end
  pcall(function()
    os.execute("pkill -f " .. sh.shq(scan_job.script) .. " 2>/dev/null")
  end)
  os.remove(scan_job.script)
  os.remove(scan_job.out)
  os.remove(scan_job.done)
  scan_job = nil
end

function M.filter(cat, query)
  local out = {}
  local q = (query or ""):lower()
  for _, t in ipairs(db.tracks) do
    if (not cat or cat == "all" or t.cat == cat)
       and (q == "" or (t.name or ""):lower():find(q, 1, true)) then
      out[#out+1] = t
    end
  end
  return out
end

function M.filter_state(items, state)
  if not state or state == "all" then return items end
  local out = {}
  for _, it in ipairs(items) do
    local keep = false
    if     state == "watched"   then keep = WS.is_watched(it.path)
    elseif state == "unwatched" then keep = not WS.is_watched(it.path)
    elseif state == "favorites" then keep = WS.is_favorite(it.path)
    elseif state == "resume"    then keep = WS.get_resume(it.path) ~= nil
    else keep = true end
    if keep then out[#out+1] = it end
  end
  return out
end

function M.search(query)
  query = (query or ""):lower()
  query = query:gsub("^%s+", ""):gsub("%s+$", "")
  if query == "" then return db.tracks end
  local out = {}
  for _, it in ipairs(db.tracks) do
    local hay = ((it.title or "") .. " " .. (it.name or "")):lower()
    local qi = 1
    local matched = false
    for i = 1, #hay do
      if hay:sub(i, i) == query:sub(qi, qi) then
        qi = qi + 1
        if qi > #query then matched = true; break end
      end
    end
    if matched then out[#out+1] = it end
  end
  return out
end

M.load()
return M
