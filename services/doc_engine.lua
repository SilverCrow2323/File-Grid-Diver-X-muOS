-- services/doc_engine.lua -- backend for GD-X Library.
-- PDF   via PyMuPDF (cached PNG per page)
-- EPUB  via unzip -> html_parse
-- CBZ   via unzip -> image list
-- CBR   via unrar / 7z -> image list
local sh     = require("core.sh")
local HParse = require("services.html_parse")
local JSON   = require("core.json")
local M      = {}

local function have(tool)
  local h = io.popen("command -v " .. tool .. " 2>/dev/null")
  if not h then return false end
  local r = h:read("*a") or ""
  h:close()
  return r ~= ""
end

-- IMPORTANTE: __pdf_prefix deve essere DEFINITA PRIMA di qualunque
-- chiamata, altrimenti in Lua la local e' nil.
local function __pdf_prefix()
  local cands = { "data/pdf_pack/lib", "data/pdf_pack",
                  "data/downloads/extracted" }
  for _, d in ipairs(cands) do
    local h = io.popen("test -d " .. sh.shq(d .. "/pymupdf") ..
      " && echo ok 2>/dev/null")
    if h then
      local o = h:read("*a") or ""
      h:close()
      if o:find("ok", 1, true) then
        return "PYTHONPATH=" .. sh.shq(d) .. " "
      end
    end
  end
  return ""
end

M.tools = {
  python3 = have("python3"),
  unzip   = have("unzip"),
  unrar   = have("unrar"),
  ["7z"]  = have("7z"),
}

M.tools.pymupdf = false
if M.tools.python3 then
  local out = sh.read(__pdf_prefix() ..
    "python3 -c 'import pymupdf; print(\"ok\")' 2>/dev/null")
  if not out or out == "" then
    out = sh.read(__pdf_prefix() ..
      "python3 -c 'import fitz; print(\"ok\")' 2>/dev/null")
  end
  M.tools.pymupdf = (out and out:find("ok", 1, true)) and true or false
end

local PY_HELPER = "tools/pdf_render.py"

local function cache_dir()
  local d = "/tmp/fgd_lib"
  sh.exec("mkdir -p " .. sh.shq(d))
  return d
end

local function hash_of(path)
  local out = sh.read("md5sum " .. sh.shq(path) .. " 2>/dev/null | cut -d' ' -f1")
  if out and #out >= 32 then return out:sub(1, 32) end
  return tostring(os.time())
end

-- ============================================================
--  PDF
-- ============================================================
local function pdf_pages(path)
  if not M.tools.pymupdf then return nil end
  local out = sh.read(__pdf_prefix() .. "python3 " .. sh.shq(PY_HELPER) .. " " ..
                      sh.shq(path) .. " info 2>/dev/null")
  if out then
    local n = tonumber(out:match("^(%d+)"))
    if n and n > 0 then return n end
  end
  return nil
end

local function pdf_render_page(path, page, dpi)
  dpi = dpi or 96
  if not M.tools.pymupdf then return nil end
  local h = hash_of(path)
  local dir = cache_dir() .. "/" .. h
  sh.exec("mkdir -p " .. sh.shq(dir))
  local png = dir .. "/p" .. string.format("%04d", page) .. ".png"
  if sh.exists(png) then return png end
  local cmd = __pdf_prefix() .. "python3 " .. sh.shq(PY_HELPER) .. " " ..
              sh.shq(path) .. " " .. page .. " " .. dpi .. " " ..
              sh.shq(png) .. " 2>/dev/null"
  if sh.exec(cmd) == 0 and sh.exists(png) then return png end
  return nil
end

-- API pubblica per il file manager: dice se PyMuPDF e'
-- importabile. Usa lo STESSO prefisso PYTHONPATH del resto
-- del modulo, cosi' non ci sono falsi negativi.
function M.pdf_available()
  return M.tools.pymupdf == true
end

function M.pdf_open(path)
  local pages = pdf_pages(path)
  if not pages then
    return nil, "cannot read PDF (install PDF Support plugin / PyMuPDF)"
  end
  return {
    kind    = "pdf",
    path    = path,
    pages   = pages,
    _render = pdf_render_page,
  }
end

function M.pdf_page(doc, page, dpi)
  return doc._render(doc.path, page, dpi)
end

-- ============================================================
--  EPUB
-- ============================================================
local function epub_extract(path)
  local h = hash_of(path)
  local dir = cache_dir() .. "/epub_" .. h
  if not sh.is_dir(dir) then
    sh.exec("mkdir -p " .. sh.shq(dir))
    if M.tools.unzip then
      sh.exec("unzip -q -o " .. sh.shq(path) .. " -d " .. sh.shq(dir) .. " 2>/dev/null")
    elseif M.tools["7z"] then
      sh.exec("7z x -y -o" .. sh.shq(dir) .. " " .. sh.shq(path) .. " 2>/dev/null")
    end
  end
  return dir
end

local function epub_spine(dir)
  local container = dir .. "/META-INF/container.xml"
  local f = io.open(container, "r")
  if not f then return nil end
  local c = f:read("*a"); f:close()
  local opf_path = c:match('full%-path="([^"]+)"')
  if not opf_path then return nil end
  local opf = dir .. "/" .. opf_path
  local f2 = io.open(opf, "r")
  if not f2 then return nil end
  local o = f2:read("*a"); f2:close()
  local base = opf_path:match("^(.*)/[^/]+$") or ""

  local manifest = {}
  for id, href in o:gmatch('<item[^>]-id="([^"]-)"[^>]-href="([^"]-)"') do
    manifest[id] = href
  end
  local order = {}
  for idref in o:gmatch('<itemref[^>]-idref="([^"]-)"') do
    local href = manifest[idref]
    if href then
      local full = (base == "" and href) or (base .. "/" .. href)
      order[#order+1] = full
    end
  end
  return order
end

function M.epub_open(path)
  local dir = epub_extract(path)
  local spine = epub_spine(dir)
  if not spine or #spine == 0 then
    return nil, "cannot read EPUB spine"
  end
  return { kind = "epub", path = path, dir = dir, spine = spine, page = 1 }
end

function M.epub_toc(doc)
  local toc = {}
  local dir = doc.dir

  local nav_paths = {
    dir .. "/OEBPS/nav.xhtml",
    dir .. "/nav.xhtml",
    dir .. "/EPUB/nav.xhtml",
    dir .. "/OPS/nav.xhtml",
  }
  for _, p in ipairs(nav_paths) do
    local f = io.open(p, "r")
    if f then
      local html = f:read("*a"); f:close()
      local in_toc = false
      for line in html:gmatch("[^\n]+") do
        if line:find('epub:type="toc"') then in_toc = true end
        if in_toc then
          for href, title in line:gmatch('<a[^>]-href="([^"]-)"[^>]*>(.-)</a>') do
            local clean = title:gsub("<[^>]->", ""):gsub("&amp;", "&")
              :gsub("&lt;", "<"):gsub("&gt;", ">")
            toc[#toc + 1] = { title = clean, href = href, level = 1 }
          end
          if line:find("</nav>") then in_toc = false end
        end
      end
      if #toc > 0 then break end
    end
  end

  if #toc == 0 then
    local ncx_paths = {
      dir .. "/toc.ncx",
      dir .. "/OEBPS/toc.ncx",
      dir .. "/EPUB/toc.ncx",
      dir .. "/OPS/toc.ncx",
    }
    for _, p in ipairs(ncx_paths) do
      local f = io.open(p, "r")
      if f then
        local xml = f:read("*a"); f:close()
        for block in xml:gmatch("<navPoint.-</navPoint>") do
          local label = block:match("<text>(.-)</text>") or "?"
          local src   = block:match('<content src="(.-)"') or ""
          label = label:gsub("&amp;", "&"):gsub("&lt;", "<"):gsub("&gt;", ">")
          toc[#toc + 1] = { title = label, href = src, level = 1 }
        end
        if #toc > 0 then break end
      end
    end
  end

  local function href_to_spine(href)
    if not href then return nil end
    href = href:gsub("^%./", "")
    for i, spine_href in ipairs(doc.spine) do
      local clean_spine = spine_href:gsub("^%./", "")
      if clean_spine == href or clean_spine:find(href, 1, true) then return i end
      local sp_base = clean_spine:match("([^/]+)$") or clean_spine
      local hr_base = href:match("([^/]+)$") or href
      if sp_base == hr_base then return i end
    end
    return nil
  end
  for _, item in ipairs(toc) do
    item.spine_idx = href_to_spine(item.href)
  end
  return toc
end

function M.epub_page(doc, idx)
  local rel = doc.spine[idx]
  if not rel then return nil end
  local full = doc.dir .. "/" .. rel
  local f = io.open(full, "r")
  if not f then
    return { { kind = "p", runs = { { text = "(missing: " .. rel .. ")" } } } }
  end
  local html = f:read("*a"); f:close()
  return HParse.parse(html)
end

-- ============================================================
--  CBZ / CBR / CB7
-- ============================================================
local IMG_EXTS = { png=true, jpg=true, jpeg=true, gif=true, webp=true, bmp=true }
local function is_img(name)
  local ext = name:match("%.([^.]+)$")
  if not ext then return false end
  return IMG_EXTS[ext:lower()] == true
end

local function list_cbz(path)
  local h = hash_of(path)
  local dir = cache_dir() .. "/cbz_" .. h
  if not sh.is_dir(dir) then
    sh.exec("mkdir -p " .. sh.shq(dir))
    if M.tools.unzip then
      sh.exec("unzip -q -o " .. sh.shq(path) .. " -d " .. sh.shq(dir) .. " 2>/dev/null")
    elseif M.tools["7z"] then
      sh.exec("7z x -y -o" .. sh.shq(dir) .. " " .. sh.shq(path) .. " 2>/dev/null")
    else
      return nil, "no unzip or 7z"
    end
  end
  local images = {}
  local h2 = io.popen("find " .. sh.shq(dir) .. " -type f 2>/dev/null | sort")
  if h2 then
    for line in h2:lines() do
      if is_img(line) then images[#images+1] = line end
    end
    h2:close()
  end
  return images
end

local function list_cbr(path)
  if M.tools.unrar then
    local out = sh.read("unrar lb " .. sh.shq(path) .. " 2>/dev/null")
    if out then
      local images = {}
      local h = hash_of(path)
      local dir = cache_dir() .. "/cbr_" .. h
      if not sh.is_dir(dir) then
        sh.exec("mkdir -p " .. sh.shq(dir))
        sh.exec("unrar x -o+ " .. sh.shq(path) .. " " .. sh.shq(dir) .. "/ 2>/dev/null")
      end
      local h2 = io.popen("find " .. sh.shq(dir) .. " -type f 2>/dev/null | sort")
      if h2 then
        for line in h2:lines() do
          if is_img(line) then images[#images+1] = line end
        end
        h2:close()
      end
      return images
    end
  end
  if M.tools["7z"] then
    local h = hash_of(path)
    local dir = cache_dir() .. "/cbr_" .. h
    if not sh.is_dir(dir) then
      sh.exec("mkdir -p " .. sh.shq(dir))
      sh.exec("7z x -y -o" .. sh.shq(dir) .. " " .. sh.shq(path) .. " 2>/dev/null")
    end
    local images = {}
    local h2 = io.popen("find " .. sh.shq(dir) .. " -type f 2>/dev/null | sort")
    if h2 then
      for line in h2:lines() do
        if is_img(line) then images[#images+1] = line end
      end
      h2:close()
    end
    return images
  end
  return nil, "no unrar or 7z"
end

function M.cbz_open(path)
  local ext = path:match("%.([^.]+)$")
  ext = ext and ext:lower() or ""
  local images, err
  if ext == "cbz" then images, err = list_cbz(path)
  elseif ext == "cbr" then images, err = list_cbr(path)
  elseif ext == "cb7" then images, err = list_cbz(path)
  end
  if not images then return nil, err or "cannot read" end
  if #images == 0 then return nil, "no images found" end
  return { kind = "cbz", path = path, images = images, page = 1 }
end

function M.cbz_image(doc, idx)
  return doc.images[idx]
end

-- ============================================================
--  Dispatcher
-- ============================================================
function M.open(path)
  local ext = path:match("%.([^.]+)$")
  ext = ext and ext:lower() or ""
  if ext == "pdf" then return M.pdf_open(path) end
  if ext == "epub" then return M.epub_open(path) end
  if ext == "cbz" or ext == "cbr" or ext == "cb7" then return M.cbz_open(path) end
  return nil, "unsupported format: " .. ext
end

function M.is_supported(path)
  local ext = path:match("%.([^.]+)$")
  ext = ext and ext:lower() or ""
  return ext == "pdf" or ext == "epub"
      or ext == "cbz" or ext == "cbr" or ext == "cb7"
end

return M
