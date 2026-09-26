-- screens/editor.lua — small-file surgical text editor.
-- Preserves BOM and line endings. Atomic save with .fgd.bak backup.
-- Files > 512 KB open read-only.
local A     = require("core.assets")
local State = require("core.state")
local Input = require("core.input_map")
local Frame = require("ui.frame")
local D     = require("ui.draw")
local KB    = require("ui.keyboard")
local Modal = require("ui.modal")
local Notify= require("ui.notify")

local S = {}
S.raw_keys = true
S.reserve_select = true
S.escape_passthrough = true
local W, H = 640, 480

local edit = {
  path     = nil,
  lines    = { "" },
  bom      = "",
  eol      = "LF",
  ro       = false,
  dirty    = false,
  cline    = 1,
  ccol     = 1,
  scroll   = 1,
  show_ln  = true,
  t_cur    = 0,
  undo     = {},
  redo     = {},
}

local function snapshot()
  local copy = {}
  for i, l in ipairs(edit.lines) do copy[i] = l end
  return { lines = copy, cline = edit.cline, ccol = edit.ccol }
end
local function push_undo()
  edit.undo[#edit.undo + 1] = snapshot()
  if #edit.undo > 200 then table.remove(edit.undo, 1) end
  edit.redo = {}
end
local function do_undo()
  if #edit.undo == 0 then return end
  edit.redo[#edit.redo + 1] = snapshot()
  local s = table.remove(edit.undo)
  edit.lines = s.lines; edit.cline = s.cline; edit.ccol = s.ccol
  edit.dirty = true
end
local function do_redo()
  if #edit.redo == 0 then return end
  edit.undo[#edit.undo + 1] = snapshot()
  local s = table.remove(edit.redo)
  edit.lines = s.lines; edit.cline = s.cline; edit.ccol = s.ccol
  edit.dirty = true
end

local function load_file(p)
  edit.path = p
  edit.lines = {""}
  edit.bom = ""
  edit.eol = "LF"
  edit.ro = false
  edit.dirty = false
  edit.cline = 1
  edit.ccol = 1
  edit.scroll = 1
  edit.undo = {}
  edit.redo = {}
  if not p or p == "" then return end
  local f = io.open(p, "rb")
  if not f then
    Notify.show("error", "cannot open " .. p)
    return
  end
  local data = f:read("*a") or ""
  f:close()
  local size = #data
  if size > 512 * 1024 then edit.ro = true end
  -- BOM
  if data:sub(1, 3) == "\239\187\191" then
    edit.bom = "\239\187\191"
    data = data:sub(4)
  end
  -- EOL detect
  if data:find("\r\n", 1, true) then edit.eol = "CRLF" end
  -- normalize
  data = data:gsub("\r\n", "\n")
  local lines = {}
  for line in (data .. "\n"):gmatch("([^\n]*)\n") do
    lines[#lines + 1] = line
  end
  -- last element is trailing if original had no trailing newline
  if data:sub(-1) ~= "\n" and #lines > 1 then
    -- keep as is (means no trailing newline: still add a final empty slot)
    -- We drop the artifact: original data ended without \n, gmatch adds one
    if #lines > 0 and lines[#lines] == "" then
      table.remove(lines)
    end
  end
  if #lines == 0 then lines = {""} end
  edit.lines = lines
end

local function detect_syntax()
  if not edit.path then return "Text" end
  local e = edit.path:match("%.([^.]+)$")
  if not e then return "Text" end
  e = e:lower()
  if e == "lua" then return "Lua" end
  if e == "sh" or e == "bash" then return "Sh" end
  if e == "json" then return "JSON" end
  if e == "md" then return "MD" end
  if e == "py" then return "Py" end
  if e == "conf" or e == "ini" or e == "cfg" or e == "gptk" then return "INI" end
  return "Text"
end

local function save_file()
  if edit.ro then
    Notify.show("warning", "read-only")
    return
  end
  local eol = (edit.eol == "CRLF") and "\r\n" or "\n"
  local body = table.concat(edit.lines, eol)
  local content = edit.bom .. body
  -- backup
  pcall(function()
    local src = io.open(edit.path, "rb")
    if src then
      local d = src:read("*a"); src:close()
      local b = io.open(edit.path .. ".fgd.bak", "wb")
      if b then b:write(d); b:close() end
    end
  end)
  -- atomic
  local tmp = edit.path .. ".tmp"
  local f = io.open(tmp, "wb")
  if not f then Notify.show("error", "cannot write"); return end
  f:write(content); f:close()
  local ok = os.rename(tmp, edit.path)
  if not ok then
    os.execute("mv '" .. tmp .. "' '" .. edit.path .. "'")
  end
  edit.dirty = false
  Notify.show("success", "saved " .. (edit.path:match("([^/]+)$") or ""))
end

local function confirm_back()
  if edit.dirty then
    Modal.show("Unsaved changes",
      "File has unsaved modifications. Save before leaving?",
      {
        accept_label = "SAVE",
        cancel_label = "DISCARD",
        on_accept = function() save_file(); State.back() end,
        on_cancel = function() State.back() end,
      })
  else
    State.back()
  end
end

-- ── Cursor / editing ops ────────────────────────────────────
local function clamp_cursor()
  if edit.cline < 1 then edit.cline = 1 end
  if edit.cline > #edit.lines then edit.cline = #edit.lines end
  local line = edit.lines[edit.cline] or ""
  if edit.ccol < 1 then edit.ccol = 1 end
  if edit.ccol > #line + 1 then edit.ccol = #line + 1 end
end

local function insert_text(t)
  if edit.ro then return end
  push_undo()
  local line = edit.lines[edit.cline] or ""
  local before = line:sub(1, edit.ccol - 1)
  local after  = line:sub(edit.ccol)
  -- split by newlines in inserted text
  local parts = {}
  for seg in (t .. "\n"):gmatch("([^\n]*)\n") do parts[#parts + 1] = seg end
  if #parts == 1 then
    edit.lines[edit.cline] = before .. parts[1] .. after
    edit.ccol = edit.ccol + #parts[1]
  else
    local newlines = {}
    newlines[1] = before .. parts[1]
    for i = 2, #parts - 1 do newlines[#newlines + 1] = parts[i] end
    newlines[#newlines + 1] = parts[#parts] .. after
    local tail = {}
    for i = edit.cline + 1, #edit.lines do tail[#tail + 1] = edit.lines[i] end
    edit.lines[edit.cline] = newlines[1]
    for i = 2, #newlines do
      table.insert(edit.lines, edit.cline + i - 1, newlines[i])
    end
    edit.cline = edit.cline + #newlines - 1
    edit.ccol  = #parts[#parts] + 1
  end
  edit.dirty = true
end

local function insert_char(c)
  insert_text(c)
end

local function backspace()
  if edit.ro then return end
  push_undo()
  if edit.ccol > 1 then
    local line = edit.lines[edit.cline]
    edit.lines[edit.cline] = line:sub(1, edit.ccol - 2) .. line:sub(edit.ccol)
    edit.ccol = edit.ccol - 1
  elseif edit.cline > 1 then
    local prev = edit.lines[edit.cline - 1]
    local cur  = edit.lines[edit.cline]
    edit.lines[edit.cline - 1] = prev .. cur
    table.remove(edit.lines, edit.cline)
    edit.cline = edit.cline - 1
    edit.ccol = #prev + 1
  end
  edit.dirty = true
end

local function del()
  if edit.ro then return end
  push_undo()
  local line = edit.lines[edit.cline]
  if edit.ccol <= #line then
    edit.lines[edit.cline] = line:sub(1, edit.ccol - 1) .. line:sub(edit.ccol + 1)
  elseif edit.cline < #edit.lines then
    edit.lines[edit.cline] = line .. (edit.lines[edit.cline + 1] or "")
    table.remove(edit.lines, edit.cline + 1)
  end
  edit.dirty = true
end

local function newline()
  if edit.ro then return end
  insert_text("\n")
end

local function move_cursor(dx, dy)
  if dy ~= 0 then
    edit.cline = edit.cline + dy
    clamp_cursor()
    local line = edit.lines[edit.cline] or ""
    if edit.ccol > #line + 1 then edit.ccol = #line + 1 end
  end
  if dx ~= 0 then
    edit.ccol = edit.ccol + dx
    if edit.ccol < 1 then
      if edit.cline > 1 then
        edit.cline = edit.cline - 1
        edit.ccol = #(edit.lines[edit.cline] or "") + 1
      else edit.ccol = 1 end
    end
    local line = edit.lines[edit.cline] or ""
    if edit.ccol > #line + 1 then
      if edit.cline < #edit.lines then
        edit.cline = edit.cline + 1
        edit.ccol = 1
      else edit.ccol = #line + 1 end
    end
  end
end

-- ── Lifecycle ───────────────────────────────────────────────
function S.enter()
  local p = State.selected_path
  if not p then
    local e = State.selected_entry
    if e then p = e.path end
  end
  if not p then
    p = "/tmp/fgd_untitled.txt"
    local f = io.open(p, "w"); if f then f:write(""); f:close() end
  end
  load_file(p)
  edit.t_cur = 0
  edit.undo = {}
  edit.redo = {}
end

function S.leave() end

function S.update(dt)
  edit.t_cur = edit.t_cur + dt
  KB.update(dt)

  -- STICK HANDLING
  -- L stick = rapid cursor move, R stick = scroll text
  if not KB.is_open() and not Modal.is_open() then
    local js = love.joystick and love.joystick.getJoysticks()[1]
    if js then
      local okx, lx = pcall(js.getAxis, js, 1)
      local oky, ly = pcall(js.getAxis, js, 2)
      local okrx, rx = pcall(js.getAxis, js, 3)
      local okry, ry = pcall(js.getAxis, js, 4)
      local DEAD = 0.35
      -- Cursor with left stick
      if okx and math.abs(lx) > DEAD then
        edit.accum_x = (edit.accum_x or 0) + dt * math.abs(lx)
        if edit.accum_x > 0.05 then
          edit.accum_x = 0
          if lx > 0 then move_cursor(1, 0) else move_cursor(-1, 0) end
        end
      else edit.accum_x = 0 end
      if oky and math.abs(ly) > DEAD then
        edit.accum_y = (edit.accum_y or 0) + dt * math.abs(ly)
        if edit.accum_y > 0.05 then
          edit.accum_y = 0
          if ly > 0 then move_cursor(0, 1) else move_cursor(0, -1) end
        end
      else edit.accum_y = 0 end
      -- Scroll with right stick
      if okry and math.abs(ry) > DEAD then
        edit.scroll = edit.scroll + ry * dt * 20
        edit.scroll = math.max(1, math.min(#edit.lines, edit.scroll))
      end
    end
  end
  -- scroll follow
  local vis = math.floor((H - Frame.TOP_H - Frame.BOTTOM_H - 40) / 12)
  if edit.cline < edit.scroll then edit.scroll = edit.cline end
  if edit.cline > edit.scroll + vis - 1 then edit.scroll = edit.cline - vis + 1 end
end

-- ── Input ───────────────────────────────────────────────────
function S.pad(b)
  if KB.is_open() then
    KB.pad(b)
    return
  end
  if Modal.is_open() then
    if b == Input.A then Modal.accept()
    elseif b == Input.B then Modal.cancel() end
    return
  end
  if     b == Input.UP    then move_cursor(0, -1)
  elseif b == Input.DOWN  then move_cursor(0,  1)
  elseif b == Input.LEFT  then move_cursor(-1, 0)
  elseif b == Input.RIGHT then move_cursor( 1, 0)
  elseif b == Input.A then
    -- open keyboard at current cursor position
    local pre  = (edit.lines[edit.cline] or ""):sub(1, edit.ccol - 1)
    local post = (edit.lines[edit.cline] or ""):sub(edit.ccol)
    local initial = pre .. post  -- full line as seed
    KB.open({
      title = "Edit line " .. edit.cline,
      initial = initial,
      multiline = true,
      on_accept = function(t)
        -- Replace current line with the edited text (may be multi-line)
        local new_lines = {}
        for seg in (t .. "\n"):gmatch("([^\n]*)\n") do
          new_lines[#new_lines + 1] = seg
        end
        if #new_lines == 0 then new_lines = {""} end
        push_undo()
        edit.lines[edit.cline] = new_lines[1]
        for i = 2, #new_lines do
          table.insert(edit.lines, edit.cline + i - 1, new_lines[i])
        end
        edit.cline = edit.cline + #new_lines - 1
        edit.ccol = #new_lines[#new_lines] + 1
        edit.dirty = true
      end,
      on_hide = function(t)
        -- Store the buffer so next A re-opens with it
        edit._kb_buffer = t
        edit._kb_cline = edit.cline
      end,
    })
  elseif b == Input.B then confirm_back()
  elseif b == Input.X then
    -- delete current line
    if not edit.ro then
      push_undo()
      table.remove(edit.lines, edit.cline)
      if #edit.lines == 0 then edit.lines = {""} end
      clamp_cursor()
      edit.dirty = true
    end
  elseif b == Input.Y then save_file()
  elseif b == Input.L1 then edit.scroll = math.max(1, edit.scroll - 20); edit.cline = edit.scroll
  elseif b == Input.R1 then edit.scroll = math.min(#edit.lines, edit.scroll + 20); edit.cline = edit.scroll
  elseif b == Input.START then save_file()
  elseif b == Input.SELECT then edit.show_ln = not edit.show_ln
  end
end

function S.hat(dir) S.pad(dir == "up" and Input.UP or dir == "down" and Input.DOWN or dir == "left" and Input.LEFT or Input.RIGHT) end

function S.key(k)
  if KB.is_open() then KB.key(k); return end
  if Modal.is_open() then
    if k == "return" then Modal.accept()
    elseif k == "escape" then Modal.cancel() end
    return
  end
  if     k == "up"    then move_cursor(0, -1)
  elseif k == "down"  then move_cursor(0,  1)
  elseif k == "left"  then move_cursor(-1, 0)
  elseif k == "right" then move_cursor( 1, 0)
  elseif k == "backspace" then backspace()
  elseif k == "delete"    then del()
  elseif k == "return"    then newline()
  elseif k == "tab"       then insert_text("    ")
  elseif k == "home"      then edit.ccol = 1
  elseif k == "end"       then edit.ccol = #(edit.lines[edit.cline] or "") + 1
  elseif k == "pageup"    then edit.cline = math.max(1, edit.cline - 20); clamp_cursor()
  elseif k == "pagedown"  then edit.cline = math.min(#edit.lines, edit.cline + 20); clamp_cursor()
  elseif k == "escape"    then confirm_back()
  elseif k == "s" and love.keyboard.isDown("lctrl", "rctrl") then save_file()
  elseif k == "z" and love.keyboard.isDown("lctrl", "rctrl") then do_undo()
  elseif k == "y" and love.keyboard.isDown("lctrl", "rctrl") then do_redo()
  end
end

function S.textinput(t)
  if KB.is_open() or Modal.is_open() then return end
  insert_char(t)
end

-- ── Draw ────────────────────────────────────────────────────
function S.draw()
  local th = State.theme
  D.bg()

  local fnt = A.font(A.FONT_MONO, 13)
  love.graphics.setFont(fnt)
  local line_h = 12
  local gutter_w = edit.show_ln and 44 or 8
  local pad_l = 6

  local area_top = Frame.TOP_H + 18
  local area_bot = H - Frame.BOTTOM_H - 22
  local vis = math.floor((area_bot - area_top) / line_h)

  local first = edit.scroll
  local last  = math.min(#edit.lines, first + vis - 1)

  -- gutter background
  if edit.show_ln then
    love.graphics.setColor(0.02, 0.016, 0.012, 1)
    love.graphics.rectangle("fill", 0, area_top, gutter_w, area_bot - area_top)
    love.graphics.setColor(th.amber_lo[1], th.amber_lo[2], th.amber_lo[3], 0.4)
    love.graphics.line(gutter_w - 0.5, area_top, gutter_w - 0.5, area_bot)
  end

  -- current line highlight
  local cy = area_top + (edit.cline - first) * line_h
  if edit.cline >= first and edit.cline <= last then
    love.graphics.setColor(0.06, 0.05, 0.04, 1)
    love.graphics.rectangle("fill", gutter_w, cy, W - gutter_w, line_h)
  end

  -- lines
  for i = first, last do
    local y = area_top + (i - first) * line_h
    local line = edit.lines[i] or ""

    if edit.show_ln then
      love.graphics.setColor(th.text_dim)
      love.graphics.printf(string.format("%4d", i),
        0, y, gutter_w - 6, "right")
    end

    love.graphics.setColor(th.text)
    love.graphics.print(line, gutter_w + pad_l, y)
  end

  -- cursor
  local show_cursor = (math.floor(edit.t_cur * 2) % 2 == 0)
  if show_cursor and edit.cline >= first and edit.cline <= last then
    local line = edit.lines[edit.cline] or ""
    local before = line:sub(1, edit.ccol - 1)
    local cw = fnt:getWidth(before)
    local x = gutter_w + pad_l + cw
    local y = area_top + (edit.cline - first) * line_h
    love.graphics.setColor(th.amber_hi)
    love.graphics.rectangle("fill", x, y, 6, line_h)
  end

  -- Info bar
  love.graphics.setColor(0.02, 0.016, 0.012, 1)
  love.graphics.rectangle("fill", 0, Frame.TOP_H, W, 16)
  love.graphics.setColor(th.amber_lo[1], th.amber_lo[2], th.amber_lo[3], 0.4)
  love.graphics.line(0, Frame.TOP_H + 15.5, W, Frame.TOP_H + 15.5)

  love.graphics.setFont(A.font(A.FONT_MONO, 12))
  love.graphics.setColor(th.amber_hi)
  local name = edit.path and edit.path:match("([^/]+)$") or "?"
  love.graphics.print(name .. (edit.ro and "  [RO]" or "") .. (edit.dirty and "  *" or ""),
    8, Frame.TOP_H + 3)

  love.graphics.setColor(th.cyan_hi)
  love.graphics.printf(string.format("[%s] [%s] [%s]   Ln %d, Col %d   %d lines",
    edit.eol, edit.bom ~= "" and "BOM" or "UTF-8", detect_syntax(),
    edit.cline, edit.ccol, #edit.lines),
    0, Frame.TOP_H + 3, W - 8, "right")

  -- Status footer
  love.graphics.setColor(th.text_dim)
  love.graphics.setFont(A.font(A.FONT_BODY, 12))
  love.graphics.print("A: insert   Y/START: save   X: del line   B: exit   SEL: line numbers   CTRL+Z/Y",
    8, H - Frame.BOTTOM_H - 14)

  Frame.draw_top("FGD", "editor")
  Frame.draw_bottom({
    { key = "D-PAD",  label = "Move" },
    { key = "A",      label = "Insert" },
    { key = "Y",      label = "Save" },
    { key = "X",      label = "Del line" },
    { key = "B",      label = "Exit" },
  })

  KB.draw()
  D.scanlines(W, H, 0.06)
end

return S
