-- core/external_image.lua -- load PNG/JPG from any absolute path.
-- LÖVE sandboxes love.filesystem; we read bytes ourselves and wrap.
local M = {}
local cache = {}

function M.load(path)
  if not path or path == "" then return nil end
  local c = cache[path]
  if c ~= nil then return c or nil end
  local f = io.open(path, "rb")
  if not f then cache[path] = false; return nil end
  local data = f:read("*a")
  f:close()
  if not data or #data == 0 then cache[path] = false; return nil end
  local name = path:match("([^/]+)$") or "img"
  local ok, fd = pcall(love.filesystem.newFileData, data, name)
  if not ok or not fd then cache[path] = false; return nil end
  local ok2, img = pcall(love.graphics.newImage, fd)
  if not ok2 or not img then cache[path] = false; return nil end
  img:setFilter("linear", "linear")
  cache[path] = img
  return img
end

function M.clear() cache = {} end

return M
