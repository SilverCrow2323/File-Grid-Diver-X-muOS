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
  },
  sound   = { enabled = false, volume = 70 },
  update  = { auto_catalog = true, auto_app_check = true },
  last_cwd = "/mnt/mmc",
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

function S.get(section, key)
  if not S.data then S.load() end
  if key then return S.data[section] and S.data[section][key] end
  return S.data[section]
end

function S.set(section, key, value)
  if not S.data then S.load() end
  S.data[section] = S.data[section] or {}
  S.data[section][key] = value
end

local function pretty_json(v, indent)
  indent = indent or 0
  local pad = string.rep("  ", indent)
  local pad_inner = string.rep("  ", indent + 1)
  if type(v) ~= "table" then
    return json.encode(v)
  end
  -- Detect array vs object
  local n = 0
  local is_array = true
  for k in pairs(v) do
    n = n + 1
    if type(k) ~= "number" then is_array = false; break end
  end
  if n == 0 then return "{}" end
  if is_array then
    local parts = {}
    for i = 1, #v do
      parts[#parts + 1] = pad_inner .. pretty_json(v[i], indent + 1)
    end
    return "[\n" .. table.concat(parts, ",\n") .. "\n" .. pad .. "]"
  end
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = tostring(k) end
  table.sort(keys)
  local parts = {}
  for _, k in ipairs(keys) do
    local val = v[k]
    if val == nil then
      for kk, vv in pairs(v) do
        if tostring(kk) == k then val = vv; break end
      end
    end
    parts[#parts + 1] = pad_inner .. json.encode(k) .. ": " ..
      pretty_json(val, indent + 1)
  end
  return "{\n" .. table.concat(parts, ",\n") .. "\n" .. pad .. "}"
end

function S.save()
  if not S.data then return end
  os.execute("mkdir -p data")
  local tmp = S.path .. ".tmp"
  local f = io.open(tmp, "w")
  if f then
    f:write(pretty_json(S.data, 0))
    f:write("\n")
    f:close()
    os.rename(tmp, S.path)
  end
end

return S
