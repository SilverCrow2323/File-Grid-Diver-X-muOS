-- core/assets.lua -- fonts and images, with runtime font scale/family.
local M = { fonts = {}, images = {}, ready = false }

M.FONT_TITLE      = "assets/fonts/Oxanium-Bold.ttf"
M.FONT_TITLE_ALT  = "assets/fonts/Oxanium-Bold.ttf"
M.FONT_BODY       = "assets/fonts/Oxanium-Regular.ttf"
M.FONT_BODY_BOLD  = "assets/fonts/Oxanium-Bold.ttf"
M.FONT_MONO       = "assets/fonts/JetBrainsMono-Regular.ttf"

M._scale  = 1.0
M._family = "auto"

-- Called every frame from main.lua love.update (cheap).
function M.sync()
  local ok, Store = pcall(require, "core.settings_store")
  if not ok then return end
  M._scale  = Store.get("ui", "font_scale")  or 1.0
  M._family = Store.get("ui", "font_family") or "auto"
end

function M.set_scale(s) M._scale = s end
function M.set_family(f) M._family = f end

local function pick(path)
  -- Override with family selection when not "auto".
  if M._family == "auto" or not M._family then return path end
  if M._family == "default"  then return nil end
  if M._family == "orbitron" then return "assets/fonts/Orbitron-Bold.ttf" end
  if M._family == "oxanium"  then
    -- keep bold vs regular distinction using the requested path
    if path == M.FONT_BODY then return "assets/fonts/Oxanium-Regular.ttf" end
    return "assets/fonts/Oxanium-Bold.ttf"
  end
  if M._family == "mono"     then return "assets/fonts/JetBrainsMono-Regular.ttf" end
  return path
end

local function try_new_font(path, size)
  if path and path ~= "" then
    local ok, fnt = pcall(love.graphics.newFont, path, size)
    if ok and fnt then return fnt end
  end
  local ok, fnt = pcall(love.graphics.newFont, size)
  if ok and fnt then return fnt end
  return love.graphics.getFont()
end

-- Scaled font (used by screens). Scales with M._scale.
function M.font(path, size)
  size = math.max(10, math.floor((size or 12) * M._scale + 0.5))
  local real_path = pick(path)
  local key = tostring(real_path or "default") .. "@" .. size
  if M.fonts[key] == nil then
    local fnt = try_new_font(real_path, size)
    if fnt and fnt.setFilter then fnt:setFilter("linear", "linear") end
    M.fonts[key] = fnt
  end
  return M.fonts[key]
end

-- Raw font (used by header/footer which scale with their own thickness).
function M.font_raw(path, size)
  size = math.max(10, math.floor(size or 12))
  local real_path = pick(path)
  local key = "raw:" .. tostring(real_path or "default") .. "@" .. size
  if M.fonts[key] == nil then
    local fnt = try_new_font(real_path, size)
    if fnt and fnt.setFilter then fnt:setFilter("linear", "linear") end
    M.fonts[key] = fnt
  end
  return M.fonts[key]
end

function M.title_font(size) return M.font(M.FONT_TITLE, size) end

function M.clear_cache()
  M.fonts = {}
end

function M.image(path)
  if not path or path == "" then return nil end
  if M.images[path] == nil then
    local ok, img = pcall(love.graphics.newImage, path)
    if ok and img then
      img:setFilter("linear", "linear")
      M.images[path] = img
    else
      M.images[path] = false
    end
  end
  return M.images[path] or nil
end

function M.init() M.ready = true end

return M
