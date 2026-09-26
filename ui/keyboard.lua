-- ui/keyboard.lua -- on-screen keyboard v2.
-- Layout: 4 rows + action row. D-pad or L stick navigates.
-- A confirms a char. B hides the keyboard. Y backspace. X space.
-- L1/R1 move cursor in the buffer. SELECT cycles layout:
--   lower -> UPPER -> special -> lower. Auto-capitalize first
--   letter of a sentence, or after . ! ?
-- START is newline (multi-line mode only).
-- Long-press not used. Auto-repeat via the parent gamepad handler.
local A = require("core.assets")

local KB = {}

local W, H = 640, 480
local KB_H = 224
local KB_Y = H - KB_H - 22

KB.open_flag = false
KB.buffer    = ""
KB.title     = ""
KB.on_accept = nil
KB.on_cancel = nil
KB.on_hide   = nil         -- called when B hides the keyboard
KB.focus     = { row = 1, col = 1 }
KB.cursor    = 0           -- index in buffer, 0..len
KB.layout    = "lower"     -- "lower" | "upper" | "special"
KB.multiline = true

local ROWS_LOWER = {
  "1234567890",
  "qwertyuiop",
  "asdfghjkl-",
  "zxcvbnm._/",
}
local ROWS_UPPER = {
  "!@#$%^&*()",
  "QWERTYUIOP",
  "ASDFGHJKL+",
  "ZXCVBNM?:;",
}
local ROWS_SPECIAL = {
  "[]{}()<>|~",
  "`'\"\\/+=%$",
  "!?#@&*-_^,",
  ":;.,°§€£¥",
}

local ACTIONS = {
  { key = "SHIFT", label = "SHIFT", w = 84 },
  { key = "SPACE", label = "SPACE", w = 120 },
  { key = "BKSP",  label = "BKSP",  w = 84 },
  { key = "CANCEL",label = "ESC",   w = 84 },
  { key = "OK",    label = "OK",    w = 84 },
}

local KEY_W, KEY_H = 54, 30
local KEY_GAP = 4
local COLS = 10
local ROWS = 4
local ACT_ROW = 5

local function rows_for(layout)
  if layout == "upper"   then return ROWS_UPPER end
  if layout == "special" then return ROWS_SPECIAL end
  return ROWS_LOWER
end

local function grid_width()
  return COLS * (KEY_W + KEY_GAP) - KEY_GAP
end
local function grid_x_start() return (W - grid_width()) / 2 end
local function grid_y_start() return KB_Y + 40 end

local function col_count_for_row(row)
  if row <= ROWS then return COLS end
  return #ACTIONS
end

local function key_at(row, col)
  if row <= ROWS then
    local line = rows_for(KB.layout)[row] or ""
    local c = line:sub(col, col)
    if c == "" or c == " " then return nil end
    return c
  end
  if row == ACT_ROW and col >= 1 and col <= #ACTIONS then
    return ACTIONS[col].key
  end
  return nil
end

-- Auto-capitalize detection
local function needs_caps(buf, pos)
  if pos == 0 then return true end
  local prev = buf:sub(pos, pos)  -- char before cursor (1-indexed)
  if prev == "\n" then return true end
  if prev == "." or prev == "!" or prev == "?" then return true end
  return false
end

local function insert_at_cursor(s)
  local b = KB.buffer
  local c = KB.cursor
  KB.buffer = b:sub(1, c) .. s .. b:sub(c + 1)
  KB.cursor = c + #s
end

local function backspace()
  if KB.cursor == 0 then return end
  local b = KB.buffer
  KB.buffer = b:sub(1, KB.cursor - 1) .. b:sub(KB.cursor + 1)
  KB.cursor = KB.cursor - 1
end

local function delete_forward()
  if KB.cursor >= #KB.buffer then return end
  local b = KB.buffer
  KB.buffer = b:sub(1, KB.cursor) .. b:sub(KB.cursor + 2)
end

local function cycle_layout()
  if     KB.layout == "lower"   then KB.layout = "upper"
  elseif KB.layout == "upper"   then KB.layout = "special"
  else KB.layout = "lower" end
end

-- ============================================================
--  API
-- ============================================================
function KB.open(opts)
  opts = opts or {}
  KB.open_flag = true
  KB.buffer    = opts.initial or ""
  KB.title     = opts.title or "Input"
  KB.on_accept = opts.on_accept
  KB.on_cancel = opts.on_cancel
  KB.on_hide   = opts.on_hide
  KB.multiline = opts.multiline ~= false
  KB.focus     = { row = 1, col = 1 }
  KB.layout    = "lower"
  KB.cursor    = #KB.buffer
end

function KB.close()
  KB.open_flag = false
  KB.on_accept = nil
  KB.on_cancel = nil
  KB.on_hide   = nil
end

function KB.hide()
  -- Called by B: hide keyboard but keep buffer alive for later edit.
  KB.open_flag = false
  if KB.on_hide then pcall(KB.on_hide, KB.buffer) end
end

function KB.is_open() return KB.open_flag end

local function accept()
  local cb = KB.on_accept
  local txt = KB.buffer
  KB.close()
  if cb then pcall(cb, txt) end
end

local function cancel()
  local cb = KB.on_cancel
  KB.close()
  if cb then pcall(cb) end
end

-- ============================================================
--  Input
-- ============================================================
local function move(dr, dc)
  local r = KB.focus.row + dr
  local c = KB.focus.col + dc
  if r < 1 then r = 1 end
  if r > ACT_ROW then r = ACT_ROW end
  local maxc = col_count_for_row(r)
  if c < 1 then c = maxc end
  if c > maxc then c = 1 end
  KB.focus.row = r
  KB.focus.col = c
end

local function press_key(key)
  if not key then return end
  if key == "SHIFT" then
    cycle_layout()
  elseif key == "SPACE" then
    insert_at_cursor(" ")
  elseif key == "BKSP" then
    backspace()
  elseif key == "CANCEL" then
    cancel()
  elseif key == "OK" then
    accept()
  else
    local ch = key
    -- Auto-capitalize: if layout is lower and caps is needed, uppercase
    if KB.layout == "lower" and #ch == 1 and ch:match("%a") then
      if needs_caps(KB.buffer, KB.cursor) then
        ch = ch:upper()
      end
    end
    insert_at_cursor(ch)
  end
end

function KB.pad(b)
  if not KB.open_flag then return end
  local IM = require("core.input_map")
  if     b == IM.A then press_key(key_at(KB.focus.row, KB.focus.col))
  elseif b == IM.B then KB.hide()
  elseif b == IM.START then
    if KB.multiline then insert_at_cursor("\n") end
  elseif b == IM.SELECT then cycle_layout()
  elseif b == IM.Y then backspace()
  elseif b == IM.X then insert_at_cursor(" ")
  elseif b == IM.L1 then
    KB.cursor = math.max(0, KB.cursor - 1)
  elseif b == IM.R1 then
    KB.cursor = math.min(#KB.buffer, KB.cursor + 1)
  end
end

function KB.hat(dir)
  if not KB.open_flag then return end
  if     dir == "up"    then move(-1, 0)
  elseif dir == "down"  then move( 1, 0)
  elseif dir == "left"  then move(0, -1)
  elseif dir == "right" then move(0,  1)
  end
end

function KB.key(k)
  if not KB.open_flag then return end
  if #k == 1 then
    insert_at_cursor(k)
  elseif k == "backspace" then backspace()
  elseif k == "delete"    then delete_forward()
  elseif k == "return"    then
    if KB.multiline then insert_at_cursor("\n") else accept() end
  elseif k == "escape"    then cancel()
  elseif k == "space"     then insert_at_cursor(" ")
  elseif k == "tab"       then cycle_layout()
  elseif k == "left"      then KB.cursor = math.max(0, KB.cursor - 1)
  elseif k == "right"     then KB.cursor = math.min(#KB.buffer, KB.cursor + 1)
  end
end

function KB.update(_) end

-- ============================================================
--  Draw
-- ============================================================
local BLINK_PERIOD = 0.5
local blink_t = 0

function KB.draw()
  if not KB.open_flag then return end
  blink_t = blink_t + (love.timer.getDelta() or 0.016)

  local ok, State = pcall(require, "core.state")
  local th = ok and State.theme or {
    text = {0.85, 0.82, 0.76},
    text_dim = {0.44, 0.42, 0.38},
    panel = {0.05, 0.05, 0.04},
    amber = {0.94, 0.66, 0.35},
    amber_hi = {0.94, 0.66, 0.35},
    amber_lo = {0.35, 0.22, 0.10},
    cyan_hi = {0.48, 0.80, 0.90},
  }

  -- Dim
  love.graphics.setColor(0, 0, 0, 0.72)
  love.graphics.rectangle("fill", 0, 0, W, H)

  -- Panel
  love.graphics.setColor(th.panel)
  love.graphics.rectangle("fill", 0, KB_Y, W, KB_H)
  love.graphics.setColor(th.amber_lo[1], th.amber_lo[2], th.amber_lo[3], 0.9)
  love.graphics.rectangle("line", 0.5, KB_Y + 0.5, W - 1, KB_H - 1)
  love.graphics.setColor(th.amber_lo[1], th.amber_lo[2], th.amber_lo[3], 0.35)
  love.graphics.rectangle("line", 4.5, KB_Y + 4.5, W - 9, KB_H - 9)

  -- Title + layout indicator
  love.graphics.setColor(th.amber_hi)
  love.graphics.setFont(A.font(A.FONT_BODY_BOLD, 12))
  love.graphics.print("> " .. KB.title:upper(), 14, KB_Y + 8)

  local layout_labels = { lower="abc", upper="ABC", special="!@#" }
  love.graphics.setFont(A.font(A.FONT_MONO, 10))
  love.graphics.setColor(th.cyan_hi)
  love.graphics.printf("[" .. (layout_labels[KB.layout] or "abc") .. "]",
    0, KB_Y + 9, W - 14, "right")

  -- Buffer + cursor
  love.graphics.setColor(0.02, 0.02, 0.015, 1)
  love.graphics.rectangle("fill", 14, KB_Y + 24, W - 28, 20)
  love.graphics.setColor(th.cyan_hi)
  love.graphics.setFont(A.font(A.FONT_MONO, 13))

  -- Scroll buffer horizontally if needed
  local maxw = W - 40
  local visible_start = 1
  local pre = KB.buffer:sub(1, KB.cursor)
  local pre_w = love.graphics.getFont():getWidth(pre)
  if pre_w > maxw - 20 then
    -- shift so cursor stays visible
    local cut = pre:sub(math.max(1, #pre - 50))
    visible_start = #pre - #cut + 1
  end
  local visible = KB.buffer:sub(visible_start)
  if #visible > 90 then visible = visible:sub(1, 90) end

  local cursor_local = KB.cursor - (visible_start - 1)
  local before = visible:sub(1, cursor_local)
  local after  = visible:sub(cursor_local + 1)
  local blink = (math.floor(blink_t / BLINK_PERIOD) % 2 == 0)
  local cur_char = blink and "|" or " "
  local rendered = before .. cur_char .. after
  love.graphics.print(rendered, 20, KB_Y + 27)

  -- Keys
  local x0 = grid_x_start()
  local y0 = grid_y_start()
  local rows = rows_for(KB.layout)

  for r = 1, ROWS do
    local line = rows[r] or ""
    for c = 1, COLS do
      local ch = line:sub(c, c)
      if ch ~= "" and ch ~= " " then
        local kx = x0 + (c - 1) * (KEY_W + KEY_GAP)
        local ky = y0 + (r - 1) * (KEY_H + KEY_GAP)
        local focused = (KB.focus.row == r and KB.focus.col == c)

        local bg = focused
          and {th.amber_hi[1]*0.35, th.amber_hi[2]*0.35, th.amber_hi[3]*0.35}
          or  {0.10, 0.09, 0.07}
        love.graphics.setColor(bg[1], bg[2], bg[3], 1)
        love.graphics.rectangle("fill", kx, ky, KEY_W, KEY_H)

        if focused then
          love.graphics.setColor(th.amber_hi)
          love.graphics.setLineWidth(2)
        else
          love.graphics.setColor(th.amber_lo[1], th.amber_lo[2], th.amber_lo[3], 0.7)
          love.graphics.setLineWidth(1)
        end
        love.graphics.rectangle("line", kx + 0.5, ky + 0.5, KEY_W - 1, KEY_H - 1)
        love.graphics.setLineWidth(1)

        love.graphics.setColor(focused and {1, 1, 1} or th.text)
        love.graphics.setFont(A.font(A.FONT_MONO, 16))
        local tw = love.graphics.getFont():getWidth(ch)
        love.graphics.print(ch, kx + (KEY_W - tw) / 2, ky + (KEY_H - 16) / 2)
      end
    end
  end

  -- Action row
  local ACT_TOTAL = 0
  for _, a in ipairs(ACTIONS) do ACT_TOTAL = ACT_TOTAL + a.w end
  ACT_TOTAL = ACT_TOTAL + (KEY_GAP * (#ACTIONS - 1))
  local ax = (W - ACT_TOTAL) / 2
  local ay = y0 + ROWS * (KEY_H + KEY_GAP)

  for i, act in ipairs(ACTIONS) do
    local aw = act.w
    local kx = ax
    local focused = (KB.focus.row == ACT_ROW and KB.focus.col == i)

    local bg = focused
      and {th.amber_hi[1]*0.35, th.amber_hi[2]*0.35, th.amber_hi[3]*0.35}
      or  {0.10, 0.09, 0.07}
    love.graphics.setColor(bg[1], bg[2], bg[3], 1)
    love.graphics.rectangle("fill", kx, ay, aw, KEY_H)
    love.graphics.setColor(
      focused and th.amber_hi[1] or th.amber_lo[1],
      focused and th.amber_hi[2] or th.amber_lo[2],
      focused and th.amber_hi[3] or th.amber_lo[3], 1)
    love.graphics.setLineWidth(focused and 2 or 1)
    love.graphics.rectangle("line", kx + 0.5, ay + 0.5, aw - 1, KEY_H - 1)
    love.graphics.setLineWidth(1)

    love.graphics.setColor(focused and {1, 1, 1} or th.text)
    love.graphics.setFont(A.font(A.FONT_BODY_BOLD, 12))
    love.graphics.printf(act.label, kx, ay + 9, aw, "center")

    ax = ax + aw + KEY_GAP
  end

  -- Hint line
  love.graphics.setFont(A.font(A.FONT_MONO, 9))
  love.graphics.setColor(th.text_dim, 0.75)
  love.graphics.printf(
    "A type  B hide  Y backspace  X space  L1/R1 cursor  SELECT layout  START newline",
    0, KB_Y + KB_H - 14, W, "center")
end

return KB
