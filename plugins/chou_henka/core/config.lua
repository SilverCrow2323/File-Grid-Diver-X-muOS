-- core/config.lua -- settings + defaults (JSON persistence)
local JSON = require("core.json")
local M = {}
M.PATH = "data/chou_henka_config.json"
M.defaults = {
  version = 3,
  ui = {
    theme = "neon", layout = "tiles",
    show_clock = true, show_stats = true, animations = true,
  },
  library = {
    auto_scan_boot = false, scan_max_depth = 6,
    exclude_hidden = true, min_size_kb = 32, group_by = "folder",
    disabled_categories = {},   -- { comic=true, image=true } => nascoste
    comic_handler = "comic_reader", -- comic_reader | gdx_library
  },
  player = {
    engine = "normal", volume = 70, speed = 100, gapless = true,
    video_vo = "sdl", video_hwdec = "auto", audio_ao = "alsa",
  },
  sources = {
    "/mnt/mmc/Music", "/mnt/mmc/Videos", "/mnt/mmc/Books",
    "/mnt/sdcard/Music", "/mnt/sdcard/Videos",
  },
  addons = { enabled = {} },
  scraper = {
    enabled = false,
    tmdb_api_key = "",
    prefer_local_nfo = true,
    fetch_posters = true,
  },
  watch = {
    resume_enabled = true,
    watched_threshold = 0.90,
    resume_min_pct = 0.02,
  },
}
local data = nil
local function dc(t)
  local c = {}
  for k, v in pairs(t) do c[k] = (type(v) == "table") and dc(v) or v end
  return c
end
local function mg(d, s)
  for k, v in pairs(s) do
    if type(v) == "table" and type(d[k]) == "table" then mg(d[k], v)
    else d[k] = v end
  end
end
function M.load()
  data = dc(M.defaults)
  local f = io.open(M.PATH, "r")
  if not f then return end
  local c = f:read("*a"); f:close()
  local ok, d = pcall(JSON.decode, c)
  if ok and type(d) == "table" then mg(data, d) end
end
function M.get(sec, key)
  if not data then M.load() end
  if not sec then return data end
  if key then return data[sec] and data[sec][key] end
  return data[sec]
end
function M.set(sec, key, value)
  if not data then M.load() end
  data[sec] = data[sec] or {}
  data[sec][key] = value
end
function M.set_sources(list)
  if not data then M.load() end
  data.sources = list or {}
  M.save()
end
function M.save()
  if not data then return end
  pcall(function() os.execute("mkdir -p data") end)
  local f = io.open(M.PATH, "w")
  if not f then return end
  local ok, s = pcall(JSON.encode, data)
  if ok then f:write(s) end
  f:close()
end
function M.reset() data = dc(M.defaults); M.save() end
M.load()
return M
