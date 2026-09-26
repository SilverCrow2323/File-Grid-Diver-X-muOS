-- screens/search.lua — recursive fuzzy search with async shell.
local A     = require("core.assets")
local State = require("core.state")
local Input = require("core.input_map")
local Frame = require("ui.frame")
local D     = require("ui.draw")
local KB    = require("ui.keyboard")
local Notify= require("ui.notify")
local FS    = require("services.fs")
local sh    = require("core.sh")

local S = {}
local W, H = 640, 480

local query     = ""
local results   = {}
local sel       = 1
local searching = false
local job_id    = nil
local job_start = 0

local function tmpname(suffix)
  return "/tmp/fgd_search_" .. (job_id or "x") .. suffix
end

local function kill_job()
  if not job_id then return end
  os.execute("pkill -f fgd_search_" .. job_id .. " 2>/dev/null")
  os.remove(tmpname(".sh"))
  os.remove(tmpname(".out"))
  os.remove(tmpname(".done"))
  job_id = nil
end

local function start_search(q)
  kill_job()
  results = {}
  sel = 1
  query = q
  if not q or q == "" then return end
  job_id = tostring(os.time()) .. "_" .. tostring(math.random(1000, 9999))
  job_start = love.timer.getTime()

  local root = State.cwd or "/"
  local script = tmpname(".sh")
  local out    = tmpname(".out")
  local done   = tmpname(".done")

  local body = table.concat({
    "set +e",
    "OUT=" .. sh.shq(out),
    "DONE=" .. sh.shq(done),
    ': > "$OUT"',
    -- case-insensitive fuzzy-ish match on basename; also match full path
    "find " .. sh.shq(root) ..
      " -mindepth 1 2>/dev/null | grep -i -- " .. sh.shq(q) ..
      " | head -n 400 > \"$OUT\"",
    'touch "$DONE"',
  }, "\n")

  local f = io.open(script, "w")
  if not f then Notify.show("error", "cannot write job"); return end
  f:write("#!/bin/sh\n" .. body .. "\n")
  f:close()
  os.execute("chmod +x " .. sh.shq(script))
  os.execute("setsid sh " .. sh.shq(script) ..
    " </dev/null >/dev/null 2>&1 &")
  searching = true
end

local function poll()
  if not job_id then return end
  local done = tmpname(".done")
  local f = io.open(done, "r")
  if not f then
    -- timeout
    if love.timer.getTime() - job_start > 30 then
      kill_job(); searching = false
      Notify.show("warning", "search timeout")
    end
    return
  end
  f:close()

  results = {}
  local of = io.open(tmpname(".out"), "r")
  if of then
    for line in of:lines() do
      if line ~= "" then
        local e = FS.stat(line) or {}
        e.path = line
        e.name = line:match("([^/]+)$") or line
        results[#results + 1] = e
      end
    end
    of:close()
  end
  kill_job()
  searching = false
  if #results == 0 then
    Notify.show("info", "no matches for: " .. query)
  else
    Notify.show("success", #results .. " matches")
  end
end

function S.enter()
  results = {}
  sel = 1
  query = ""
  searching = false
  job_id = nil
  -- auto-prompt
  KB.open({
    title = "Search",
    initial = "",
    on_accept = function(t) start_search(t) end,
    on_cancel = function() State.back() end,
  })
end
function S.leave() kill_job() end
function S.update(dt)
  KB.update(dt)
  if searching then poll() end
end

local function move(d)
  if #results == 0 then return end
  sel = sel + d
  if sel < 1 then sel = 1 end
  if sel > #results then sel = #results end
end

local function open_result()
  local e = results[sel]
  if not e then return end
  if e.is_dir then
    State.cwd = e.path
    State.go("grid")
    return
  end
  State.selected_path = e.path
  State.selected_entry = e
  local kind = FS.classify(e)
  if kind == "image" then State.go("image_viewer")
  elseif kind == "audio" then State.go("audio_player")
  elseif kind == "video" then State.go("video_player")
  elseif kind == "text" then State.go("editor")
  else State.cwd = e.path:match("^(.*)/[^/]+$") or State.cwd
       State.go("grid") end
end

function S.pad(b)
  if KB.is_open() then KB.pad(b); return end
  if     b == Input.B or b == Input.SELECT then State.back()
  elseif b == Input.UP   then move(-1)
  elseif b == Input.DOWN then move( 1)
  elseif b == Input.A    then open_result()
  elseif b == Input.X    then
    KB.open({
      title = "Search",
      initial = query,
      on_accept = function(t) start_search(t) end,
    })
  end
end
function S.hat(dir) S.pad(dir == "up" and Input.UP or dir == "down" and Input.DOWN) end
function S.key(k)
  if KB.is_open() then KB.key(k); return end
  if k == "escape" or k == "backspace" then State.back()
  elseif k == "up"   then move(-1)
  elseif k == "down" then move( 1)
  elseif k == "return" then open_result()
  elseif k == "/" then
    KB.open({ title = "Search", initial = query,
      on_accept = function(t) start_search(t) end })
  end
end

function S.draw()
  local th = State.theme
  D.bg()

  -- Query bar
  love.graphics.setColor(0.03, 0.026, 0.022, 1)
  love.graphics.rectangle("fill", 10, Frame.TOP_H + 4, W - 20, 22)
  love.graphics.setColor(th.amber_lo[1], th.amber_lo[2], th.amber_lo[3], 0.6)
  love.graphics.rectangle("line", 10.5, Frame.TOP_H + 4.5, W - 21, 21)

  love.graphics.setColor(th.amber_hi)
  love.graphics.setFont(A.font(A.FONT_BODY_BOLD, 13))
  love.graphics.print("> " .. (query == "" and "(press X)" or query), 20,
    Frame.TOP_H + 8)

  love.graphics.setFont(A.font(A.FONT_MONO, 12))
  love.graphics.setColor(searching and th.amber_hi or th.cyan_hi)
  love.graphics.printf(
    searching and "SEARCHING…" or string.format("%d RESULTS", #results),
    0, Frame.TOP_H + 8, W - 20, "right")

  -- Results
  local row_h = 22
  local y0 = Frame.TOP_H + 32
  local vis = math.floor((H - y0 - Frame.BOTTOM_H - 6) / row_h)
  local first = math.max(1, sel - math.floor(vis / 2))
  local last  = math.min(#results, first + vis - 1)

  if #results == 0 and not searching then
    love.graphics.setColor(th.text_dim)
    love.graphics.setFont(A.font(A.FONT_BODY, 14))
    love.graphics.printf("no results yet — press X to type a query",
      0, H/2, W, "center")
  end

  for i = first, last do
    local e = results[i]
    local ry = y0 + (i - first) * row_h
    local focused = (i == sel)
    if focused then
      love.graphics.setColor(0.06, 0.05, 0.035, 1)
      love.graphics.rectangle("fill", 10, ry, W - 20, row_h - 2)
    end
    love.graphics.setColor(focused and th.amber_hi or th.text_dim)
    love.graphics.setFont(A.font(A.FONT_MONO, 12))
    love.graphics.printf(string.format("%03d", i), 14, ry + 6, 30, "right")
    love.graphics.setColor(focused and th.text_bright or th.text)
    love.graphics.setFont(A.font(A.FONT_BODY, 13))
    love.graphics.print(e.path, 50, ry + 5)
  end

  Frame.draw_top("FGD", "search")
  Frame.draw_bottom({
    { key = "UP/DN", label = "Select" },
    { key = "A",     label = "Open" },
    { key = "X",     label = "New query" },
    { key = "B",     label = "Back" },
  })

  KB.draw()
  D.scanlines(W, H, 0.06)
end

return S
