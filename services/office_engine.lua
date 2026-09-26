-- services/office_engine.lua -- DOCX / XLSX / PPTX text extractor.
-- DOCX: word/document.xml -> text runs
-- XLSX: sharedStrings + sheet1.xml -> table
-- PPTX: ppt/slides/slide*.xml -> per-slide text
local sh    = require("core.sh")
local HParse = require("services.html_parse")
local M     = {}

local function cache_root()
  local d = "/tmp/fgd_office"
  sh.exec("mkdir -p " .. sh.shq(d))
  return d
end

local function hash_of(path)
  local out = sh.read("md5sum " .. sh.shq(path) .. " 2>/dev/null | cut -d' ' -f1")
  return out and out:sub(1, 32) or tostring(os.time())
end

local function unzip_to(path, dir)
  if sh.is_dir(dir) then return true end
  sh.exec("mkdir -p " .. sh.shq(dir))
  if sh.exec("unzip -q -o " .. sh.shq(path) .. " -d " .. sh.shq(dir) .. " 2>/dev/null") == 0 then
    return true
  end
  return sh.exec("7z x -y -o" .. sh.shq(dir) .. " " .. sh.shq(path) .. " 2>/dev/null") == 0
end

local function xml_text(xml)
  -- Strip XML tags, decode entities, collapse whitespace.
  if not xml then return "" end
  local out = {}
  -- Preserve paragraph breaks
  xml = xml:gsub("</w:p>", "\n")
  xml = xml:gsub("</a:p>", "\n")
  xml = xml:gsub("<w:br[^>]*/>", "\n")
  xml = xml:gsub("<a:br[^>]*/>", "\n")
  -- Strip all remaining tags
  xml = xml:gsub("<[^>]->", "")
  -- Entities
  xml = xml:gsub("&lt;", "<"):gsub("&gt;", ">")
  xml = xml:gsub("&quot;", '"'):gsub("&apos;", "'")
  xml = xml:gsub("&amp;", "&")
  -- Collapse runs of spaces but keep newlines
  xml = xml:gsub("[ \t]+", " ")
  xml = xml:gsub("\n%s*\n", "\n\n")
  return xml
end

-- ============================================================
--  DOCX
-- ============================================================
function M.open_docx(path)
  local dir = cache_root() .. "/docx_" .. hash_of(path)
  if not unzip_to(path, dir) then return nil, "cannot unzip docx" end
  local f = io.open(dir .. "/word/document.xml", "r")
  if not f then return nil, "not a docx" end
  local xml = f:read("*a"); f:close()
  local txt = xml_text(xml)
  return {
    kind = "docx",
    path = path,
    text = txt,
  }
end

-- ============================================================
--  XLSX
-- ============================================================
local function parse_shared_strings(dir)
  local f = io.open(dir .. "/xl/sharedStrings.xml", "r")
  if not f then return {} end
  local xml = f:read("*a"); f:close()
  local strings = {}
  for si in xml:gmatch("<si>(.-)</si>") do
    local t = {}
    for m in si:gmatch("<t[^>]*>(.-)</t>") do t[#t+1] = m end
    strings[#strings+1] = table.concat(t)
  end
  return strings
end

function M.open_xlsx(path)
  local dir = cache_root() .. "/xlsx_" .. hash_of(path)
  if not unzip_to(path, dir) then return nil, "cannot unzip xlsx" end
  local strings = parse_shared_strings(dir)

  -- Find first sheet file
  local sheet_path = dir .. "/xl/worksheets/sheet1.xml"
  local f = io.open(sheet_path, "r")
  if not f then return nil, "cannot read sheet1.xml" end
  local xml = f:read("*a"); f:close()

  local rows = {}
  for row in xml:gmatch("<row[^>]*>(.-)</row>") do
    local cells = {}
    for cell in row:gmatch("<c[^>]*>(.-)</c>") do
      local v = cell:match("<v>(.-)</v>") or ""
      local t = cell:match('t="([^"]+)"') or ""
      if t == "s" then
        local idx = tonumber(v) or 0
        v = strings[idx + 1] or v
      elseif t == "inlineStr" then
        v = cell:match("<t[^>]*>(.-)</t>") or v
      end
      cells[#cells+1] = v
    end
    rows[#rows+1] = cells
  end

  return {
    kind = "xlsx",
    path = path,
    rows = rows,
  }
end

-- ============================================================
--  PPTX
-- ============================================================
function M.open_pptx(path)
  local dir = cache_root() .. "/pptx_" .. hash_of(path)
  if not unzip_to(path, dir) then return nil, "cannot unzip pptx" end
  local slides = {}
  local h = io.popen("ls " .. sh.shq(dir .. "/ppt/slides/slide*.xml") .. " 2>/dev/null | sort -V")
  if h then
    for path_slide in h:lines() do
      local f = io.open(path_slide, "r")
      if f then
        local xml = f:read("*a"); f:close()
        local txt = xml_text(xml)
        slides[#slides+1] = txt
      end
    end
    h:close()
  end
  return {
    kind = "pptx",
    path = path,
    slides = slides,
  }
end

-- ============================================================
--  Dispatcher
-- ============================================================
function M.open(path)
  local ext = path:match("%.([^.]+)$")
  ext = ext and ext:lower() or ""
  if ext == "docx" then return M.open_docx(path) end
  if ext == "xlsx" then return M.open_xlsx(path) end
  if ext == "pptx" then return M.open_pptx(path) end
  return nil, "unsupported office format: " .. ext
end

function M.is_supported(path)
  local ext = path:match("%.([^.]+)$")
  ext = ext and ext:lower() or ""
  return ext == "docx" or ext == "xlsx" or ext == "pptx"
end

return M
