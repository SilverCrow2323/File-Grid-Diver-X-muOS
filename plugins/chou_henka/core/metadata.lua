-- core/metadata.lua -- metadata locale stile Kodi.
-- Legge, accanto al file multimediale:
--   <base>.nfo        (XML Kodi, minimal parser)
--   <base>-poster.jpg / .png
--   <base>.jpg / .png
--   poster.jpg / folder.jpg / cover.jpg   (nella stessa cartella)
--   fanart.jpg / background.jpg
--   <base>-thumb.jpg / <base>.tbn
-- Restituisce una tabella con: title, plot, year, rating, genre,
--   poster, fanart, thumb (path immagine o nil).
local M = {}

local function exists(p)
  local f = io.open(p, "rb"); if f then f:close(); return true end; return false
end

local function read_file(p)
  local f = io.open(p, "r"); if not f then return nil end
  local c = f:read("*a"); f:close(); return c
end

local function strip_ext(name)
  return (name:gsub("%.[^.]+$", ""))
end

local function basename(p) return (p or ""):match("([^/]+)$") or p or "" end
local function dirname(p)  return (p or ""):match("^(.*)/[^/]+$") or "." end

local function unescape(s)
  if not s then return nil end
  s = s:gsub("&lt;", "<"):gsub("&gt;", ">")
  s = s:gsub("&quot;", '"'):gsub("&apos;", "'")
  s = s:gsub("&amp;", "&")
  s = s:gsub("%s+$", "")
  return s
end

-- Estrae il valore di un tag semplice <tag>...</tag>
local function get_tag(xml, tag)
  if not xml then return nil end
  local v = xml:match("<" .. tag .. "[^>]*>(.-)</" .. tag .. ">")
  if v then v = v:gsub("<!%[CDATA%[(.-)%]%]>", "%1") end
  return unescape(v)
end

-- Estrae tutti i valori di un tag ripetuto
local function get_all(xml, tag)
  local out = {}
  if not xml then return out end
  for v in xml:gmatch("<" .. tag .. "[^>]*>(.-)</" .. tag .. ">") do
    out[#out + 1] = unescape(v:gsub("<!%[CDATA%[(.-)%]%]>", "%1"))
  end
  return out
end

-- Estrae <thumb ...>attr</thumb> con attributi vari
local function get_thumb(xml, kind)
  if not xml then return nil end
  -- <thumb aspect="poster">path</thumb>
  -- <thumb type="poster">path</thumb>
  for attrs, v in xml:gmatch("<thumb([^>]*)>(.-)</thumb>") do
    local a = attrs:lower()
    if not kind
       or a:find('aspect="' .. kind .. '"')
       or a:find('type="' .. kind .. '"')
       or a:find("aspect='" .. kind .. "'")
       or a:find("type='" .. kind .. "'") then
      return unescape(v)
    end
  end
  return nil
end

local IMG_EXT = { "jpg", "jpeg", "png", "webp", "tbn" }

local function find_side_image(dir, base, suffix)
  for _, e in ipairs(IMG_EXT) do
    local p = dir .. "/" .. base .. suffix .. "." .. e
    if exists(p) then return p end
  end
  return nil
end

local function find_folder_image(dir, names)
  for _, n in ipairs(names) do
    for _, e in ipairs(IMG_EXT) do
      local p = dir .. "/" .. n .. "." .. e
      if exists(p) then return p end
    end
  end
  return nil
end

function M.get(path)
  if not path or path == "" then return nil end
  local dir  = dirname(path)
  local base = strip_ext(basename(path))
  local meta = { path = path }

  -- 1. NFO (priorità 1: <base>.nfo)
  local nfo = read_file(dir .. "/" .. base .. ".nfo")
  if not nfo then
    nfo = read_file(dir .. "/movie.nfo")
  end
  if nfo then
    meta.title  = get_tag(nfo, "title")
    meta.plot   = get_tag(nfo, "plot") or get_tag(nfo, "outline")
    meta.year   = tonumber(get_tag(nfo, "year") or "")
    meta.rating = tonumber(get_tag(nfo, "rating") or "")
    meta.runtime= tonumber(get_tag(nfo, "runtime") or "")
    meta.studio = get_tag(nfo, "studio")
    meta.genre  = get_all(nfo, "genre")
    meta.actor  = get_all(nfo, "name")
    meta.tagline= get_tag(nfo, "tagline")
    local tp    = get_thumb(nfo, "poster") or get_thumb(nfo, nil)
    local tf    = get_thumb(nfo, "fanart") or get_thumb(nfo, "banner")
    if tp and tp ~= "" and not tp:match("^https?://") then
      if tp:sub(1, 1) ~= "/" then tp = dir .. "/" .. tp end
      if exists(tp) then meta.poster = tp end
    end
    if tf and tf ~= "" and not tf:match("^https?://") then
      if tf:sub(1, 1) ~= "/" then tf = dir .. "/" .. tf end
      if exists(tf) then meta.fanart = tf end
    end
  end

  -- 2. Immagini sidecar (priorità se NFO non le ha)
  if not meta.poster then
    meta.poster =
      find_side_image(dir, base, "-poster") or
      find_side_image(dir, base, "-cover")  or
      find_side_image(dir, base, "")        or
      find_folder_image(dir, { "poster", "folder", "cover" })
  end
  if not meta.fanart then
    meta.fanart =
      find_side_image(dir, base, "-fanart") or
      find_side_image(dir, base, "-background") or
      find_folder_image(dir, { "fanart", "background", "backdrop" })
  end
  if not meta.thumb then
    meta.thumb =
      find_side_image(dir, base, "-thumb") or
      find_side_image(dir, base, "-landscape")
  end

  return meta
end

return M
