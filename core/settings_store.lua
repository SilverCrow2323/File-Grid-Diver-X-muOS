local json = require("core.json")
local S = { data = nil, path = "data/fgd.json" }

S.defaults = {
  general = {
    theme = "blame",
    grid_cols = 5,
    grid_rows = 3,
    font_scale = 1.0,
    show_hidden = false,
    sort_asc = true,
    view = "list",
    multi_select = true,
  },
  sort    = { key = "name", folders_first = true },
  ui = {
    show_fps      = false,
    particles     = true,
    header_logo   = true,
    font_scale    = 1.40,
    font_family   = "auto",
    header_h      = 48,
    footer_h      = 40,
    show_clock    = true,
    show_wifi     = true,
    show_battery  = true,
    show_mem      = true,
    show_download = true,
    icon_set      = "classic",
  },
  sound   = { enabled = false, volume = 70, set = "default" },
  update  = { auto_catalog = true, auto_app_check = true },
  last_cwd = "/mnt/mmc",
  goku = {
    show_mascot  = true,
    mascot       = "goku",
    transparency = 0,
    size         = "medium",
    amp          = 14,
    speed        = "normal",
    shadow       = true,
  },
}

local function deep_copy(t)
  local c = {}
  for k, v in pairs(t) do c[k] = type(v) == "table" and deep_copy(v) or v end
  return c
end

local function merge(dst, src)
  for k, v in pairs(src) do
    if type(v) == "table" and type(dst[k]) == "table" then merge(dst[k], v)
    else dst[k] = v end
  end
end

function S.load()
  S.data = deep_copy(S.defaults)
  local f = io.open(S.path, "r")
  if not f then return end
  local c = f:read("*a"); f:close()
  local ok, d = pcall(json.decode, c)
  if ok and type(d) == "table" then merge(S.data, d) end
end

