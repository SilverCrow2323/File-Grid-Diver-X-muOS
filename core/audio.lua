-- core/audio.lua — small SFX manager.
-- Loads WAV files from assets/sfx/. Clones sources for overlapping
-- playback (a single LÖVE Source cannot be played twice at once).
local M = {}

local cache     = {}
local enabled   = true
local volume    = 0.55

-- Background-music slot. Exactly one BGM at a time.
-- Cloned from the cache just like SFX, but kept alive so we can fade
-- its volume smoothly without disturbing the source in cache.
local bgm = nil  -- { source =, base_vol =, fading =, fade_t =, fade_dur =, start_vol = }

local NAMES = {
  "nav", "nav2", "nav3",
  "enter", "back", "error", "success", "open", "beep", "boot", "finalbout",
  "gokustep",
  "toggle_switch", "toggle_badge",
}

-- Try .ogg first, then .wav. Return (source, ext) or (nil, nil).
-- Keeping both extensions supported means a user who drops a stray
-- .wav still gets sound, and a fully .ogg library loads cleanly.
local function try_load(name)
  local candidates = {
    { path = "assets/sfx/" .. name .. ".ogg", ext = "ogg" },
    { path = "assets/sfx/" .. name .. ".wav", ext = "wav" },
  }
  for _, c in ipairs(candidates) do
    local ok, src = pcall(love.audio.newSource, c.path, "static")
    if ok and src then return src, c.ext, c.path end
  end
  return nil, nil, nil
end

function M.load()
  local loaded, missing = 0, {}
  for _, name in ipairs(NAMES) do
    local src, ext, path = try_load(name)
    if src then
      cache[name] = src
      loaded = loaded + 1
      print("[SFX] loaded: " .. name .. " (" .. ext .. ")")
    else
      missing[#missing + 1] = name
    end
  end
  if #missing > 0 then
    print("[SFX] missing: " .. table.concat(missing, ", "))
  end
  print("[SFX] total loaded: " .. loaded .. "/" .. #NAMES)
end

function M.play(name, vol)
  if not enabled then return end
  if M._fb_mode and M._FB_MAP[name] then name = M._FB_MAP[name] end
  local base = cache[name]
  if not base then return end
  -- clone so rapid-fire taps overlap cleanly
  local ok, clone = pcall(function() return base:clone() end)
  if ok and clone then
    clone:setVolume((vol or 1.0) * volume)
    pcall(function() clone:play() end)
  end
end

-- FGDX_FB_MODE: quando attivo, i nomi degli SFX vengono
-- tradotti nei file della cartella assets/sfx/fb/.
M._fb_mode = false
M._FB_MAP = {
  nav            = "fb/navfb",
  nav2           = "fb/nav2fb",
  nav3           = "fb/nav2fb",
  enter          = "fb/selectfb",
  back           = "fb/backfb",
  error          = "fb/errorfb",
  success        = "fb/select2fb",
  open           = "fb/select2fb",
  beep           = "fb/warningfb",
  toggle_switch  = "fb/warningfb",
  toggle_badge   = "fb/select2fb",
}
function M.set_fb_mode(on)
  M._fb_mode = on == true
  local f = io.open("data/fgd_runtime.log", "a")
  if f then
    f:write(os.date("%Y-%m-%d %H:%M:%S") ..
      " [audio] FB mode = " .. tostring(M._fb_mode) .. "\n")
    f:close()
  end
end
function M.is_fb_mode() return M._fb_mode == true end

function M.set_enabled(v)  enabled = v end
function M.set_volume(v)   volume = math.max(0, math.min(1, v)) end
function M.is_enabled()    return enabled end
function M.get_volume()    return volume end

function M.debug_info()
  local n = 0
  for _ in pairs(cache) do n = n + 1 end
  return {
    enabled = enabled,
    volume = volume,
    loaded = n,
    cache = cache,
  }
end


-- ============================================================
--  Background music (BGM)
-- ============================================================
-- Starts a looping BGM. Returns the internal handle, or nil if the
-- file is missing. Does NOT go through NAMES -- it is loaded lazily
-- as an .ogg (streamed) with .wav fallback (static).
function M.play_bgm(name, vol)
  M.stop_bgm()
  if not name or name == "" then return nil end

  local base = cache[name]
  if not base then
    -- Streamed OGG first (long tracks), static WAV fallback.
    local candidates = {
      { path = "assets/sfx/" .. name .. ".ogg", mode = "stream", ext = "ogg" },
      { path = "assets/sfx/" .. name .. ".wav", mode = "static", ext = "wav" },
    }
    for _, c in ipairs(candidates) do
      local ok, src = pcall(love.audio.newSource, c.path, c.mode)
      if ok and src then
        base = src
        print("[BGM] loaded: " .. name .. " (" .. c.ext .. ")")
        break
      end
    end
    if not base then
      print("[BGM] cannot load: " .. name)
      return nil
    end
    cache[name] = base
  end

  local ok, clone = pcall(function() return base:clone() end)
  if not ok or not clone then return nil end
  clone:setLooping(true)
  local v = (vol or 1.0) * volume
  clone:setVolume(v)
  pcall(function() clone:play() end)

  bgm = {
    source    = clone,
    base_vol  = v,
    fading    = false,
    fade_t    = 0,
    fade_dur  = 0,
    start_vol = v,
  }
  print("[BGM] playing: " .. name .. "  vol=" .. string.format("%.2f", v))
  return bgm
end

-- Start a gradual fade-out. `duration` is in seconds; 2.0 is a good default.
function M.fade_bgm(duration)
  if not bgm then return end
  bgm.fading    = true
  bgm.fade_t    = 0
  bgm.fade_dur  = math.max(0.1, duration or 2.0)
  bgm.start_vol = bgm.source:getVolume()
  print("[BGM] fade-out over " .. bgm.fade_dur .. "s")
end

-- Stop immediately. Safe to call when nothing is playing.
function M.stop_bgm()
  if bgm and bgm.source then
    pcall(function() bgm.source:stop() end)
  end
  bgm = nil
end

-- Called every frame from love.update. Drives the fade.
function M.update_bgm(dt)
  if not bgm then return end
  if not bgm.fading then return end
  bgm.fade_t = bgm.fade_t + dt
  local k = bgm.fade_t / bgm.fade_dur
  if k >= 1 then
    M.stop_bgm()
    return
  end
  local v = bgm.start_vol * (1 - k)
  pcall(function() bgm.source:setVolume(v) end)
end

function M.is_bgm_playing()
  return bgm ~= nil and not bgm.fading
end


return M
