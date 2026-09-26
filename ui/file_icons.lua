-- ui/file_icons.lua -- comprehensive file type icon renderer.
-- Every category has its own colour and glyph. Special paths
-- (/mnt/mmc, /mnt/sdcard, $HOME, /) get dedicated mount icons.

local A = require("core.assets")

local F = {}

-- =============================================================
--  Extension -> category
-- =============================================================
local EXT = {
  -- images
  png="image", jpg="image", jpeg="image", webp="image", bmp="image",
  gif="image", tiff="image", tif="image", svg="image", ico="image",
  heic="image", avif="image",
  -- audio
  mp3="audio", ogg="audio", oga="audio", wav="audio", flac="audio",
  opus="audio", m4a="audio", aac="audio", wma="audio", ape="audio",
  mid="audio", midi="audio", mod="audio", s3m="audio", xm="audio",
  it="audio",
  -- video
  mp4="video", mkv="video", avi="video", webm="video", mov="video",
  mpg="video", mpeg="video", m4v="video", flv="video", wmv="video",
  ["3gp"]="video", ogv="video", ts="video", m2ts="video",
  -- text
  txt="text", md="text", markdown="text", log="text", rtf="text",
  -- code
  lua="code", py="code", sh="code", bash="code", zsh="code",
  js="code", ts="code", jsx="code", tsx="code",
  c="code", h="code", cpp="code", cxx="code", hpp="code",
  java="code", rb="code", go="code", rs="code", php="code",
  pl="code", swift="code", kt="code",
  -- web
  html="web", htm="web", css="web", scss="web", sass="web", less="web",
  -- config
  json="config", xml="config", yaml="config", yml="config",
  ini="config", conf="config", cfg="config", toml="config",
  gptk="config", desktop="config", service="config",
  -- archives
  zip="archive", rar="archive", ["7z"]="archive", tar="archive",
  gz="archive", bz2="archive", xz="archive", tgz="archive",
  lz4="archive", zst="archive", lzma="archive", cab="archive",
  arj="archive", zipx="archive",
  -- ROMs
  iso="rom", gcm="rom", rvz="rom", wbfs="rom", wia="rom",
  ciso="rom", nkit="rom", gcz="rom",
  nes="rom", snes="rom", smc="rom", gba="rom", gbc="rom", gb="rom",
  nds="rom", cso="rom", ["3ds"]="rom", cia="rom", xci="rom",
  nsp="rom", nro="rom", pbp="rom", chd="rom", cue="rom", bin="rom",
  m3u="rom", pce="rom", gen="rom", smd="rom", ["32x"]="rom",
  z64="rom", n64="rom", v64="rom", rom="rom",
  a26="rom", a52="rom", a78="rom", col="rom", int="rom", vec="rom",
  d64="rom", tap="rom", dsk="rom", adf="rom", st="rom", ipf="rom",
  -- saves
  sav="save", srm="save", state="save",
  st0="save", st1="save", st2="save", st3="save", st4="save",
  st5="save", st6="save", st7="save", st8="save", st9="save",
  mpk="save", eep="save", fla="save",
  -- executables
  elf="exe", deb="exe", ipk="exe", appimage="exe", exe="exe",
  msi="exe", dmg="exe", apk="exe",
  so="lib", dll="lib", ko="lib",
  -- fonts
  ttf="font", otf="font", woff="font", woff2="font", eot="font",
  -- documents
  pdf="doc", doc="doc", docx="doc", xls="doc", xlsx="doc",
  ppt="doc", pptx="doc", odt="doc", ods="doc", odp="doc",
  epub="doc", mobi="doc",
  -- muOS packages
  muxapp="muos", muxzip="muos", muxupd="muos", muxthm="muos",
  muxrom="muos", muxscript="muos", muxcfg="muos", muxpack="muos",
  -- disk images
  img="disk", vhd="disk", vmdk="disk", qcow2="disk",
  -- scripts
  bat="script", cmd="script", ps1="script", vbs="script",
}

-- =============================================================
--  Special paths -> mount icon
-- =============================================================
local function home_path()
  return os.getenv("HOME") or "/tmp"
end

local function special_for(path)
  if not path or path == "" then return nil end
  if path == "/" then return "root" end
  if path == "/mnt/mmc" then return "sd1" end
  if path == "/mnt/sdcard" then return "sd2" end
  if path == "/tmp" then return "temp" end
  if path == home_path() then return "home" end
  if path:match("^/mnt/usb") or path:match("^/media/") then return "usb" end
  return nil
end

-- =============================================================
--  Colours per category
-- =============================================================
local COLORS = {
  dir     = {0.94, 0.66, 0.35},
  root    = {0.85, 0.82, 0.76},
  sd1     = {0.94, 0.66, 0.35},
  sd2     = {0.85, 0.42, 0.42},
  temp    = {0.60, 0.60, 0.70},
  home    = {0.55, 0.72, 0.50},
  usb     = {0.55, 0.72, 0.50},
  image   = {0.29, 0.62, 0.72},
  audio   = {0.90, 0.55, 0.35},
  video   = {0.85, 0.42, 0.42},
  text    = {0.55, 0.72, 0.50},
  code    = {0.40, 0.72, 0.72},
  web     = {0.90, 0.70, 0.30},
  config  = {0.55, 0.55, 0.85},
  archive = {0.60, 0.50, 0.80},
  rom     = {0.42, 0.72, 0.90},
  save    = {0.55, 0.85, 0.55},
  exe     = {0.85, 0.82, 0.76},
  lib     = {0.60, 0.55, 0.50},
  font    = {0.90, 0.55, 0.80},
  doc     = {0.85, 0.45, 0.55},
  muos    = {0.30, 0.85, 0.90},
  disk    = {0.60, 0.60, 0.60},
  script  = {0.90, 0.75, 0.40},
  unknown = {0.44, 0.42, 0.38},
}

-- =============================================================
--  Get spec
-- =============================================================
function F.get(entry, cwd)
  if not entry then return { cat = "unknown", shape = "unknown" } end

  if entry.is_parent then
    return { cat = "dir", shape = "folder_up" }
  end

  if entry.is_dir then
    local sp = special_for(entry.path)
    if sp then return { cat = sp, shape = sp } end
    return { cat = "dir", shape = "folder" }
  end

  local name = entry.name or ""
  local ext = name:match("%.([^%.]+)$")
  if ext then ext = ext:lower() end
  local cat = (ext and EXT[ext]) or "unknown"

  -- short name specials
  if name == "README" or name == "README.md" then
    cat = "text"
  elseif name:match("^%.gitignore") or name:match("^%.git") then
    cat = "config"
  end

  return { cat = cat, shape = cat, ext = ext }
end

-- =============================================================
--  Drawing
-- =============================================================
local function setcol(c, a)
  love.graphics.setColor(c[1], c[2], c[3], a or 1)
end

local function hex_disc(cx, cy, r, col, alpha)
  setcol(col, alpha * 0.22)
  local hex = {}
  for i = 0, 5 do
    local a = -math.pi / 2 + i * math.pi / 3
    hex[#hex + 1] = cx + math.cos(a) * r
    hex[#hex + 1] = cy + math.sin(a) * r
  end
  love.graphics.polygon("fill", hex)
  setcol(col, alpha)
  love.graphics.setLineWidth(1.4)
  love.graphics.polygon("line", hex)
  love.graphics.setLineWidth(1)
end

-- Small letters rendered as flat text
local function letter(cx, cy, text, col, alpha, size)
  local f = A.font(A.FONT_BODY_BOLD, size or 10)
  love.graphics.setFont(f)
  setcol(col, alpha)
  local w = f:getWidth(text)
  love.graphics.print(text, cx - w / 2, cy - f:getHeight() / 2)
end

-- Draw a small SD-card glyph (rect with notched corner + number)
local function draw_sd(cx, cy, r, num, col, alpha)
  local w, h = r * 1.5, r * 1.8
  local x, y = cx - w / 2, cy - h / 2
  setcol(col, alpha)
  -- body
  local cut = r * 0.35
  love.graphics.polygon("line",
    x, y,
    x + w - cut, y,
    x + w, y + cut,
    x + w, y + h,
    x, y + h)
  -- contact pins
  love.graphics.setLineWidth(1)
  for i = 0, 3 do
    local px = x + w - cut + 2 + i * (cut / 4)
    love.graphics.line(px, y + 2, px, y + cut * 0.5)
  end
  -- number
  letter(cx - 1, cy + 1, tostring(num), col, alpha, math.floor(r * 1.0))
end

-- muOS badge: rounded rect with "mu" monogram
local function draw_muos(cx, cy, r, col, alpha)
  local w, h = r * 1.7, r * 1.6
  local x, y = cx - w / 2, cy - h / 2
  setcol(col, alpha)
  love.graphics.setLineWidth(1.6)
  love.graphics.rectangle("line", x, y, w, h, 3, 3)
  -- inner "mu" text
  local f = A.font(A.FONT_BODY_BOLD, math.floor(r * 1.1))
  love.graphics.setFont(f)
  local txt = "mu"
  local tw = f:getWidth(txt)
  love.graphics.print(txt, cx - tw / 2, cy - f:getHeight() / 2)
  -- accent bar
  love.graphics.rectangle("fill", x + 2, y + h - 4, w - 4, 2)
end

local function draw_shape(shape, cx, cy, r, col, alpha)
  local g = r * 0.55

  setcol(col, alpha)
  love.graphics.setLineWidth(1.4)

  if shape == "folder" or shape == "folder_up" then
    love.graphics.rectangle("line", cx - g, cy - g * 0.5, g * 2, g * 1.2)
    love.graphics.rectangle("fill", cx - g, cy - g * 0.9, g * 0.8, g * 0.5)
    if shape == "folder_up" then
      love.graphics.setLineWidth(1.6)
      love.graphics.line(cx, cy + g * 0.3, cx, cy - g * 0.3)
      love.graphics.line(cx, cy - g * 0.3, cx - g * 0.4, cy + g * 0.1)
      love.graphics.line(cx, cy - g * 0.3, cx + g * 0.4, cy + g * 0.1)
    end
  elseif shape == "sd1" then
    draw_sd(cx, cy, r, 1, col, alpha)
  elseif shape == "sd2" then
    draw_sd(cx, cy, r, 2, col, alpha)
  elseif shape == "root" then
    love.graphics.circle("line", cx, cy, g * 0.9)
    love.graphics.line(cx, cy - g * 0.9, cx, cy + g * 0.9)
    love.graphics.line(cx - g * 0.9, cy, cx + g * 0.9, cy)
  elseif shape == "home" then
    love.graphics.polygon("line",
      cx, cy - g * 0.9,
      cx + g * 0.9, cy - g * 0.1,
      cx + g * 0.5, cy - g * 0.1,
      cx + g * 0.5, cy + g * 0.9,
      cx - g * 0.5, cy + g * 0.9,
      cx - g * 0.5, cy - g * 0.1,
      cx - g * 0.9, cy - g * 0.1)
    love.graphics.rectangle("line", cx - g * 0.2, cy + g * 0.3,
      g * 0.4, g * 0.6)
  elseif shape == "temp" then
    love.graphics.rectangle("line", cx - g * 0.8, cy - g * 0.8,
      g * 1.6, g * 1.6)
    love.graphics.circle("line", cx, cy, g * 0.35)
    love.graphics.line(cx - g * 0.8, cy - g * 0.8,
      cx + g * 0.8, cy + g * 0.8)
  elseif shape == "usb" then
    love.graphics.rectangle("line", cx - g * 0.4, cy - g * 0.9,
      g * 0.8, g * 0.9)
    love.graphics.rectangle("line", cx - g * 0.6, cy,
      g * 1.2, g * 0.8)
    love.graphics.rectangle("fill", cx - g * 0.1, cy + g * 0.3,
      g * 0.2, g * 0.6)
  elseif shape == "image" then
    love.graphics.rectangle("line", cx - g, cy - g * 0.8, g * 2, g * 1.6)
    love.graphics.circle("fill", cx + g * 0.4, cy - g * 0.3, g * 0.2)
    love.graphics.polygon("fill",
      cx - g * 0.7, cy + g * 0.6,
      cx - g * 0.1, cy - g * 0.1,
      cx + g * 0.6, cy + g * 0.6)
  elseif shape == "audio" then
    love.graphics.circle("line", cx - g * 0.35, cy + g * 0.4, g * 0.4)
    love.graphics.line(cx + g * 0.05, cy + g * 0.4, cx + g * 0.05, cy - g * 0.8)
    love.graphics.line(cx + g * 0.05, cy - g * 0.8, cx + g * 0.7, cy - g * 0.6)
  elseif shape == "video" then
    love.graphics.rectangle("line", cx - g, cy - g * 0.7, g * 2, g * 1.4)
    love.graphics.polygon("fill",
      cx - g * 0.2, cy - g * 0.4,
      cx + g * 0.5, cy,
      cx - g * 0.2, cy + g * 0.4)
  elseif shape == "text" then
    for i = -1, 1 do
      love.graphics.line(cx - g, cy + i * g * 0.45,
                         cx + g, cy + i * g * 0.45)
    end
  elseif shape == "code" then
    -- < > pair
    love.graphics.line(cx - g * 0.6, cy - g * 0.5,
                       cx - g, cy,
                       cx - g * 0.6, cy + g * 0.5)
    love.graphics.line(cx + g * 0.6, cy - g * 0.5,
                       cx + g, cy,
                       cx + g * 0.6, cy + g * 0.5)
    love.graphics.line(cx - g * 0.15, cy + g * 0.5,
                       cx + g * 0.15, cy - g * 0.5)
  elseif shape == "web" then
    love.graphics.circle("line", cx, cy, g * 0.9)
    love.graphics.ellipse("line", cx, cy, g * 0.9, g * 0.4)
    love.graphics.line(cx, cy - g * 0.9, cx, cy + g * 0.9)
    love.graphics.line(cx - g * 0.9, cy, cx + g * 0.9, cy)
  elseif shape == "config" then
    -- gear
    for i = 0, 7 do
      local a = i * math.pi / 4
      love.graphics.line(cx + math.cos(a) * g * 0.6,
                         cy + math.sin(a) * g * 0.6,
                         cx + math.cos(a) * g * 0.9,
                         cy + math.sin(a) * g * 0.9)
    end
    love.graphics.circle("line", cx, cy, g * 0.55)
    love.graphics.circle("line", cx, cy, g * 0.25)
  elseif shape == "archive" then
    love.graphics.rectangle("line", cx - g * 0.8, cy - g,
                            g * 1.6, g * 2)
    -- zipper
    love.graphics.line(cx, cy - g, cx, cy - g * 0.2)
    love.graphics.rectangle("fill", cx - g * 0.1, cy - g * 0.4,
      g * 0.2, g * 0.15)
    love.graphics.rectangle("fill", cx - g * 0.1, cy - g * 0.1,
      g * 0.2, g * 0.15)
  elseif shape == "rom" then
    -- game cartridge
    love.graphics.rectangle("line", cx - g * 0.8, cy - g * 0.9,
      g * 1.6, g * 1.8)
    love.graphics.rectangle("fill", cx - g * 0.6, cy - g * 0.9,
      g * 1.2, g * 0.3)
    love.graphics.rectangle("line", cx - g * 0.5, cy - g * 0.3,
      g, g * 0.8)
  elseif shape == "save" then
    -- floppy disk shape
    love.graphics.rectangle("line", cx - g, cy - g, g * 2, g * 2)
    love.graphics.rectangle("line", cx - g * 0.6, cy - g,
      g * 1.2, g * 0.7)
    love.graphics.rectangle("line", cx - g * 0.5, cy + g * 0.2,
      g, g * 0.8)
  elseif shape == "exe" then
    love.graphics.circle("line", cx, cy, g * 0.8)
    love.graphics.circle("line", cx, cy, g * 0.35)
    love.graphics.line(cx - g * 0.8, cy, cx + g * 0.8, cy)
    love.graphics.line(cx, cy - g * 0.8, cx, cy + g * 0.8)
  elseif shape == "lib" then
    love.graphics.rectangle("line", cx - g * 0.7, cy - g * 0.6,
      g * 1.4, g * 1.2)
    love.graphics.rectangle("fill", cx - g * 0.3, cy - g * 0.2,
      g * 0.2, g * 0.4)
    love.graphics.rectangle("fill", cx + g * 0.1, cy - g * 0.2,
      g * 0.2, g * 0.4)
  elseif shape == "font" then
    letter(cx, cy, "A", col, alpha, math.floor(r * 1.1))
  elseif shape == "doc" then
    -- page with folded corner
    love.graphics.line(cx - g * 0.7, cy - g, cx + g * 0.4, cy - g)
    love.graphics.line(cx + g * 0.4, cy - g, cx + g * 0.7, cy - g * 0.7)
    love.graphics.line(cx + g * 0.7, cy - g * 0.7, cx + g * 0.7, cy + g)
    love.graphics.line(cx + g * 0.7, cy + g, cx - g * 0.7, cy + g)
    love.graphics.line(cx - g * 0.7, cy + g, cx - g * 0.7, cy - g)
    love.graphics.line(cx + g * 0.4, cy - g, cx + g * 0.4, cy - g * 0.7)
    love.graphics.line(cx + g * 0.4, cy - g * 0.7, cx + g * 0.7, cy - g * 0.7)
    for i = 0, 2 do
      love.graphics.line(cx - g * 0.4, cy - g * 0.3 + i * g * 0.4,
                         cx + g * 0.4, cy - g * 0.3 + i * g * 0.4)
    end
  elseif shape == "muos" then
    draw_muos(cx, cy, r, col, alpha)
  elseif shape == "disk" then
    love.graphics.ellipse("line", cx, cy, g * 0.9, g * 0.5)
    love.graphics.ellipse("line", cx, cy, g * 0.9, g * 0.5)
    love.graphics.line(cx, cy - g * 0.5, cx, cy + g * 0.5)
    love.graphics.circle("fill", cx, cy, g * 0.15)
  elseif shape == "script" then
    letter(cx, cy, "$", col, alpha, math.floor(r * 1.3))
  else
    -- unknown: page + dot
    love.graphics.rectangle("line", cx - g * 0.6, cy - g * 0.8,
      g * 1.2, g * 1.6)
    love.graphics.line(cx - g * 0.3, cy - g * 0.3,
                       cx + g * 0.3, cy - g * 0.3)
    love.graphics.line(cx - g * 0.3, cy + 0.1,
                       cx + g * 0.3, cy + 0.1)
  end

  love.graphics.setLineWidth(1)
end

function F.draw(spec, cx, cy, r, alpha)
  if not spec then spec = { cat = "unknown", shape = "unknown" } end
  local col = COLORS[spec.cat] or COLORS.unknown
  hex_disc(cx, cy, r, col, alpha)
  draw_shape(spec.shape, cx, cy, r, col, alpha)
end

-- Colours for external use (grid view name colour, etc.)
function F.color_for(spec)
  if not spec then return COLORS.unknown end
  return COLORS[spec.cat] or COLORS.unknown
end

return F
