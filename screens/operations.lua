-- screens/operations.lua — running ops + ops log browser.
local A     = require("core.assets")
local State = require("core.state")
local Input = require("core.input_map")
local Frame = require("ui.frame")
local D     = require("ui.draw")
local sh    = require("core.sh")

local S = {}
local W, H = 640, 480

local OPS_LOG = "data/ops.log"
local entries = {}
local scroll = 0
local tab = "ops"    -- ops | jobs

local function read_ops_log()
  entries = {}
  local f = io.open(OPS_LOG, "r")
  if not f then
    entries = { "(no ops.log yet)" }
    return
  end
  local all = {}
  for line in f:lines() do all[#all + 1] = line end
  f:close()
  -- keep last 500
  local start = math.max(1, #all - 499)
  for i = start, #all do entries[#entries + 1] = all[i] end
  if #entries == 0 then entries = { "(empty)" } end
  scroll = #entries
end

local function list_jobs()
  local out = {}
  -- look for our /tmp markers
  local h = io.popen("ls -1 /tmp/fgd_*.done 2>/dev/null")
  if h then
    for line in h:lines() do
      out[#out + 1] = "done: " .. line
    end
    h:close()
  end
  h = io.popen("ls -1 /tmp/fgd_*.sh 2>/dev/null")
  if h then
    for line in h:lines() do
      out[#out + 1] = "running: " .. line
    end
    h:close()
  end
  if #out == 0 then out = { "(no jobs in /tmp)" } end
  return out
end

local function append_op(kind, target, ok, note)
  os.execute("mkdir -p data")
  local f = io.open(OPS_LOG, "a")
  if f then
    f:write(string.format("%s  %s  %s  %s  %s\n",
      os.date("%Y-%m-%d %H:%M:%S"),
      kind, ok and "OK" or "FAIL",
      target, note or ""))
    f:close()
  end
end

function S.enter()
  read_ops_log()
end
function S.leave() end
function S.update(dt) end

local function view_lines()
  if tab == "ops" then return entries end
  return list_jobs()
end

local function move(n)
  scroll = math.max(1, math.min(#view_lines(), scroll + n))
end

function S.pad(b)
  if     b == Input.B or b == Input.SELECT then State.back()
  elseif b == Input.UP   then move(-1)
  elseif b == Input.DOWN then move( 1)
  elseif b == Input.L1   then move(-10)
  elseif b == Input.R1   then move( 10)
  elseif b == Input.X    then
    tab = (tab == "ops") and "jobs" or "ops"
    if tab == "ops" then read_ops_log() end
    scroll = 1
  elseif b == Input.Y    then
    -- clear ops.log
    os.remove(OPS_LOG)
    read_ops_log()
  end
end
function S.hat(dir)
  if     dir == "up"   then move(-1)
  elseif dir == "down" then move( 1) end
end
function S.key(k)
  if k == "escape" or k == "backspace" then State.back()
  elseif k == "up"   then move(-1)
  elseif k == "down" then move( 1)
  elseif k == "pageup"   then move(-10)
  elseif k == "pagedown" then move( 10)
  elseif k == "tab" then
    tab = (tab == "ops") and "jobs" or "ops"
    if tab == "ops" then read_ops_log() end
    scroll = 1
  end
end

function S.draw()
  local th = State.theme
  D.bg()

  -- Tab header
  love.graphics.setFont(A.font(A.FONT_BODY_BOLD, 13))
  local f = A.font(A.FONT_BODY_BOLD, 13)
  local function tab_at(x, label, active)
    local w = f:getWidth(label) + 16
    love.graphics.setColor(active and th.amber_hi or th.text_dim)
    love.graphics.rectangle("line", x, Frame.TOP_H + 4, w, 16)
    love.graphics.print(label, x + 8, Frame.TOP_H + 7)
    return x + w + 4
  end
  local tx = 10
  tx = tab_at(tx, "OPERATIONS LOG", tab == "ops")
  tx = tab_at(tx, "RUNNING JOBS",   tab == "jobs")

  love.graphics.setColor(th.text_dim)
  love.graphics.setFont(A.font(A.FONT_MONO, 12))
  love.graphics.printf("X: switch   Y: clear log", 0, Frame.TOP_H + 7, W - 12, "right")

  -- List
  local lines = view_lines()
  local row_h = 12
  local y0 = Frame.TOP_H + 26
  local vis = math.floor((H - y0 - Frame.BOTTOM_H - 4) / row_h)
  local first = math.max(1, scroll - vis + 1)
  local last  = math.min(#lines, first + vis - 1)

  local font = A.font(A.FONT_MONO, 12)
  love.graphics.setFont(font)
  for i = first, last do
    local line = lines[i]
    local y = y0 + (i - first) * row_h
    local cur = (i == scroll)
    local ok  = line:find(" OK ", 1, true)
    local bad = line:find(" FAIL ", 1, true)
    if cur then
      love.graphics.setColor(0.10, 0.08, 0.05, 1)
      love.graphics.rectangle("fill", 0, y - 1, W, row_h)
    end
    if bad then love.graphics.setColor(th.red_hi)
    elseif ok then love.graphics.setColor(th.green)
    elseif cur then love.graphics.setColor(th.cyan_hi)
    else love.graphics.setColor(th.text) end
    love.graphics.print(line, 12, y)
  end

  love.graphics.setColor(th.text_dim)
  love.graphics.setFont(A.font(A.FONT_MONO, 12))
  love.graphics.printf(string.format("%d / %d", scroll, #lines),
    0, Frame.TOP_H + 7, W - 12, "left")

  Frame.draw_top("FGD", "operations")
  Frame.draw_bottom({
    { key = "UP/DN", label = "Scroll" },
    { key = "L1/R1", label = "±10" },
    { key = "X",     label = "Switch tab" },
    { key = "Y",     label = "Clear" },
    { key = "B",     label = "Back" },
  })
  D.scanlines(W, H, 0.06)
end

return S
