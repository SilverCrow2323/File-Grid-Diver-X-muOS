-- luacheck configuration for File-GD X.
-- Run locally with:  luacheck .

std = "lua51+love"
max_line_length = false

exclude_files = {
  ".desktopbase/**",
  ".fgd_backup_*/**",
  "releases/**",
  "lib/**",
  "vendor/**",
  "docs/**",
  ".git/**",
  "build/**",
}

ignore = {
  "212",   -- unused argument (LÖVE callbacks often ignore theirs)
  "213",   -- unused loop variable
  "542",   -- empty if branch
  "631",   -- line too long (max_line_length is off anyway)
}

globals = {
  "jit",
  "utf8",
  "loadstring",   -- LuaJIT / Lua 5.1
  "setfenv",      -- LuaJIT / Lua 5.1
  "getfenv",      -- LuaJIT / Lua 5.1
  "unpack",       -- LuaJIT / Lua 5.1
}
