-- core/addons.lua -- registry future estensioni
local sh  = require("core.sh")
local CFG = require("plugins.chou_henka.core.config")
local M = {}

M.ADDON_ROOT = "plugins/chou_henka/addons"

M.BUILTIN_SLOTS = {
  { key="video_library", label="Video Library Providers",
    desc="Add sources for movies/TV (Jellyfin, Plex, TMDB)", status="planned" },
  { key="theme_pack",    label="Theme Packs",
    desc="Extra color themes and layout skins", status="planned" },
  { key="decoder_pack",  label="Media Decoders",
    desc="Additional codec support (PGS, DTS, HEVC 10-bit)", status="planned" },
  { key="scraper",       label="Metadata Scrapers",
    desc="Auto-fetch cover art and metadata", status="planned" },
  { key="subtitle_pack", label="Subtitle Sources",
    desc="OpenSubtitles / OpenSUBS lookups", status="planned" },
}

local addons = {}

function M.scan()
  addons = {}
  if not sh.is_dir(M.ADDON_ROOT) then return end
  -- sh.read usa io.popen internamente nel modulo core.sh (fuori sandbox)
  local out = sh.read("ls -1d " .. sh.shq(M.ADDON_ROOT) .. "/*/ 2>/dev/null")
  if not out or out == "" then return end
  for line in out:gmatch("[^\n]+") do
    local pkg = line:match("([^/]+)/$")
    if pkg then
      -- Prova a caricare il manifest via require (passthrough sandbox)
      local ok, man = pcall(require, "plugins.chou_henka.addons." .. pkg .. ".addon")
      if ok and type(man) == "table" and man.key then
        man.pkg = pkg
        man.status = "installed"
        addons[#addons+1] = man
      end
    end
  end
end

function M.list()
  local out = {}
  for _, a in ipairs(addons) do out[#out+1] = a end
  for _, s in ipairs(M.BUILTIN_SLOTS) do
    local installed = false
    for _, a in ipairs(addons) do
      if a.key == s.key then installed = true end
    end
    if not installed then
      local c = {}
      for k, v in pairs(s) do c[k] = v end
      c.installed = false
      out[#out+1] = c
    end
  end
  return out
end

function M.enabled(key)
  local e = CFG.get("addons", "enabled") or {}
  return e[key] == true
end

function M.set_enabled(key, on)
  local e = CFG.get("addons", "enabled") or {}
  e[key] = on and true or nil
  CFG.set("addons", "enabled", e)
  CFG.save()
end

M.scan()
return M
