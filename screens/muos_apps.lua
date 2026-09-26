-- screens/muos_apps.lua -- list of muOS apps in a given /application folder.
-- Icon is taken from the app's glyph/ folder (or first PNG in the folder),
-- total size is computed with du -sk and cached.
local A     = require("core.assets")
local State = require("core.state")
local Input = require("core.input_map")
local Frame = require("ui.frame")
local D     = require("ui.draw")
local sh    = require("core.sh")
local Notify= require("ui.notify")
local ExtImg= require("core.external_image")

local S = {}
local W, H = 640, 480

local ROW_H = 62
local sel       = 1
local scroll    = 0
local max_scroll= 0
local t_enter   = 0
local root      = "/mnt/mmc/MUOS/application"
local apps      = nil
local icon_cache = {}

local function col(c, a) love.graphics.setColor(c[1], c[2], c[3], a or 1) end
local function human(n)
  if not n or n <= 0 then return "0 B" end
  local u = {"B","KB","MB","GB","TB"}; local i = 1
  while n >= 1024 and i < #u do n = n / 1024; i = i + 1 end
  if i == 1 then return string.format("%d %s", n, u[i]) end
  return string.format("%.1f %s", n, u[i])
end
local function trunc(f, s, w)
  if not s then return "" end
  if f:getWidth(s) <= w then return s end
  local o = s
  while #o > 1 and f:getWidth(o .. ".") > w do o = o:sub(1,-2) end
  return o .. "."
end

local function find_app_icon(folder)
  local h = io.popen("ls -1 " .. sh.shq(folder .. "/glyph") .. "/*.png 2>/dev/null | head -1")
  if h then local l = h:read("*l"); h:close(); if l and l ~= "" then return l end end
  h = io.popen("find " .. sh.shq(folder) .. " -maxdepth 1 -name '*.png' 2>/dev/null | head -1")
  if h then local l = h:read("*l"); h:close(); if l and l ~= "" then return l end end
  return nil
end

local function du_kb(path)
  local h = io.popen("du -sk " .. sh.shq(path) .. " 2>/dev/null | cut -f1")
  if not h then return 0 end
  local v = tonumber(h:read("*a") or "0") or 0
  h:close()
  return v * 1024
end

local function scan_apps()
  apps = {}
  icon_cache = {}
  if not sh.is_dir(root) then return end
  local h = io.popen("ls -1d " .. sh.shq(root) .. "/*/ 2>/dev/null")
  if not h then return end
  local list = {}
  for line in h:lines() do
    local name = line:match("([^/]+)/$")
    if name then list[#list+1] = name end
  end
  h:close()
  table.sort(list)
  for _, name in ipairs(list) do
    local full = root .. "/" .. name
    apps[#apps+1] = {
      name = name,
      path = full,
      size = du_kb(full),
      icon = find_app_icon(full),
    }
  end
end

function S.enter()
  t_enter = 0
  sel = 1
  scroll = 0
  root = State.muos_apps_root or "/mnt/mmc/MUOS/application"
  scan_apps()
end
function S.leave() end
function S.update(dt) t_enter = t_enter + dt end

local function move(d)
  if not apps or #apps == 0 then return end
  sel = sel + d
  if sel < 1 then sel = 1 end
  if sel > #apps then sel = #apps end
end

function S.pad(b)
  if     b == Input.UP    or b == Input.L1 then move(-1)
  elseif b == Input.DOWN  or b == Input.R1 then move( 1)
  elseif b == Input.A then
    local a = apps and apps[sel]
    if a then
      State.app_detail_path = a.path
      State.app_detail_name = a.name
      State.app_detail_icon = a.icon
      State.app_detail_size = a.size
      State.app_detail_root = root
      State.go("app_detail")
    end
  elseif b == Input.B or b == Input.SELECT then State.back() end
end
function S.hat(dir)
  if     dir == "up"   then move(-1)
  elseif dir == "down" then move( 1) end
end
function S.key(k)
  if     k == "up"    then move(-1)
  elseif k == "down"  then move( 1)
  elseif k == "return" or k == "space" then S.pad(Input.A)
  elseif k == "escape" or k == "backspace" then State.back() end
end

local function draw_icon_fallback(cx, cy, r, acc)
  col(acc, 0.9)
  love.graphics.setLineWidth(1.8)
  for i = 0, 2 do
    for j = 0, 2 do
      love.graphics.rectangle("line",
        cx - r*0.85 + i * r*0.62, cy - r*0.85 + j * r*0.62,
        r*0.5, r*0.5, 1, 1)
    end
  end
  love.graphics.setLineWidth(1)
end

local function draw_row(a, y, focused, idx)
  local th = State.theme
  local x = 20
  local w = W - 40
  local acc = {0.55, 0.85, 0.45}

  if focused then
    col({acc[1]*0.18, acc[2]*0.18, acc[3]*0.18}, 0.95)
    love.graphics.rectangle("fill", x, y, w, ROW_H - 4, 4, 4)
    col(acc, 0.95)
    love.graphics.setLineWidth(1.8)
    love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, ROW_H - 5, 4, 4)
    love.graphics.setLineWidth(1)
    col(acc, 1)
    love.graphics.rectangle("fill", x, y + 6, 3, ROW_H - 16)
  else
    col({0.030, 0.026, 0.022}, 0.85)
    love.graphics.rectangle("fill", x, y, w, ROW_H - 4, 4, 4)
    col(acc, 0.28)
    love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, ROW_H - 5, 4, 4)
  end

  -- icon
  local icon_cx = x + 32
  local icon_cy = y + ROW_H/2 - 2
  local icon_r  = 20
  col({acc[1]*0.20, acc[2]*0.20, acc[3]*0.20}, 0.95)
  love.graphics.circle("fill", icon_cx, icon_cy, icon_r)
  col(acc, 0.9)
  love.graphics.circle("line", icon_cx, icon_cy, icon_r)

  if a.icon and not icon_cache[a.path] then
    icon_cache[a.path] = ExtImg.load(a.icon)
  end
  local img = a.icon and icon_cache[a.path]
  if img then
    local iw, ih = img:getDimensions()
    local sc = (icon_r * 1.6) / math.max(iw, ih)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(img, icon_cx - iw*sc/2, icon_cy - ih*sc/2, 0, sc, sc)
    love.graphics.setColor(1, 1, 1, 1)
  else
    draw_icon_fallback(icon_cx, icon_cy, icon_r * 0.6, acc)
  end

  -- name
  love.graphics.setFont(A.font(A.FONT_BODY_BOLD, 13))
  col(focused and {1,1,1} or th.text, 1)
  love.graphics.print(trunc(love.graphics.getFont(), a.name, w - 60), x + 62, y + 10)

  -- size
  love.graphics.setFont(A.font(A.FONT_MONO, 10))
  col(th.text_dim, 0.85)
  love.graphics.print("size", x + 62, y + 30)
  col(acc, 0.95)
  love.graphics.print(human(a.size), x + 90, y + 30)

  -- index
  love.graphics.setFont(A.font(A.FONT_MONO, 9))
  col(acc, 0.55)
  love.graphics.printf(string.format("%02d", idx), x, y + 10, w - 12, "right")
end

function S.draw()
  local th = State.theme
  D.bg()
  col(th.grid_faint, 0.08)
  for gy = Frame.TOP_H, H - Frame.BOTTOM_H, 16 do
    for gx = 0, W, 16 do love.graphics.rectangle("fill", gx, gy, 1, 1) end
  end

  local vp_y = Frame.TOP_H + 4
  local vp_h = H - Frame.TOP_H - Frame.BOTTOM_H - 8

  if not apps then
    col(th.text_dim, 0.8)
    love.graphics.setFont(A.font(A.FONT_BODY, 12))
    love.graphics.printf("scanning...", 0, vp_y + vp_h/2, W, "center")
  elseif #apps == 0 then
    col(th.text_dim, 0.8)
    love.graphics.setFont(A.font(A.FONT_BODY, 12))
    love.graphics.printf("no apps found in\n" .. root, 0, vp_y + vp_h/2 - 16, W, "center")
  else
    local row_step = ROW_H + 4
    local content_h = #apps * row_step
    max_scroll = math.max(0, content_h - vp_h)

    if (sel - 1) * row_step < scroll then scroll = (sel - 1) * row_step end
    if sel * row_step > scroll + vp_h then scroll = sel * row_step - vp_h end
    scroll = math.max(0, math.min(max_scroll, scroll))

    love.graphics.setScissor(0, vp_y, W, vp_h)
    local y = vp_y - scroll
    for i, a in ipairs(apps) do
      draw_row(a, y, i == sel, i)
      y = y + row_step
    end
    love.graphics.setScissor()
  end

  Frame.draw_top("FGD", "plugins")
  Frame.draw_bottom({
    { key = "up", label = "Move" },
    { key = "a",  label = "Open" },
    { key = "b",  label = "Back" },
  })
  D.scanlines(W, H, 0.06)
end

return S
