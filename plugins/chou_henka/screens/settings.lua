-- screens/settings.lua -- 5-tab settings panel
local A = require("core.assets")
local D = require("ui.draw")
local Input = require("core.input_map")
local T = require("plugins.chou_henka.ui.theme")
local CFG = require("plugins.chou_henka.core.config")
local PB = require("plugins.chou_henka.core.playback")
local LIB = require("plugins.chou_henka.core.library")
local Notify = require("ui.notify")
local Icons = require("plugins.chou_henka.ui.icons")
local M = {}
local W, H = 640, 480
local TABS = {
  { id="appearance", label="APPEARANCE" },
  { id="library",    label="LIBRARY" },
  { id="engine",     label="ENGINE" },
  { id="sources",    label="SOURCES" },
  { id="scraper",    label="SCRAPER" },
  { id="about",      label="ABOUT" },
}
local cur_tab, sel, scroll, t = 1, 1, 0, 0
local function col(c,a) love.graphics.setColor(c[1],c[2],c[3],a or 1) end
-- NOTE: `icon` is an optional key from plugins.chou_henka.ui.icons (e.g.
-- "star", "clock", "gear"). It used to be silently mis-passed as a bogus
-- extra argument to on_change/danger in a few rows below (crash-on-toggle
-- for anything landing in `on_change`); it's now a real, dedicated slot
-- that the row renderer in M.draw() actually uses.
local function tog(label,hint,sec,key,default,icon,on_change)
  return { kind="toggle", label=label, hint=hint, icon=icon,
    get=function() local v=CFG.get(sec,key); if v==nil then return default end; return v==true end,
    toggle=function() local v=CFG.get(sec,key); if v==nil then v=default end
      CFG.set(sec,key,not v); CFG.save()
      if on_change then on_change(not v) end end }
end
local function enu(label,hint,sec,key,options,default,on_change)
  return { kind="enum", label=label, hint=hint,
    get=function() local v=CFG.get(sec,key); if v==nil or v=="" then return default end; return v end,
    cycle=function(dir)
      local cur=CFG.get(sec,key); if cur==nil or cur=="" then cur=default end
      local i=1; for k,v in ipairs(options) do if v==cur then i=k end end
      i=((i-1+dir)%#options+#options)%#options+1
      CFG.set(sec,key,options[i]); CFG.save()
      if on_change then on_change(options[i]) end
    end }
end
local function sld(label,hint,sec,key,minv,maxv,step,fmt,default,icon)
  return { kind="slider", label=label, hint=hint, fmt=fmt, icon=icon,
    get=function() local v=CFG.get(sec,key); if v==nil then return default end; return v end,
    cycle=function(dir)
      local v=CFG.get(sec,key); if v==nil then v=default end
      v=v+dir*step; if v<minv then v=minv end; if v>maxv then v=maxv end
      CFG.set(sec,key,v); CFG.save()
    end }
end
local function act(label,hint,fn,danger,icon)
  return { kind="action", label=label, hint=hint, act=fn, danger=danger, icon=icon }
end
local function inf(label,get_fn) return { kind="info", label=label, get=get_fn } end
local function build_rows()
  local tab = TABS[cur_tab].id
  local r = {}
  if tab == "appearance" then
    r[#r+1] = { kind="header", label="THEME" }
    r[#r+1] = { kind="enum", label="Color theme", hint="predefined palettes",
      get=function() return CFG.get("ui","theme") or "neon" end,
      cycle=function(dir) T.cycle(dir) end }
    r[#r+1] = { kind="enum", label="Layout", hint="home / library view",
      get=function() return CFG.get("ui","layout") or "tiles" end,
      cycle=function(dir)
        local cur = CFG.get("ui","layout") or "tiles"
        local order = { "tiles","list","compact" }
        local i = 1; for k,v in ipairs(order) do if v==cur then i=k end end
        i = ((i-1+dir)%#order+#order)%#order+1
        CFG.set("ui","layout",order[i]); CFG.save()
      end }
    r[#r+1] = { kind="header", label="INTERFACE" }
    r[#r+1] = tog("Show clock","clock in top bar","ui","show_clock",true)
    r[#r+1] = tog("Show stats","media count in header","ui","show_stats",true)
    r[#r+1] = tog("Animations","smooth transitions","ui","animations",true)
  elseif tab == "library" then
    r[#r+1] = { kind="header", label="CATEGORIES" }
    for _, cat in ipairs(LIB.CAT_ORDER) do
      local c = LIB.categories[cat]
      r[#r+1] = { kind="toggle",
        label=c.label,
        hint=cat,
        get=function() return LIB.is_enabled(cat) end,
        toggle=function() LIB.set_enabled(cat, not LIB.is_enabled(cat)) end }
    end
    r[#r+1] = { kind="header", label="COMIC HANDLER" }
    r[#r+1] = enu("Comic reader","which plugin opens CBZ/CBR/CB7",
      "library","comic_handler",
      {"comic_reader","gdx_library"},"comic_reader")
    r[#r+1] = { kind="header", label="SCAN BEHAVIOR" }
    r[#r+1] = tog("Auto scan on boot","scan on plugin open",
      "library","auto_scan_boot",false)
    r[#r+1] = sld("Max depth","scan depth",
      "library","scan_max_depth",2,12,1,function(v) return tostring(v) end,6)
    r[#r+1] = { kind="header", label="ACTIONS" }
    r[#r+1] = act("Scan now","reindex libraries",function()
      local ok, err = LIB.start_scan()
      if not ok then Notify.show("error", err or "cannot scan") end
    end)
    r[#r+1] = act("Clear library DB","forget every indexed file",function()
      LIB.clear(); Notify.show("info","library cleared")
    end,true)
  elseif tab == "engine" then
    r[#r+1] = { kind="header", label="ENGINE" }
    r[#r+1] = { kind="enum", label="Preset", hint="EQ + filters",
      get=function() return PB.current_engine() end,
      cycle=function(dir) PB.cycle_engine(dir) end }
    r[#r+1] = { kind="header", label="PLAYBACK" }
    r[#r+1] = sld("Volume","0..200","player","volume",0,200,5,
      function(v) return v.."%" end,70)
    r[#r+1] = sld("Speed","0.25x..4.0x","player","speed",25,400,25,
      function(v) return string.format("%.2fx", v/100) end,100)
    r[#r+1] = tog("Gapless playback","continuous playback","player","gapless",true)
    r[#r+1] = { kind="header", label="VIDEO" }
    r[#r+1] = enu("Video output","vo backend","player","video_vo",
      {"sdl","gpu","drm","xv"},"sdl")
    r[#r+1] = enu("HW decode","hwdec","player","video_hwdec",
      {"auto","v4l2request","v4l2m2m","none"},"auto")
  elseif tab == "sources" then
    r[#r+1] = { kind="header", label="LIBRARY SOURCES" }
    local srcs = CFG.get("sources") or {}
    for i, s in ipairs(srcs) do
      r[#r+1] = { kind="source", label=s, idx=i,
        remove=function()
          local list = CFG.get("sources") or {}
          table.remove(list, i)
          CFG.set_sources(list)
          Notify.show("info","source removed")
        end }
    end
    r[#r+1] = { kind="header", label="ADD NEW" }
    r[#r+1] = act("Add source...","choose folder manually",function()
      local KB = require("ui.keyboard")
      KB.open({ title="Add media source", initial="/mnt/mmc/",
        on_accept=function(t2)
          if not t2 or t2 == "" then return end
          local list = CFG.get("sources") or {}
          list[#list+1] = t2
          CFG.set_sources(list)
          Notify.show("success","added: "..t2)
        end })
    end)
    r[#r+1] = act("Add default sources","SD1 + SD2 media folders",function()
      local list = CFG.get("sources") or {}
      for _, s in ipairs({"/mnt/mmc/Music","/mnt/mmc/Videos","/mnt/mmc/Books",
                          "/mnt/sdcard/Music","/mnt/sdcard/Videos"}) do
        local has=false; for _,x in ipairs(list) do if x==s then has=true end end
        if not has then list[#list+1] = s end
      end
      CFG.set_sources(list); Notify.show("success","default sources added")
    end)
  elseif tab == "scraper" then
    r[#r+1] = { kind="header", label="METADATA SCRAPER" }
    r[#r+1] = tog("Enable scraper","scarica metadata online (TMDB)",
      "scraper","enabled",false,"search")
    r[#r+1] = { kind="enum", label="TMDB API key", hint="incolla la tua API key",
      icon="info",
      get=function() return CFG.get("scraper","tmdb_api_key") or "(vuota)" end,
      cycle=function(dir)
        local KB = require("ui.keyboard")
        KB.open({ title="TMDB API key",
          initial=CFG.get("scraper","tmdb_api_key") or "",
          on_accept=function(s)
            CFG.set("scraper","tmdb_api_key", s or ""); CFG.save()
            require("ui.notify").show("success","API key salvata")
          end })
      end }
    r[#r+1] = tog("Prefer local NFO","usa .nfo prima di TMDB",
      "scraper","prefer_local_nfo",true,"doc")
    r[#r+1] = tog("Fetch posters","scarica poster e fanart",
      "scraper","fetch_posters",true,"image")
    r[#r+1] = { kind="header", label="WATCH STATE" }
    r[#r+1] = tog("Resume playback","riprendi da dove eri rimasto",
      "watch","resume_enabled",true,"clock")
    r[#r+1] = sld("Watched threshold","% per marcare come visto",
      "watch","watched_threshold",50,100,5,
      function(v) return v .. "%" end,90,"star")
    r[#r+1] = sld("Resume minimum","% minimo per salvare resume",
      "watch","resume_min_pct",1,20,1,
      function(v) return v .. "%" end,2,"clock")
    r[#r+1] = { kind="header", label="ACTIONS" }
    r[#r+1] = act("Clear watch state","reset resume, watched, favorites",function()
      local WS = require("plugins.chou_henka.core.watchstate")
      WS.clear_all()
      require("ui.notify").show("warning","watch state cleared")
    end, true, "gear")
  elseif tab == "about" then
    r[#r+1] = { kind="header", label="CHOU HENKA MC" }
    r[#r+1] = inf("Version",function()
      -- single source of truth: plugins/chou_henka/plugin.lua
      local ok, P = pcall(require, "plugins.chou_henka.plugin")
      return "v" .. ((ok and P.version) or "2.1.0")
    end)
    r[#r+1] = inf("Author",function() return "sirpips / SPDW" end)
    r[#r+1] = inf("Engine",function() return "mpv + LÖVE 11.5" end)
    r[#r+1] = { kind="header", label="STATS" }
    r[#r+1] = inf("Library entries",function() return tostring(#(LIB.tracks() or {})) end)
    r[#r+1] = inf("Last scan",function()
      local s = LIB.scanned_at()
      if s == 0 then return "never" end
      return os.date("%Y-%m-%d %H:%M", s)
    end)
    r[#r+1] = { kind="header", label="DANGER" }
    r[#r+1] = act("Reset all settings","restore defaults",function()
      CFG.reset(); Notify.show("warning","settings reset")
    end,true)
  end
  return r
end
local function cur_rows() return build_rows() end
local function cur_row() return cur_rows()[sel] end
local function is_header(i)
  local rr = cur_rows()[i]; return rr and rr.kind == "header"
end
local function skip_header(dir)
  local n = #cur_rows(); if n == 0 then return end
  if not is_header(sel) then return end
  for _ = 1, n do
    sel = sel + dir
    if sel < 1 then sel = 1; dir = 1 end
    if sel > n then sel = n; dir = -1 end
    if not is_header(sel) then return end
  end
end
function M.enter() cur_tab, sel, scroll, t = 1, 1, 0, 0; CFG.load(); skip_header(1) end
function M.leave() end
function M.update(dt) t = t + dt end
local function move(d)
  local n = #cur_rows(); if n == 0 then return end
  local i = sel
  for _ = 1, n do
    i = i + d
    if i < 1 then i = n end
    if i > n then i = 1 end
    if not is_header(i) then sel = i; return end
  end
end
function M.pad(b)
  if b == Input.B or b == Input.SELECT then return "back" end
  if b == Input.UP then move(-1)
  elseif b == Input.DOWN then move(1)
  elseif b == Input.L1 then cur_tab = math.max(1, cur_tab - 1); sel = 1; skip_header(1)
  elseif b == Input.R1 then cur_tab = math.min(#TABS, cur_tab + 1); sel = 1; skip_header(1)
  elseif b == Input.LEFT or b == Input.RIGHT then
    local rr = cur_row()
    if rr and rr.cycle then rr.cycle(b == Input.RIGHT and 1 or -1)
    elseif rr and rr.kind == "toggle" and rr.toggle then rr.toggle() end
  elseif b == Input.A then
    local rr = cur_row(); if not rr then return end
    if rr.kind == "toggle" and rr.toggle then rr.toggle()
    elseif rr.cycle then rr.cycle(1)
    elseif rr.kind == "action" and rr.act then rr.act() end
  elseif b == Input.X then
    local rr = cur_row()
    if rr and rr.kind == "source" and rr.remove then rr.remove() end
  end
  return false
end
function M.hat(dir)
  if dir == "up" then move(-1) elseif dir == "down" then move(1)
  elseif dir == "left" then M.pad(Input.LEFT)
  elseif dir == "right" then M.pad(Input.RIGHT) end
end
function M.key(k)
  if k == "escape" then return "back" end
  if k == "up" then move(-1) elseif k == "down" then move(1)
  elseif k == "left" then M.pad(Input.LEFT)
  elseif k == "right" then M.pad(Input.RIGHT)
  elseif k == "return" or k == "space" then M.pad(Input.A) end
  return false
end
local function draw_tab_bar()
  local th = T.current()
  local n = #TABS
  local x, y = 20, 76
  local w = W - 40
  local gap = 4
  local tw = (w - (n - 1) * gap) / n
  for i, tb in ipairs(TABS) do
    local tx = x + (i - 1) * (tw + gap)
    local focused = (i == cur_tab)
    if focused then
      col(th.accent, 0.22)
      love.graphics.rectangle("fill", tx, y, tw, 24, 3, 3)
      col(th.accent_hi, 0.95); love.graphics.setLineWidth(1.4)
      love.graphics.rectangle("line", tx + 0.5, y + 0.5, tw - 1, 23, 3, 3)
      love.graphics.setLineWidth(1)
    else
      col(th.panel, 0.7)
      love.graphics.rectangle("fill", tx, y, tw, 24, 3, 3)
      col(th.accent, 0.30)
      love.graphics.rectangle("line", tx + 0.5, y + 0.5, tw - 1, 23, 3, 3)
    end
    love.graphics.setFont(A.font(A.FONT_MONO, 9))
    col(focused and {1,1,1} or th.text_dim, 1)
    love.graphics.printf(tb.label, tx, y + 7, tw, "center")
  end
end
function M.draw()
  local th = T.current()
  D.bg()
  col(th.accent, 0.05)
  for y = 30, H - 20, 20 do for x = 0, W, 20 do
    love.graphics.rectangle("fill", x, y, 1, 1)
  end end
  love.graphics.setFont(A.font(A.FONT_TITLE, 18))
  col(th.accent_hi, 1)
  love.graphics.printf("CHOU HENKA — SETTINGS", 0, 42, W, "center")
  draw_tab_bar()
  local rows = cur_rows()
  local y0 = 110
  local vp_h = H - 40 - y0
  local row_h = 42
  local vis = math.floor(vp_h / row_h)
  if sel > vis then scroll = (sel - vis) * row_h else scroll = 0 end
  love.graphics.setScissor(20, y0, W - 40, vp_h)
  for i, rr in ipairs(rows) do
    local y = y0 + (i - 1) * row_h - scroll
    if y + row_h > y0 and y < y0 + vp_h then
      local focused = (i == sel)
      if rr.kind == "header" then
        love.graphics.setFont(A.font(A.FONT_MONO, 10))
        col(th.accent, 0.9)
        love.graphics.print(rr.label, 28, y + 4)
        col(th.accent, 0.3)
        love.graphics.rectangle("fill", 28, y + 20, W - 56, 1)
      else
        if focused then
          col(th.accent, 0.15)
          love.graphics.rectangle("fill", 24, y, W - 48, row_h - 4, 3, 3)
          col(th.accent, 0.9); love.graphics.setLineWidth(1.4)
          love.graphics.rectangle("line", 24.5, y + 0.5, W - 49, row_h - 5, 3, 3)
          love.graphics.setLineWidth(1)
        end
        local label_x = 36
        if rr.icon then
          Icons.draw(rr.icon, 28, y + 13, 8,
            focused and th.accent_hi or th.text_dim, focused and 1 or 0.75)
          label_x = 50
        end
        love.graphics.setFont(A.font(A.FONT_BODY_BOLD, 12))
        col(focused and {1,1,1} or th.text, 1)
        love.graphics.print(rr.label or "?", label_x, y + 6)
        if rr.hint then
          love.graphics.setFont(A.font(A.FONT_BODY, 9))
          col(th.text_dim, 0.75)
          love.graphics.print(rr.hint, label_x, y + 22)
        end
        local vtxt, vc
        if rr.kind == "toggle" then
          local on = rr.get and rr.get() or false
          vtxt, vc = on and "ON" or "OFF", on and th.ok or th.err
        elseif rr.kind == "slider" or rr.kind == "enum" then
          local v = rr.get and rr.get() or "-"
          if rr.kind == "slider" and rr.fmt then v = rr.fmt(v) end
          vtxt, vc = tostring(v), th.accent_hi
        elseif rr.kind == "action" then vtxt, vc = "RUN", th.warn
        elseif rr.kind == "info" then
          vtxt, vc = tostring(rr.get and rr.get() or "-"), th.text_dim
        elseif rr.kind == "source" then vtxt, vc = "X=remove", th.warn
        end
        if vtxt then
          love.graphics.setFont(A.font(A.FONT_MONO, 10))
          col(vc, focused and 1 or 0.75)
          love.graphics.printf(vtxt, 0, y + 14, W - 34, "right")
        end
      end
    end
  end
  love.graphics.setScissor()
end
return M
