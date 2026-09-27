-- core/scraper.lua -- scraper opzionale (TMDB via curl).
-- Disabilitato di default. Attivalo in SETTINGS e fornisci una API key.
-- Se non hai API key, il metadata viene comunque letto da .nfo e sidecar.
local sh = require("core.sh")
local JSON = require("core.json")
local CFG = require("plugins.chou_henka.core.config")
local M = {}

M.CACHE_DIR = "data/chou_henka_scraper"

local function cache_path(kind, tmdb_id)
  return M.CACHE_DIR .. "/" .. kind .. "_" .. tostring(tmdb_id) .. ".json"
end

local function curl(url, out)
  sh.exec("mkdir -p " .. sh.shq(M.CACHE_DIR))
  local cmd = "curl -sL --max-time 8 -o " .. sh.shq(out) .. " " .. sh.shq(url)
  return sh.exec(cmd) == 0 and sh.exists(out)
end

function M.enabled()
  return CFG.get("scraper", "enabled") == true
end

function M.api_key()
  return CFG.get("scraper", "tmdb_api_key") or ""
end

function M.available()
  if not M.enabled() then return false, "scraper disabled" end
  if M.api_key() == "" then return false, "no TMDB API key" end
  if sh.exec("command -v curl >/dev/null 2>&1") ~= 0 then
    return false, "curl not installed"
  end
  return true
end

-- Cerca un film su TMDB. Ritorna tabella o nil, err.
function M.search_movie(query, year)
  local ok, err = M.available()
  if not ok then return nil, err end
  local q = query:gsub("[^%w%s]", "")
  q = q:gsub("%s+", "+")
  local url = "https://api.themoviedb.org/3/search/movie?api_key=" ..
    M.api_key() .. "&query=" .. q ..
    (year and ("&year=" .. tostring(year)) or "")
  local tmp = "/tmp/ch_tmdb_search.json"
  if not curl(url, tmp) then return nil, "network error" end
  local f = io.open(tmp, "r")
  if not f then return nil, "no response" end
  local c = f:read("*a"); f:close()
  os.remove(tmp)
  local j = JSON.decode(c)
  if not j or not j.results or #j.results == 0 then return nil, "not found" end
  return j.results[1]
end

-- Applica metadata da TMDB a un item (in memoria).
function M.apply_tmdb(item)
  if not item or not item.path then return false end
  local base = item.name:gsub("%.[^.]+$", ""):gsub("%b()", "")
  base = base:gsub("20%d%d", ""):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
  local year = tonumber((item.name:match("(%d%d%d%d)")))
  local res, err = M.search_movie(base, year)
  if not res then return false, err end
  item.title  = res.title or item.name
  item.plot   = res.overview or ""
  item.year   = tonumber((res.release_date or ""):match("^(%d%d%d%d)")) or item.year
  item.rating = res.vote_average
  if res.poster_path then
    item.poster_remote = "https://image.tmdb.org/t/p/w300" .. res.poster_path
  end
  if res.backdrop_path then
    item.fanart_remote = "https://image.tmdb.org/t/p/w780" .. res.backdrop_path
  end
  return true
end

-- Scarica immagine remota in cache locale.
function M.fetch_image(url, dest)
  if not url or url == "" then return nil end
  if sh.exists(dest) then return dest end
  sh.exec("mkdir -p " .. sh.shq((dest:match("^(.*)/[^/]+$") or ".")))
  if curl(url, dest) then return dest end
  return nil
end

return M
