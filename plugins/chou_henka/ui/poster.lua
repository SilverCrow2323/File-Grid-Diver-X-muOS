-- ui/poster.lua -- cache poster/fanart, caricati via external_image.
-- Ritorna una love.Image o nil. Cache LRU soft con cap massimo.
local ExtImg = require("core.external_image")

local M = {}
local cache = {}
local lru = {}
local CAP = 40
local MISS = false

local function touch(key)
  for i, k in ipairs(lru) do
    if k == key then table.remove(lru, i); break end
  end
  table.insert(lru, key)
end

local function evict()
  while #lru > CAP do
    local old = table.remove(lru, 1)
    local img = cache[old]
    if img and img.release and img ~= MISS then
      pcall(function() img:release() end)
    end
    cache[old] = nil
  end
end

function M.get(path)
  if not path or path == "" then return nil end
  local c = cache[path]
  if c ~= nil then
    if c == MISS then return nil end
    touch(path)
    return c
  end
  local img = ExtImg.load(path)
  if img then
    cache[path] = img
    touch(path)
    evict()
    return img
  end
  cache[path] = MISS
  return nil
end

function M.clear()
  for _, img in pairs(cache) do
    if img and img ~= MISS and img.release then
      pcall(function() img:release() end)
    end
  end
  cache = {}
  lru = {}
end

function M.stats()
  local n = 0
  for _ in pairs(cache) do n = n + 1 end
  return n, CAP
end

return M
