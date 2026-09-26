-- screens/web_browser.lua -- Web View: mini-browser for local HTML files.
local A     = require("core.assets")
local State = require("core.state")
local Input = require("core.input_map")
local Frame = require("ui.frame")
local D     = require("ui.draw")
local sh    = require("core.sh")
local Notify= require("ui.notify")
local PathSel = require("ui.path_selector")

local S = {}
local W, H = 640, 480
local acc = {0.30, 0.85, 0.95}

local items = {}
local sel = 1
local scroll = 0
local max_scroll = 0
local roots = {
  "/mnt/mmc/Documents", "/mnt/mmc/Downloads", "/mnt/mmc/Books",
  "/mnt/sdcard/Documents", "/mnt/sdcard/Downloads",
  os.getenv("HOME") .. "/Documents",
  os.getenv("HOME") .. "/Downloads",
}
local t_enter = 0

local function col(c, a) love.graphics.setColor(c[1], c[2], c[3], a or 1) end
local function basename(p) return (p or ""):match("([^/]+)$") or p or "?" end

local custom_paths = {}

local function scan()
  items = {}
  local seen = {}
  local all_roots = {}
  for _, r in ipairs(roots) do all_roots[#all_roots+1] = r end
  for _, p in ipairs(custom_paths) do all_roots[#all_roots+1] = p end
  for _, r in ipairs(all_roots) do
    if sh.is_dir(r) then
      local h = io.popen("find " .. sh.shq(r) ..
        " -maxdepth 3 -type f \\( -iname '*.html' -o -iname '*.htm' \\) 2>/dev/null | sort | head -200")
      if h then
        for line in h:lines() do
          if line ~= "" and not seen[line] then
            seen[line] = true
            items[#items+1] = { path = line, name = basename(line) }
          end
        end
        h:close()
      end
    end
  end
  table.sort(items, function(a, b) return a.name:lower() < b.name:lower() end)
end

function S.enter()
  t_enter = 0
  sel = 1; scroll = 0
  scan()
end
function S.leave() end
function S.update(dt) t_enter = t_enter + dt end

function S.pad(b)
  if #items == 0 then
    PathSel.pad(b, {
      paths = roots,
      on_rescan = function() scan() end,
      on_pick = function(p)
        table.insert(custom_paths, 1, p)
        scan()
        Notify.show("info", "custom folder added")
      end,
      on_back = function() State.back() end,
    })
    return
  end
  if     b == Input.UP   then sel = math.max(1, sel - 1)
  elseif b == Input.DOWN then sel = math.min(#items, sel + 1)
  elseif b == Input.L1   then sel = math.max(1, sel - 8)
  elseif b == Input.R1   then sel = math.min(#items, sel + 8)
  elseif b == Input.A    then
    State.net_sphere_path = items[sel].path
    State.go("net_sphere")
  elseif b == Input.B or b == Input.SELECT then State.back() end
end
function S.hat(dir)
  if     dir == "up"   then sel = math.max(1, sel - 1)
  elseif dir == "down" then sel = math.min(#items, sel + 1) end
end
function S.key(k)
  if     k == "up"   then sel = math.max(1, sel - 1)
  elseif k == "down" then sel = math.min(#items, sel + 1)
  elseif k == "return" or k == "space" then S.pad(Input.A)
  elseif k == "escape" or k == "backspace" then S.pad(Input.B) end
end

function S.draw()
  local th = State.theme
  D.bg()
  col(acc, 0.06)
  for gy = Frame.TOP_H, H - Frame.BOTTOM_H, 18 do
    for gx = 0, W, 18 do love.graphics.rectangle("fill", gx, gy, 1, 1) end
  end

  love.graphics.setFont(A.font(A.FONT_TITLE, 20))
  col(acc, 1)
  love.graphics.printf("WEB VIEW", 0, Frame.TOP_H + 8, W, "center")

  love.graphics.setFont(A.font(A.FONT_MONO, 10))
  col(acc, 0.75)
  love.graphics.printf("// local HTML files -- " .. #items .. " found",
    0, Frame.TOP_H + 34, W, "center")

  local vp_y = Frame.TOP_H + 54
  local vp_h = H - Frame.BOTTOM_H - vp_y - 4

  if #items == 0 then
    PathSel.draw({
      title = "WEB VIEW",
      message = "No HTML files found.\n\n" ..
                "Copy your .html or .htm files into one of the folders listed " ..
                "below, or add a custom folder with Y.\n\n" ..
                "Press X to rescan.\nPress Y to add a custom folder.\nPress B to go back.",
      paths = roots,
      accent = acc,
      on_rescan = function() scan() end,
      on_pick = function(p)
        table.insert(custom_paths, 1, p)
        scan()
        Notify.show("info", "custom folder added")
      end,
      on_back = function() State.back() end,
    })
    return
  end

  local row_h = 40
  local total_h = #items * row_h
  max_scroll = math.max(0, total_h - vp_h)
  local sel_top = (sel - 1) * row_h
  local sel_bot = sel_top + row_h
  if sel_top < scroll then scroll = sel_top end
  if sel_bot > scroll + vp_h then scroll = sel_bot - vp_h end
  scroll = math.max(0, math.min(max_scroll, scroll))

  love.graphics.setScissor(0, vp_y, W, vp_h)
  local y = vp_y - scroll
  for i, it in ipairs(items) do
    local focused = (i == sel)
    local ry = vp_y + (i - 1) * row_h - scroll
    if ry + row_h > vp_y and ry < vp_y + vp_h then
      if focused then
        col(acc, 0.20)
        love.graphics.rectangle("fill", 20, ry + 2, W - 40, row_h - 6, 3, 3)
        col(acc, 0.9)
        love.graphics.setLineWidth(1.4)
        love.graphics.rectangle("line", 20.5, ry + 2.5, W - 41, row_h - 7, 3, 3)
        love.graphics.setLineWidth(1)
      end

      love.graphics.setFont(A.font(focused and A.FONT_BODY_BOLD or A.FONT_BODY, 12))
      col(focused and {1,1,1} or th.text, 1)
      love.graphics.print(it.name, 34, ry + 8)

      love.graphics.setFont(A.font(A.FONT_MONO, 9))
      col(th.text_dim, 0.8)
      love.graphics.print(it.path, 34, ry + 24)
    end
  end
  love.graphics.setScissor()

  if max_scroll > 0 then
    local track_h = vp_h - 4
    local thumb_h = math.max(20, track_h * (vp_h / total_h))
    local thumb_y = vp_y + (track_h - thumb_h) * (scroll / max_scroll)
    col(acc, 0.55)
    love.graphics.rectangle("fill", W - 6, thumb_y, 3, thumb_h, 1, 1)
  end

  Frame.draw_top("FGD", "plugins")
  Frame.draw_bottom({
    { key = "up",  label = "Move" },
    { key = "a",   label = "Render" },
    { key = "b",   label = "Back" },
  })
  D.scanlines(W, H, 0.06)
end

return S
