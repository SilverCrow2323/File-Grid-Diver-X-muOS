-- services/bookmarks.lua -- persistent user lists:
-- bookmarks (user-saved paths), recent files, favorites (starred).
local JSON = require("core.json")
local M = {}

local FILE = "data/bookmarks.json"
local MAX_RECENT = 60
local MAX_BOOKMARKS = 30

local function load()
  local f = io.open(FILE, "r")
  if not f then return { bookmarks = {}, recent = {}, favorites = {} } end
  local c = f:read("*a"); f:close()
  local ok, d = pcall(JSON.decode, c)
  if ok and type(d) == "table" then
    d.bookmarks = d.bookmarks or {}
    d.recent    = d.recent or {}
    d.favorites = d.favorites or {}
    return d
  end
  return { bookmarks = {}, recent = {}, favorites = {} }
end

local function save(d)
  os.execute("mkdir -p data")
  local f = io.open(FILE, "w")
  if not f then return false end
  f:write(JSON.encode(d)); f:close()
  return true
end

local function remove_from(list, item)
  for i = #list, 1, -1 do
    if list[i] == item then table.remove(list, i) end
  end
end

function M.bookmarks() return load().bookmarks end
function M.recent()    return load().recent    end
function M.favorites() return load().favorites end

function M.add_bookmark(path)
  if not path or path == "" then return end
  local d = load()
  remove_from(d.bookmarks, path)
  table.insert(d.bookmarks, 1, path)
  if #d.bookmarks > MAX_BOOKMARKS then table.remove(d.bookmarks) end
  save(d)
end

function M.remove_bookmark(path)
  local d = load(); remove_from(d.bookmarks, path); save(d)
end

function M.add_recent(path)
  if not path or path == "" then return end
  local d = load()
  remove_from(d.recent, path)
  table.insert(d.recent, 1, path)
  if #d.recent > MAX_RECENT then table.remove(d.recent) end
  save(d)
end

function M.clear_recent()
  save({ bookmarks = load().bookmarks, recent = {}, favorites = load().favorites })
end

function M.remove_recent(path)
  if not path or path == "" then return end
  local d = load()
  remove_from(d.recent, path)
  save(d)
end

function M.toggle_favorite(path)
  if not path or path == "" then return false end
  local d = load()
  local has = false
  for i, p in ipairs(d.favorites) do
    if p == path then table.remove(d.favorites, i); has = true; break end
  end
  if not has then table.insert(d.favorites, 1, path) end
  save(d)
  return not has
end

function M.is_favorite(path)
  for _, p in ipairs(load().favorites) do
    if p == path then return true end
  end
  return false
end

-- ============================================================
--  Reader bookmarks (PDF / EPUB / Comic / HTML)
-- ============================================================
-- Stored under a separate key in the JSON: { readers = { path = {...} } }
-- Each entry: { page = N, scroll = S, ts = timestamp }

local function load_readers()
  local d = load()
  d.readers = d.readers or {}
  return d
end

local function save_readers(d)
  save(d)
end

function M.reader_get(path)
  if not path or path == "" then return nil end
  local d = load_readers()
  return d.readers[path]
end

function M.reader_set(path, page, scroll)
  if not path or path == "" then return end
  local d = load_readers()
  d.readers[path] = {
    page = page or 1,
    scroll = scroll or 0,
    ts = os.time(),
  }
  save_readers(d)
end

function M.reader_clear(path)
  local d = load_readers()
  d.readers[path] = nil
  save_readers(d)
end

-- Reader "pinned" list: important files the user wants to keep
function M.reader_pinned_list()
  local d = load_readers()
  local out = {}
  for path, info in pairs(d.readers) do
    out[#out + 1] = { path = path, page = info.page, scroll = info.scroll, ts = info.ts }
  end
  table.sort(out, function(a, b) return (a.ts or 0) > (b.ts or 0) end)
  return out
end

return M
