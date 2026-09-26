-- screens/input_investigation.lua -- Input Holmes (compact).
local A     = require("core.assets")
local State = require("core.state")
local Input = require("core.input_map")
local Frame = require("ui.frame")
local D     = require("ui.draw")
local BI    = require("ui.button_icons")

local S = {}
local W, H = 640, 480
local OUT_DIR = "data/inputinvestigation"
os.execute("mkdir -p " .. OUT_DIR)

local last_error = nil
local function trap(fn)
  local ok, err = pcall(fn)
  if not ok then
    last_error = tostring(err)
    local f = io.open("data/fgd_error.log", "a")
    if f then f:write(os.date("%Y-%m-%d %H:%M:%S  ") .. last_error .. "\n"); f:close() end
  end
end

local BUTTONS = {
  { key="dpup", label="DPAD UP", gp={"dpup"}, raw={} },
  { key="dpdown", label="DPAD DOWN", gp={"dpdown"}, raw={} },
  { key="dpleft", label="DPAD LEFT", gp={"dpleft"}, raw={} },
  { key="dpright", label="DPAD RIGHT", gp={"dpright"}, raw={} },
  { key="a", label="BUTTON A", gp={"a"}, raw={3} },
  { key="b", label="BUTTON B", gp={"b"}, raw={4} },
  { key="x", label="BUTTON X", gp={"x"}, raw={6} },
  { key="y", label="BUTTON Y", gp={"y"}, raw={5} },
  { key="l1", label="L1", gp={"leftshoulder"}, raw={7} },
  { key="l2", label="L2", gp={"lefttrigger"}, raw={13} },
  { key="l3", label="L3 (stick click)", gp={"leftstick"}, raw={12} },
  { key="r1", label="R1", gp={"rightshoulder"}, raw={8} },
  { key="r2", label="R2", gp={"righttrigger"}, raw={14} },
  { key="r3", label="R3 (stick click)", gp={"rightstick"}, raw={15} },
  { key="start", label="START", gp={"start"}, raw={10} },
  { key="select", label="SELECT", gp={"back"}, raw={9} },
  { key="volup", label="VOL+", gp={}, raw={2} },
  { key="voldown", label="VOL-", gp={}, raw={1} },
  { key="m", label="M / MENU", gp={"guide"}, raw={11} },
}
local NB = #BUTTONS

local DIALOGUE = {
  "I was expecting you,",
  "Watsbrobs.",
  "I imagine you are here",
  "because, once again,",
  "your memory fails to",
  "recall how one walks --",
  "or worse, how one defines",
  "the inputs of one's own",
  "commands.",
  "Select Start Investigation",
  "to begin the identification",
  "process.",
  "I do hope that, at the",
  "very least, this much",
  "you are able to do.",
}

local CHAR_MS, LINE_HOLD, BOOT_TIME, QUIP_TIME = 0.026, 1.5, 1.0, 2.5
local PAGE_LINES = 4          -- dialogue lines per page

local st, boot_t, menu_sel = "boot", 0, 1
local cur_line, cur_char, line_hold = 1, 0, 0
local page_start = 1          -- first line of current page
local hasty, hasty_t = false, 0
local events, results, idx, timer, T_TEST = {}, {}, 1, 0, 5.0
local session_ts = ""
local hist_files, hist_sel, hist_view = {}, 1, nil

local function col(c, a) love.graphics.setColor(c[1], c[2], c[3], a or 1) end
local function ease(p) return 1 - (1 - p) ^ 3 end
local function reset_dialogue() cur_line, cur_char, line_hold, page_start = 1, 0, 0, 1 end

local function log_event(kind, value)
  events[#events + 1] = { t = os.date("%H:%M:%S"), kind = kind, value = tostring(value) }
end

local function match_target(bt, kind, value)
  if not bt then return false end
  if kind == "gamepad" then
    for _, m in ipairs(bt.gp or {}) do if m == value then return true end end
  end
  if kind == "button" then
    for _, r in ipairs(bt.raw or {}) do if tonumber(value) == r then return true end end
  end
  if kind == "hat" then
    if bt.key=="dpup"    and (value=="u" or value=="up")    then return true end
    if bt.key=="dpdown"  and (value=="d" or value=="down")  then return true end
    if bt.key=="dpleft"  and (value=="l" or value=="left")  then return true end
    if bt.key=="dpright" and (value=="r" or value=="right") then return true end
  end
  if kind == "key" then
    -- keyboard fallback for volume and menu
    local kl = value:lower()
    if bt.key == "volup"   and (kl == "volumeup"   or kl == "audio_vol_up")   then return true end
    if bt.key == "voldown" and (kl == "volumedown" or kl == "audio_vol_down") then return true end
    if bt.key == "m"       and (kl == "menu" or kl == "guide")                then return true end
  end
  if kind == "axis" and type(value) == "table" then
    -- Analog triggers are usually axes 4 and 5 (SDL standard).
    -- LÖVE gives us a table {axis=N, value=V} where |V| > 0.5 counts as pressed.
    local ax, v = value.axis or -1, value.value or 0
    if math.abs(v) < 0.5 then return false end
    if bt.key == "l2" and ax == 4 then return true end
    if bt.key == "r2" and ax == 5 then return true end
  end
  return false
end

local function save_session()
  local f = io.open(OUT_DIR .. "/" .. session_ts .. "_session.txt", "w")
  if not f then return end
  f:write("# Input Investigation Session\n")
  f:write("# Date: " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n\n")
  for i, r in ipairs(results) do
    f:write(string.format("[%02d/%02d] %s -> %s\n", i, NB, r.label, r.verdict))
    for _, e in ipairs(r.events) do
      f:write(string.format("    %s  %-8s  %s\n", e.t, e.kind, e.value))
    end
  end
  f:close()
end

function S.enter()
  st, boot_t, menu_sel = "boot", 0, 1
  reset_dialogue()
  hasty, hasty_t = false, 0
  idx, timer = 1, 0
  events, results = {}, {}
  hist_view = nil
  session_ts = os.date("%Y%m%d_%H%M%S")
  last_error = nil
end
function S.leave() end
function S.wants_capture() return st == "test" end

function S.capture_input(kind, value)
  if st ~= "test" then return end
  local bt = BUTTONS[idx]
  if type(value) == "table" then
    log_event(kind, string.format("axis%d=%.3f", value.axis or 0, value.value or 0))
  else
    log_event(kind, value)
    if match_target(bt, kind, value) then events[#events].matched = true end
  end
end

function S.update(dt)
  if last_error then return end
  if st == "boot" then
    boot_t = boot_t + dt
    if boot_t >= BOOT_TIME then st = "menu"; reset_dialogue() end
    return
  end
  if hasty and hasty_t < QUIP_TIME then hasty_t = hasty_t + dt end
  if st == "test" then
    timer = timer + dt
    if timer >= T_TEST then
      local bt = BUTTONS[idx]
      if bt then
        local ok = false
        for _, e in ipairs(events) do if e.matched then ok = true break end end
        results[#results + 1] = {
          key = bt.key, label = bt.label,
          verdict = ok and "OK" or "NOT DETECTED",
          events = events,
        }
      end
      events = {}
      st = "result"
    end
  end
end

local MENU_OPTS = {
  { key="start", label="Start Investigation", act = function()
      if cur_line <= #DIALOGUE then hasty, hasty_t = true, 0 end
      idx, timer = 1, 0
      events, results = {}, {}
      session_ts = os.date("%Y%m%d_%H%M%S")
      st = "test"
    end },
  { key="history", label="Check Previous Data", act = function()
      if cur_line <= #DIALOGUE then hasty, hasty_t = true, 0 end
      hist_files = {}
      local h = io.popen("ls -1t " .. OUT_DIR .. "/*_session.txt 2>/dev/null | head -20")
      if h then for line in h:lines() do hist_files[#hist_files+1] = line end h:close() end
      hist_sel = 1
      st = "history"
    end },
  { key="back", label="Back", act = function() State.back() end },
}

local function advance()
  idx = idx + 1
  if idx > NB then save_session() st, timer = "done", 0 else st, timer = "test", 0 end
end

function S.pad(b)
  if last_error or st == "boot" then return end
  if st == "menu" then
    if b == Input.UP then menu_sel = math.max(1, menu_sel - 1)
    elseif b == Input.DOWN then menu_sel = math.min(#MENU_OPTS, menu_sel + 1)
    elseif b == Input.A then MENU_OPTS[menu_sel].act()
    elseif b == Input.B or b == Input.SELECT then State.back() end
    return
  end
  if st == "result" then if b == Input.A then advance() end return end
  if st == "done" then if b == Input.A or b == Input.B then State.back() end return end
  if st == "history" then
    if hist_view then if b == Input.B then hist_view = nil end
    else
      if b == Input.UP then hist_sel = math.max(1, hist_sel - 1)
      elseif b == Input.DOWN then hist_sel = math.min(#hist_files, hist_sel + 1)
      elseif b == Input.A and hist_files[hist_sel] then
        hist_view = {}
        local f = io.open(hist_files[hist_sel], "r")
        if f then for line in f:lines() do hist_view[#hist_view+1] = line end f:close() end
      elseif b == Input.B then st = "menu" end
    end
  end
end

function S.hat(dir) if dir=="up" then S.pad(Input.UP) elseif dir=="down" then S.pad(Input.DOWN) end end

function S.key(k)
  if last_error or st == "boot" then return end
  if st == "menu" then
    if k == "up" then menu_sel = math.max(1, menu_sel - 1)
    elseif k == "down" then menu_sel = math.min(#MENU_OPTS, menu_sel + 1)
    elseif k == "return" or k == "space" then MENU_OPTS[menu_sel].act()
    elseif k == "escape" or k == "backspace" then State.back() end
    return
  end
  if st == "result" then if k=="return" or k=="space" then advance() end return end
  if st == "done" then if k=="return" or k=="escape" then State.back() end return end
  if st == "history" then
    if hist_view then if k=="escape" then hist_view = nil end
    else
      if k == "up" then hist_sel = math.max(1, hist_sel - 1)
      elseif k == "down" then hist_sel = math.min(#hist_files, hist_sel + 1)
      elseif k == "return" or k == "space" then
        if hist_files[hist_sel] then
          hist_view = {}
          local f = io.open(hist_files[hist_sel], "r")
          if f then for line in f:lines() do hist_view[#hist_view+1] = line end f:close() end
        end
      elseif k == "escape" then st = "menu" end
    end
  end
end

local YEL    = {0.95, 0.78, 0.20}
local YEL_HI = {1.00, 0.90, 0.42}
local BG     = {0.02, 0.018, 0.012}

local function draw_hatch()
  col(YEL, 0.035)
  for i = 0, 40 do love.graphics.line(0, i * 12, W, i * 12 + 40) end
end

local function draw_holmes(cx, cy, s, a)
  a = a or 1
  if a <= 0.01 then return end
  col(YEL, a)
  love.graphics.setLineWidth(2.2)
  love.graphics.arc("line", "open", cx-14*s, cy-30*s, 32*s, math.pi*1.20, math.pi*1.95)
  love.graphics.arc("line", "open", cx-6*s,  cy-42*s, 26*s, math.pi*0.90, math.pi*1.95)
  love.graphics.line(cx-46*s, cy-22*s, cx+14*s, cy-22*s)
  love.graphics.arc("line", "open", cx-2*s, cy-8*s, 18*s, math.pi*1.10, math.pi*1.72)
  love.graphics.line(cx+13*s, cy-8*s, cx+24*s, cy+3*s)
  love.graphics.line(cx+24*s, cy+3*s, cx+12*s, cy+6*s)
  love.graphics.line(cx+10*s, cy+10*s, cx+17*s, cy+12*s)
  love.graphics.line(cx+17*s, cy+12*s, cx+11*s, cy+20*s)
  love.graphics.arc("line", "open", cx-3*s, cy+13*s, 17*s, -math.pi*0.30, math.pi*0.30)
  love.graphics.line(cx-18*s, cy+32*s, cx+7*s, cy+26*s)
  love.graphics.line(cx-14*s, cy+46*s, cx+12*s, cy+36*s)
  love.graphics.line(cx+10*s, cy+14*s, cx+28*s, cy+18*s)
  love.graphics.circle("line", cx+30*s, cy+22*s, 4*s)
  love.graphics.line(cx+30*s, cy+26*s, cx+28*s, cy+38*s)
  love.graphics.setLineWidth(1)
end

local function draw_balloon(x, y, w, h, a)
  col(YEL, a or 1)
  love.graphics.setLineWidth(1.8)
  love.graphics.ellipse("line", x + w/2, y + h/2, w/2, h/2)
  love.graphics.line(x+w*0.22, y+h*0.85, x+w*0.08, y+h+14)
  love.graphics.line(x+w*0.08, y+h+14, x+w*0.30, y+h*0.92)
  love.graphics.setLineWidth(1)
end

local function draw_dialogue_text()
  local bx, by, bw = 320, 320, 300
  local pad = 22
  local font = A.font(A.FONT_BODY, 12)
  love.graphics.setFont(font)
  local line_h = font:getHeight() + 4
  local text_x = bx + pad
  local text_y = by + 28
  local text_w = bw - pad * 2

  -- Has the dialogue finished entirely?
  local done = (cur_line > #DIALOGUE)

  -- Decide which lines to show.
  local first, last
  if done then
    -- Show the last complete page, fully opaque, no cursor.
    first = math.max(1, #DIALOGUE - PAGE_LINES + 1)
    last  = #DIALOGUE
  else
    first = math.max(page_start, cur_line - PAGE_LINES + 1)
    last  = math.min(cur_line, #DIALOGUE)
  end

  local yy = text_y
  for i = first, last do
    local line = DIALOGUE[i]
    if line then
      local shown, a
      if done then
        shown, a = line, 1.0
      elseif i < cur_line then
        shown, a = line, 0.70
      else
        shown = line:sub(1, math.floor(cur_char))
        a = 1.0
      end
      col(YEL_HI, a)
      love.graphics.printf(shown, text_x, yy, text_w, "center")
      yy = yy + line_h
    end
  end

  -- Blinking ">" only if there is genuinely another line to come.
  if not done then
    local cur = DIALOGUE[cur_line]
    if cur and cur_char >= #cur and cur_line < #DIALOGUE then
      if math.floor(love.timer.getTime() * 2) % 2 == 0 then
        col(YEL_HI, 1)
        love.graphics.print(">", text_x + text_w - 10, yy + 2)
      end
    end
  end
end

local function draw_boot()
  love.graphics.clear(BG[1], BG[2], BG[3], 1)
  draw_hatch()
  local p = math.min(1, boot_t / BOOT_TIME)
  local ep = ease(p)
  local cy0, cy1 = H/2 - 20, 44
  local ty = cy0 + (cy1 - cy0) * ep
  local sc = 1.0 + (0.55 - 1.0) * ep
  col(YEL_HI, 1)
  love.graphics.setFont(A.font(A.FONT_TITLE, math.floor(34 * sc)))
  local title = "INPUT HOLMES"
  local tw = love.graphics.getFont():getWidth(title)
  love.graphics.print(title, W/2 - tw/2, ty)
  if p < 0.6 then D.glow(W/2, ty + 20, 120 * sc, YEL_HI, 0.7 * (1 - p/0.6)) end
  local mp = math.max(0, math.min(1, (boot_t - 0.55) / 0.35))
  if mp > 0 then
    local ep2 = ease(mp)
    local bx, bw, bh = 30 - 280 * (1 - ep2), 280, 44
    for i, o in ipairs(MENU_OPTS) do
      local y = 140 + (i - 1) * (bh + 12)
      local f = (i == menu_sel)
      col(YEL, (f and 0.16 or 0.06) * mp)
      love.graphics.rectangle("fill", bx, y, bw, bh, 4, 4)
      col(YEL, (f and 1 or 0.6) * mp)
      love.graphics.setLineWidth(f and 2.2 or 1.4)
      love.graphics.rectangle("line", bx + 0.5, y + 0.5, bw - 1, bh - 1, 4, 4)
      love.graphics.setLineWidth(1)
      col(f and YEL_HI or YEL, mp * (f and 1 or 0.85))
      love.graphics.setFont(A.font(A.FONT_BODY_BOLD, 16))
      love.graphics.printf(o.label, bx, y + 12, bw, "center")
    end
  end
  local ha = math.max(0, math.min(1, (boot_t - 0.60) / 0.40))
  if ha > 0 then draw_holmes(520 + (1 - ha) * 60, 210, 0.85, ha) end
  local da = math.max(0, math.min(1, (boot_t - 0.70) / 0.30))
  if da > 0 then draw_balloon(320, 320, 300, 140, da) end
  D.scanlines(W, H, 0.08)
  D.vignette(W, H, 0.65)
end

local function draw_menu()
  love.graphics.clear(BG[1], BG[2], BG[3], 1)
  draw_hatch()
  col(YEL_HI, 1)
  love.graphics.setFont(A.font(A.FONT_TITLE, 22))
  love.graphics.printf("INPUT HOLMES", 0, 38, W, "center")
  col(YEL, 0.65)
  love.graphics.setFont(A.font(A.FONT_MONO, 10))
  love.graphics.printf("// A STUDY IN INPUT MAPPING", 0, 68, W, "center")
  local bx, bw, bh = 30, 280, 44
  for i, o in ipairs(MENU_OPTS) do
    local y = 140 + (i - 1) * (bh + 12)
    local f = (i == menu_sel)
    col(YEL, f and 0.16 or 0.06)
    love.graphics.rectangle("fill", bx, y, bw, bh, 4, 4)
    col(YEL, f and 1 or 0.55)
    love.graphics.setLineWidth(f and 2.2 or 1.4)
    love.graphics.rectangle("line", bx + 0.5, y + 0.5, bw - 1, bh - 1, 4, 4)
    love.graphics.setLineWidth(1)
    col(f and YEL_HI or YEL, f and 1 or 0.8)
    love.graphics.setFont(A.font(A.FONT_BODY_BOLD, 16))
    love.graphics.printf(o.label, bx, y + 12, bw, "center")
  end
  draw_holmes(520, 210, 0.85, 1)
  draw_balloon(320, 320, 300, 140, 1)
  draw_dialogue_text()
  if hasty and hasty_t < QUIP_TIME then
    local a = hasty_t > QUIP_TIME - 0.5 and (QUIP_TIME - hasty_t) / 0.5 or 1
    col(YEL_HI, a * 0.9)
    love.graphics.setFont(A.font(A.FONT_BODY_BOLD, 13))
    love.graphics.printf('"How hasty, by Diana!"', bx, H - Frame.BOTTOM_H - 30, bw, "center")
  end
end

local function draw_badge(cx, cy, r, key)
  BI.draw(cx, cy, r, key)
end

local function draw_test()
  love.graphics.clear(BG[1], BG[2], BG[3], 1)
  draw_hatch()
  local bt = BUTTONS[idx]
  if not bt then return end
  local remaining = math.max(0, T_TEST - timer)
  col(YEL, 0.7)
  love.graphics.setFont(A.font(A.FONT_MONO, 12))
  love.graphics.printf(string.format("%02d / %02d", idx, NB), 0, Frame.TOP_H + 14, W - 20, "right")
  col(YEL_HI, 1)
  love.graphics.setFont(A.font(A.FONT_TITLE, 24))
  love.graphics.printf("Press the following:", 0, 100, W, "center")
  draw_badge(W/2, 200, 46, bt.key)
  col(YEL_HI, 1)
  love.graphics.setFont(A.font(A.FONT_BODY_BOLD, 26))
  love.graphics.printf(bt.label, 0, 258, W, "center")
  local bw, bh = 380, 12
  local bx = (W - bw) / 2
  local by = 320
  col(YEL, 0.25); love.graphics.rectangle("fill", bx, by, bw, bh)
  col(YEL_HI, 1);  love.graphics.rectangle("fill", bx, by, bw * (remaining / T_TEST), bh)
  col(YEL, 1);     love.graphics.rectangle("line", bx + 0.5, by + 0.5, bw - 1, bh - 1)
  col(YEL_HI, 1)
  love.graphics.setFont(A.font(A.FONT_MONO, 22))
  love.graphics.printf(string.format("%.1fs", remaining), 0, by + 22, W, "center")
  col(YEL, 0.7)
  love.graphics.setFont(A.font(A.FONT_MONO, 10))
  love.graphics.print("EVENTS:", 40, 390)
  for i, e in ipairs(events) do
    if i > 5 then break end
    col(YEL_HI, e.matched and 1 or 0.5)
    love.graphics.print(string.format("  %s  %-8s  %s", e.t, e.kind, e.value), 40, 406 + (i - 1) * 12)
  end
  if hasty and hasty_t < QUIP_TIME then
    local a = hasty_t > QUIP_TIME - 0.5 and (QUIP_TIME - hasty_t) / 0.5 or 1
    col(YEL_HI, a)
    love.graphics.setFont(A.font(A.FONT_BODY_BOLD, 14))
    love.graphics.printf('"How hasty, by Diana!"', 0, Frame.TOP_H + 30, W, "center")
  end
end

local function draw_result()
  love.graphics.clear(BG[1], BG[2], BG[3], 1)
  draw_hatch()
  local r = results[#results]
  if not r then return end
  col(YEL_HI, 1)
  love.graphics.setFont(A.font(A.FONT_TITLE, 24))
  love.graphics.printf(r.label, 0, 100, W, "center")
  local c = (r.verdict == "OK") and {0.40,0.90,0.40} or {0.95,0.28,0.22}
  col(c, 1)
  love.graphics.setFont(A.font(A.FONT_TITLE, 30))
  love.graphics.printf(r.verdict, 0, 148, W, "center")
  col(YEL, 1)
  love.graphics.setFont(A.font(A.FONT_MONO, 12))
  love.graphics.print("Events:", 60, 210)
  for i, e in ipairs(r.events) do
    if i > 12 then break end
    col(YEL_HI, e.matched and 1 or 0.6)
    love.graphics.print(string.format("  %s  %-8s  %s", e.t, e.kind, e.value), 60, 228 + (i - 1) * 13)
  end
  col(YEL, 0.75)
  love.graphics.setFont(A.font(A.FONT_MONO, 11))
  love.graphics.printf("Press A to continue", 0, H - Frame.BOTTOM_H - 40, W, "center")
end

local function draw_done()
  love.graphics.clear(BG[1], BG[2], BG[3], 1)
  draw_hatch()
  draw_holmes(140, H/2 + 10, 1.1, 1)
  local bx, by, bw, bh = 300, 140, 300, 180
  draw_balloon(bx, by, bw, bh, 1)
  col(YEL_HI, 1)
  love.graphics.setFont(A.font(A.FONT_BODY_BOLD, 15))
  love.graphics.printf("Case closed, Watsbrobs.", bx + 20, by + 40, bw - 40, "center")
  love.graphics.printf("Session data has been filed.", bx + 20, by + 68, bw - 40, "center")
  col(YEL, 0.7)
  love.graphics.setFont(A.font(A.FONT_MONO, 10))
  love.graphics.printf("Saved: " .. session_ts .. "_session.txt", bx + 20, by + 110, bw - 40, "center")
  col(YEL, 0.75)
  love.graphics.setFont(A.font(A.FONT_MONO, 11))
  love.graphics.printf("Press A to return", 0, H - Frame.BOTTOM_H - 40, W, "center")
end

local function draw_history()
  love.graphics.clear(BG[1], BG[2], BG[3], 1)
  draw_hatch()
  if hist_view then
    col(YEL_HI, 1)
    love.graphics.setFont(A.font(A.FONT_MONO, 11))
    for i = 1, math.min(#hist_view, 22) do
      love.graphics.print(hist_view[i], 24, Frame.TOP_H + 20 + (i - 1) * 14)
    end
    col(YEL, 0.7)
    love.graphics.printf("[B] back", 0, H - Frame.BOTTOM_H - 30, W, "center")
    return
  end
  col(YEL_HI, 1)
  love.graphics.setFont(A.font(A.FONT_TITLE, 22))
  love.graphics.printf("Previous Investigations", 0, 80, W, "center")
  col(YEL, 0.7)
  love.graphics.setFont(A.font(A.FONT_MONO, 12))
  if #hist_files == 0 then
    love.graphics.printf("(no sessions yet)", 0, H/2, W, "center")
  else
    for i, fpath in ipairs(hist_files) do
      local name = fpath:match("([^/]+)$") or fpath
      local focused = (i == hist_sel)
      col(focused and YEL_HI or YEL, focused and 1 or 0.7)
      love.graphics.printf((focused and "> " or "  ") .. name, 40, 130 + (i - 1) * 18, W - 80, "left")
    end
  end
  col(YEL, 0.7)
  love.graphics.printf("[A] open   [B] back", 0, H - Frame.BOTTOM_H - 30, W, "center")
end

local function draw_error_screen()
  love.graphics.clear(0.05, 0.01, 0.01, 1)
  love.graphics.setColor(1, 0.3, 0.3, 1)
  love.graphics.setFont(A.font(A.FONT_BODY_BOLD, 18))
  love.graphics.printf("INPUT HOLMES ERROR", 0, 60, W, "center")
  love.graphics.setFont(A.font(A.FONT_MONO, 10))
  love.graphics.setColor(1, 0.8, 0.8, 1)
  love.graphics.printf(last_error or "?", 30, 100, W - 60, "left")
  love.graphics.setColor(1, 0.6, 0.6, 1)
  love.graphics.setFont(A.font(A.FONT_BODY, 11))
  love.graphics.printf("Press B to return.", 0, H - 80, W, "center")
  love.graphics.printf("(see data/fgd_error.log)", 0, H - 60, W, "center")
end

function S.draw()
  if last_error then draw_error_screen(); return end
  trap(function()
    if     st == "boot"    then draw_boot()
    elseif st == "menu"    then draw_menu()
    elseif st == "test"    then draw_test()
    elseif st == "result"  then draw_result()
    elseif st == "done"    then draw_done()
    elseif st == "history" then draw_history() end
  end)
  if last_error then draw_error_screen(); return end
  trap(function()
    Frame.draw_top("FGD", "input_investigation")
    local hints = {}
    if st == "menu" then hints = {{key="dpad",label="Navigate"},{key="a",label="Select"}}
    elseif st == "result" then hints = {{key="a",label="Continue"}}
    elseif st == "test" then hints = {{key="any",label="Press shown button"}}
    elseif st == "done" then hints = {{key="a",label="Return"}}
    elseif st == "history" then hints = {{key="dpad",label="Select"},{key="a",label="Open"},{key="b",label="Back"}} end
    Frame.draw_bottom(hints)
    D.scanlines(W, H, 0.08)
    D.vignette(W, H, 0.65)
  end)
end

return S
