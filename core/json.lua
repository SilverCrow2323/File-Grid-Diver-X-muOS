-- Minimal JSON encoder/decoder for LuaJIT.
-- Uses the native cjson module when available (see core/native.lua),
-- falls back to the pure-Lua implementation in this file otherwise.

local Native = nil
pcall(function() Native = require("core.native") end)
local cjson = (Native and Native.cjson) or nil

local json = {}

local esc = {
  ['"']='\\"', ['\\']='\\\\', ['\b']='\\b',
  ['\f']='\\f', ['\n']='\\n', ['\r']='\\r', ['\t']='\\t',
}
local function esc_char(c) return esc[c] or string.format("\\u%04x", c:byte()) end
local function enc_str(s) return '"' .. s:gsub('[%z\1-\31\\"]', esc_char) .. '"' end

local function enc_num(n)
  if n ~= n or n == math.huge or n == -math.huge then return "null" end
  if n == math.floor(n) and math.abs(n) < 1e15 then return string.format("%d", n) end
  return string.format("%.14g", n)
end

local enc_val
local function enc_tab(t, seen)
  if seen[t] then error("circular reference") end
  seen[t] = true
  local is_arr, n = true, 0
  for k in pairs(t) do
    n = n + 1
    if type(k) ~= "number" or k ~= math.floor(k) or k < 1 then is_arr = false end
  end
  if n == 0 then is_arr = false end
  local parts = {}
  if is_arr then
    for i = 1, #t do parts[#parts+1] = enc_val(t[i], seen) end
    seen[t] = nil
    return "[" .. table.concat(parts, ",") .. "]"
  end
  for k, v in pairs(t) do
    if type(k) == "string" then
      parts[#parts+1] = enc_str(k) .. ":" .. enc_val(v, seen)
    end
  end
  seen[t] = nil
  return "{" .. table.concat(parts, ",") .. "}"
end

enc_val = function(v, seen)
  if v == nil then return "null" end
  local ty = type(v)
  if ty == "string" then return enc_str(v) end
  if ty == "number" then return enc_num(v) end
  if ty == "boolean" then return v and "true" or "false" end
  if ty == "table" then return enc_tab(v, seen or {}) end
  return "null"
end

function json.encode(v)
  if cjson then
    local ok, s = pcall(cjson.encode, v)
    if ok and type(s) == "string" and s ~= "" then
      return s
    end
  end
  return enc_val(v, {})
end

local dec_val
local function skip_ws(s, i)
  while i <= #s do
    local c = s:sub(i, i)
    if c == " " or c == "\t" or c == "\n" or c == "\r" then i = i + 1 else break end
  end
  return i
end

local function dec_str(s, i)
  i = i + 1
  local out = {}
  while i <= #s do
    local c = s:sub(i, i)
    if c == '"' then return table.concat(out), i + 1 end
    if c == "\\" then
      local nx = s:sub(i + 1, i + 1)
      if nx == "n" then out[#out+1] = "\n"; i = i + 2
      elseif nx == "t" then out[#out+1] = "\t"; i = i + 2
      elseif nx == "r" then out[#out+1] = "\r"; i = i + 2
      elseif nx == "b" then out[#out+1] = "\b"; i = i + 2
      elseif nx == "f" then out[#out+1] = "\f"; i = i + 2
      elseif nx == "/" then out[#out+1] = "/"; i = i + 2
      elseif nx == "\\" then out[#out+1] = "\\"; i = i + 2
      elseif nx == '"' then out[#out+1] = '"'; i = i + 2
      elseif nx == "u" then
        local cp = tonumber(s:sub(i + 2, i + 5), 16) or 63
        if cp < 0x80 then out[#out+1] = string.char(cp)
        elseif cp < 0x800 then
          out[#out+1] = string.char(0xC0 + math.floor(cp / 0x40), 0x80 + (cp % 0x40))
        else
          out[#out+1] = string.char(0xE0 + math.floor(cp / 0x1000),
                                    0x80 + (math.floor(cp / 0x40) % 0x40),
                                    0x80 + (cp % 0x40))
        end
        i = i + 6
      else out[#out+1] = nx; i = i + 2 end
    else out[#out+1] = c; i = i + 1 end
  end
  error("unterminated string")
end

local function dec_num(s, i)
  local j = i
  while j <= #s and s:sub(j, j):match("[%d%.eE%+%-]") do j = j + 1 end
  local n = tonumber(s:sub(i, j - 1))
  if not n then error("bad number at " .. i) end
  return n, j
end

local function dec_arr(s, i)
  i = i + 1
  local arr = {}
  i = skip_ws(s, i)
  if s:sub(i, i) == "]" then return arr, i + 1 end
  while true do
    local v; v, i = dec_val(s, i)
    arr[#arr+1] = v
    i = skip_ws(s, i)
    local c = s:sub(i, i)
    if c == "]" then return arr, i + 1 end
    if c == "," then i = skip_ws(s, i + 1) else error("expected , or ]") end
  end
end

local function dec_obj(s, i)
  i = i + 1
  local obj = {}
  i = skip_ws(s, i)
  if s:sub(i, i) == "}" then return obj, i + 1 end
  while true do
    if s:sub(i, i) ~= '"' then error("expected key") end
    local k; k, i = dec_str(s, i)
    i = skip_ws(s, i)
    if s:sub(i, i) ~= ":" then error("expected :") end
    i = skip_ws(s, i + 1)
    local v; v, i = dec_val(s, i)
    obj[k] = v
    i = skip_ws(s, i)
    local c = s:sub(i, i)
    if c == "}" then return obj, i + 1 end
    if c == "," then i = skip_ws(s, i + 1) else error("expected , or }") end
  end
end

dec_val = function(s, i)
  i = skip_ws(s, i)
  local c = s:sub(i, i)
  if c == '"' then return dec_str(s, i) end
  if c == "{" then return dec_obj(s, i) end
  if c == "[" then return dec_arr(s, i) end
  if c == "t" then return true, i + 4 end
  if c == "f" then return false, i + 5 end
  if c == "n" then return nil, i + 4 end
  return dec_num(s, i)
end

function json.decode(s)
  if cjson and type(s) == "string" then
    local ok, v = pcall(cjson.decode, s)
    if ok then return v end
  end
  return dec_val(s, 1)
end

return json
