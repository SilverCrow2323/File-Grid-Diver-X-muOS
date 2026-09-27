-- core/watchstate.lua -- resume, watched, favorites, recent.
-- Un unico JSON: data/chou_henka_state.json
local JSON = require("core.json")
local sh   = require("core.sh")
local M    = {}

M.PATH = "data/chou_henka_state.json"
local db = nil

local function fresh()
  return {
    resume    = {},   -- [path] = {pos=, dur=, ts=, pct=}
    watched   = {},   -- [path] = ts
    favorites = {},   -- [path] = ts
    recent    = {},   -- array ordinato di {path, ts}
    version   = 1,
  }
end

function M.load()
  db = fresh()
  local f = io.open(M.PATH, "r")
  if not f then return end
  local c = f:read("*a"); f:close()
  local ok, d = pcall(JSON.decode, c)
  if ok and type(d) == "table" then
    db.resume    = d.resume    or {}
    db.watched   = d.watched   or {}
    db.favorites = d.favorites or {}
    db.recent    = d.recent    or {}
  end
end

function M.save()
  if not db then return end
  sh.exec("mkdir -p data")
  local f = io.open(M.PATH, "w")
  if not f then return end
  local ok, s = pcall(JSON.encode, db)
  if ok then f:write(s) end
  f:close()
end

function M.reset()
  db = fresh()
  M.save()
end

-- ── Resume ───────────────────────────────────────────────────
function M.set_resume(path, pos, dur)
  if not db then M.load() end
  if not path or not pos then return end
  if not dur or dur <= 0 then dur = 0 end
  local pct = (dur > 0) and (pos / dur) or 0
  -- Se > 95% trattalo come watched, non resume
  if pct >= 0.95 then
    M.mark_watched(path)
    M.clear_resume(path)
    return
  end
  -- Se < 2% non ha senso
  if pct < 0.02 then
    M.clear_resume(path)
    return
  end
  db.resume[path] = { pos = pos, dur = dur, ts = os.time(), pct = pct }
  -- touch recent
  M.touch_recent(path)
end

function M.get_resume(path)
  if not db then M.load() end
  return db.resume[path]
end

function M.clear_resume(path)
  if not db then M.load() end
  if db.resume[path] then
    db.resume[path] = nil
    M.save()
  end
end

-- ── Watched ──────────────────────────────────────────────────
function M.mark_watched(path)
  if not db then M.load() end
  if not path then return end
  db.watched[path] = os.time()
  M.save()
end

function M.mark_unwatched(path)
  if not db then M.load() end
  if db.watched[path] then
    db.watched[path] = nil
    M.save()
  end
end

function M.is_watched(path)
  if not db then M.load() end
  return db.watched[path] ~= nil
end

function M.toggle_watched(path)
  if M.is_watched(path) then M.mark_unwatched(path)
  else M.mark_watched(path) end
  return M.is_watched(path)
end

-- ── Favorites ────────────────────────────────────────────────
function M.is_favorite(path)
  if not db then M.load() end
  return db.favorites[path] ~= nil
end

function M.toggle_favorite(path)
  if not db then M.load() end
  if db.favorites[path] then db.favorites[path] = nil
  else db.favorites[path] = os.time() end
  M.save()
  return M.is_favorite(path)
end

function M.list_favorites()
  if not db then M.load() end
  local out = {}
  for p, ts in pairs(db.favorites) do
    out[#out + 1] = { path = p, ts = ts }
  end
  table.sort(out, function(a, b) return a.ts > b.ts end)
  return out
end

-- ── Recent ───────────────────────────────────────────────────
local RECENT_MAX = 60

function M.touch_recent(path)
  if not db then M.load() end
  if not path then return end
  -- rimuovi esistente
  for i = #db.recent, 1, -1 do
    if db.recent[i].path == path then table.remove(db.recent, i) end
  end
  table.insert(db.recent, 1, { path = path, ts = os.time() })
  while #db.recent > RECENT_MAX do table.remove(db.recent) end
  M.save()
end

function M.list_recent(n)
  if not db then M.load() end
  local out = {}
  local limit = n or #db.recent
  for i = 1, math.min(limit, #db.recent) do
    out[#out + 1] = db.recent[i]
  end
  return out
end

function M.list_resume(n)
  if not db then M.load() end
  local out = {}
  for p, r in pairs(db.resume) do
    out[#out + 1] = { path = p, pos = r.pos, dur = r.dur, ts = r.ts, pct = r.pct }
  end
  table.sort(out, function(a, b) return a.ts > b.ts end)
  if n then
    local o2 = {}
    for i = 1, math.min(n, #out) do o2[i] = out[i] end
    return o2
  end
  return out
end

function M.clear_all()
  db = fresh()
  M.save()
end

M.load()
return M
