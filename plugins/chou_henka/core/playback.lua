-- core/playback.lua -- mpv engine wrapper + track selector.
local MP  = require("services.media_player")
local CFG = require("plugins.chou_henka.core.config")
local M = {}

M.ENGINES = {
  normal  = { label="Normal",  audio_filter="" },
  cinema  = { label="Cinema",  audio_filter="dynaudnorm=f=250:g=15" },
  music   = { label="Music",   audio_filter="equalizer=f=100:t=q:w=1:g=3,equalizer=f=3000:t=q:w=2:g=2" },
  podcast = { label="Podcast", audio_filter="dynaudnorm=f=250:g=15,equalizer=f=3000:t=q:w=2:g=4" },
  bass    = { label="Bass",    audio_filter="equalizer=f=60:t=q:w=1:g=8,equalizer=f=170:t=q:w=1:g=4" },
  vgm     = { label="VGM",     audio_filter="equalizer=f=8000:t=q:w=2:g=4,equalizer=f=12000:t=q:w=2:g=6" },
  voice   = { label="Voice",   audio_filter="highpass=f=200,lowpass=f=3000,dynaudnorm=f=250:g=20" },
}
M.ENGINE_ORDER = { "normal","cinema","music","podcast","bass","vgm","voice" }

local function eng(name) return M.ENGINES[name] or M.ENGINES.normal end

function M.current_engine() return CFG.get("player","engine") or "normal" end
function M.apply_engine(name)
  if not M.ENGINES[name] then name = "normal" end
  CFG.set("player","engine",name); CFG.save()
  if MP.daemon_running() then
    pcall(function() MP.send("set_property","af",eng(name).audio_filter or "") end)
  end
end
function M.cycle_engine(dir)
  local cur, order = M.current_engine(), M.ENGINE_ORDER
  local i = 1; for k,v in ipairs(order) do if v==cur then i=k end end
  i = ((i-1+dir) % #order + #order) % #order + 1
  M.apply_engine(order[i]); return order[i]
end

function M.apply_volume()
  pcall(function() MP.set_volume(CFG.get("player","volume") or 70) end)
end
function M.set_volume(v)
  v = math.max(0, math.min(200, v))
  CFG.set("player","volume",v); CFG.save()
  pcall(function() MP.set_volume(v) end)
end
function M.set_speed(v)
  v = math.max(0.25, math.min(4.0, v))
  CFG.set("player","speed",v*100); CFG.save()
  pcall(function() MP.set_speed(v) end)
end
function M.apply_speed()
  local s = (CFG.get("player","speed") or 100) / 100
  pcall(function() MP.set_speed(s) end)
end

function M.start_audio(path)
  MP.stop_daemon()
  local ok, err = MP.start_daemon()
  if not ok then return false, err end
  MP.send("loadfile", path, "replace")
  M.apply_engine(M.current_engine())
  M.apply_volume(); M.apply_speed()
  return true
end
function M.play_fullscreen_video(p) return MP.play_fullscreen(p) end
function M.stop() MP.stop_daemon() end
function M.seek(d) pcall(function() MP.seek_relative(d) end) end
function M.toggle_pause() pcall(function() MP.toggle_pause() end) end
function M.is_playing() return MP.daemon_running() end
function M.probe(p) return MP.probe(p) end
function M.get_prop(k) return MP.get_property(k) end

-- ── Track selector ──────────────────────────────────────────
function M.get_tracks()
  local list = MP.get_track_list() or {}
  local audio, subs, video = {}, {}, {}
  for _, t in ipairs(list) do
    if t.type == "audio" then audio[#audio+1] = t
    elseif t.type == "sub" then subs[#subs+1] = t
    elseif t.type == "video" then video[#video+1] = t end
  end
  return { audio = audio, subs = subs, video = video }
end

function M.get_current_audio()
  return MP.get_audio_track()
end

function M.get_current_sub()
  return MP.get_sub_track()
end

function M.set_audio(id)
  MP.set_audio_track(id)
end

function M.set_sub(id)
  MP.set_sub_track(id)
end

function M.disable_sub()
  MP.send("set_property", "sid", "no")
end

function M.auto_sub()
  MP.send("set_property", "sid", "auto")
end

-- Cicla audio avanti/indietro
function M.cycle_audio(dir)
  local t = M.get_tracks()
  if #t.audio == 0 then return nil end
  local cur = M.get_current_audio()
  local idx = 1
  for i, tr in ipairs(t.audio) do
    if tr.id == cur then idx = i; break end
  end
  idx = idx + dir
  if idx < 1 then idx = #t.audio end
  if idx > #t.audio then idx = 1 end
  M.set_audio(t.audio[idx].id)
  return t.audio[idx]
end

-- Cicla sub: include "no" e "auto" come stati
function M.cycle_sub(dir)
  local t = M.get_tracks()
  local states = { "auto", "no" }
  for _, tr in ipairs(t.subs) do states[#states+1] = tr.id end
  local cur = M.get_current_sub()
  local idx = 1
  for i, s in ipairs(states) do if s == cur then idx = i end end
  idx = idx + dir
  if idx < 1 then idx = #states end
  if idx > #states then idx = 1 end
  local target = states[idx]
  if target == "no" then M.disable_sub()
  elseif target == "auto" then M.auto_sub()
  else M.set_sub(target) end
  return target
end

function M.media_info() return MP.get_media_info() end

return M
