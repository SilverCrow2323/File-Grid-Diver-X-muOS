-- screens/screenshot_gallery.lua -- Screenshot Gallery plugin.
local A     = require("core.assets")
local State = require("core.state")
local Input = require("core.input_map")
local Frame = require("ui.frame")
local D     = require("ui.draw")
local Notify= require("ui.notify")
local Modal = require("ui.modal")
local ExtImg= require("core.external_image")
local sh    = require("core.sh")
local PathSel = require("ui.path_selector")

local S = {}
local W, H = 640, 480
local acc = {0.48, 0.80, 0.90}

local items = {}
local sel = 1
local scroll = 0
local cache = {}
local fullscreen = false
local t_enter = 0

local custom_paths = {}

local SCREEN_DIRS = {
  "/run/muos/storage/screenshot",
  "/run/muos/storage/screenshots",
  "/mnt/mmc/screenshots",
  "/mnt/mmc/Screenshots",
  "/mnt/sdcard/screenshots",
  "/mnt/sdcard/Screenshots",
  "/mnt/mmc/retroarch/screenshots",
}

local function col(c, a) love.graphics.setColor(c[1], c[2], c[3], a or 1) end

local function scan()
  items = {}
  cache = {}
  local seen = {}
  local dirs = {}
  for _, d in ipairs(SCREEN_DIRS) do dirs[#dirs+1] = d end
  for _, p in ipairs(custom_paths) do dirs[#dirs+1] = p end
  for _, dir in ipairs(dirs) do
    if sh.is_dir(dir) then
      local h = io.popen("find " .. sh.shq(dir) ..
        " -maxdepth 2 -type f \\( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \\) 2>/dev/null | sort -r | head -200")
      if h then
        for line in h:lines() do
          if line ~= "" and not seen[line] then
            seen[line] = true
            items[#items + 1] = { path = line, name = line:match("([^/]+)$") or "?" }
          end
        end
        h:close()
      end
    end
  end
end

local function get_thumb(path)
  if cache[path] then return cache[path] end
  local img = ExtImg.load(path)
  cache[path] = img or false
  return cache[path]
end

function S.enter()
  t_enter = 0
  sel = 1
  scroll = 0
  fullscreen = false
  scan()
end
function S.leave() end
function S.update(dt) t_enter = t_enter + dt end

function S.pad(b)
  if fullscreen then
    if b == Input.B or b == Input.A or b == Input.SELECT then fullscreen = false end
    return
  end
  if #items == 0 then
    PathSel.pad(b, {
      paths = SCREEN_DIRS,
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
  if #items == 0 then
    PathSel.pad(b, {
      paths = SCREEN_DIRS,
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
  if Modal.is_open() then
    if b == Input.A then Modal.accept()
    elseif b == Input.B then Modal.cancel() end
    return
  end
  if #items == 0 then
    if b == Input.B or b == Input.SELECT then State.back() end
    return
  end
  if     b == Input.LEFT  then sel = math.max(1, sel - 1)
  elseif b == Input.RIGHT then sel = math.min(#items, sel + 1)
  elseif b == Input.UP    then sel = math.max(1, sel - 4)
  elseif b == Input.DOWN  then sel = math.min(#items, sel + 4)
  elseif b == Input.A     then fullscreen = true
  elseif b == Input.X then
    local it = items[sel]
    if it then
      Modal.show("Delete screenshot", "Remove " .. it.name .. "?",
        { accept_label = "DELETE", cancel_label = "CANCEL",
          accept_color = {0.95, 0.35, 0.30},
          on_accept = function()
            os.remove(it.path)
            cache[it.path] = nil
            table.remove(items, sel)
            if sel > #items then sel = math.max(1, #items) end
            Notify.show("info", "deleted")
          end })
    end
  elseif b == Input.Y then scan(); Notify.show("info", "rescan done")
  elseif b == Input.B or b == Input.SELECT then State.back() end
end

function S.hat(dir)
  if fullscreen then return end
  if     dir == "left"  then sel = math.max(1, sel - 1)
  elseif dir == "right" then sel = math.min(#items, sel + 1)
  elseif dir == "up"    then sel = math.max(1, sel - 4)
  elseif dir == "down"  then sel = math.min(#items, sel + 4) end
end

function S.key(k)
  if fullscreen then
    if k == "escape" or k == "return" then fullscreen = false end
    return
  end
  if     k == "escape" or k == "backspace" then S.pad(Input.B)
  elseif k == "left"  then S.pad(Input.LEFT)
  elseif k == "right" then S.pad(Input.RIGHT)
  elseif k == "up"    then S.pad(Input.UP)
  elseif k == "down"  then S.pad(Input.DOWN)
  elseif k == "x"     then S.pad(Input.X)
  elseif k == "y"     then S.pad(Input.Y)
  elseif k == "return" or k == "space" then S.pad(Input.A) end
end

function S.draw()
  local th = State.theme
  D.bg()

  if fullscreen then
    local it = items[sel]
    if not it then fullscreen = false; return end
    local img = get_thumb(it.path)
    if img then
      local iw, ih = img:getDimensions()
      local sc = math.min(W / iw, H / ih)
      love.graphics.setColor(0, 0, 0, 1)
      love.graphics.rectangle("fill", 0, 0, W, H)
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(img, (W - iw*sc)/2, (H - ih*sc)/2, 0, sc, sc)
    end
    -- Info strip
    love.graphics.setColor(0, 0, 0, 0.7)
    love.graphics.rectangle("fill", 0, H - 30, W, 30)
    love.graphics.setFont(A.font(A.FONT_MONO, 10))
    col(acc, 1)
    love.graphics.print(it.name, 12, H - 22)
    love.graphics.printf(sel .. " / " .. #items, 0, H - 22, W - 12, "right")
    Frame.draw_bottom({ { key = "b", label = "Close" } })
    return
  end

  col(acc, 0.06)
  for gy = Frame.TOP_H, H - Frame.BOTTOM_H, 18 do
    for gx = 0, W, 18 do love.graphics.rectangle("fill", gx, gy, 1, 1) end
  end

  love.graphics.setFont(A.font(A.FONT_TITLE, 20))
  col(acc, 1)
  love.graphics.printf("SCREENSHOT GALLERY", 0, Frame.TOP_H + 8, W, "center")

  love.graphics.setFont(A.font(A.FONT_MONO, 10))
  col(acc, 0.75)
  love.graphics.printf(#items .. " screenshots", 0, Frame.TOP_H + 34, W, "center")

  local vp_y = Frame.TOP_H + 54
  local vp_h = H - Frame.BOTTOM_H - vp_y - 4

  if #items == 0 then
    PathSel.draw({
      title = "SCREENSHOT GALLERY",
      message = "No screenshots found.\n\n" ..
                "This gallery scans the screenshot folders used by RetroArch, " ..
                "muOS and standalone emulators.\n\n" ..
                "Press X to rescan.\nPress Y to add a custom folder.\nPress B to go back.",
      paths = SCREEN_DIRS,
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

  local cols = 4
  local cell_w = (W - 40 - (cols - 1) * 6) / cols
  local cell_h = cell_w * 0.7
  local row_h = cell_h + 6
  local rows_vis = math.max(1, math.floor(vp_h / row_h))
  local per_page = cols * rows_vis
  local sel_row = math.floor((sel - 1) / cols)
  local top_row = math.floor(scroll / cols)
  if sel_row < top_row then scroll = sel_row * cols end
  if sel_row >= top_row + rows_vis then scroll = (sel_row - rows_vis + 1) * cols end
  scroll = math.max(0, math.min(scroll, math.max(0, #items - per_page)))

  love.graphics.setScissor(0, vp_y, W, vp_h)
  for i = scroll + 1, math.min(#items, scroll + per_page) do
    local idx = i - scroll - 1
    local gx = idx % cols
    local gy = math.floor(idx / cols)
    local x = 20 + gx * (cell_w + 6)
    local y = vp_y + gy * row_h
    local focused = (i == sel)

    if focused then
      col(acc, 0.30)
      love.graphics.rectangle("fill", x - 2, y - 2, cell_w + 4, cell_h + 4, 3, 3)
    end

    local img = get_thumb(items[i].path)
    if img then
      local iw, ih = img:getDimensions()
      local sc = math.min(cell_w / iw, cell_h / ih)
      love.graphics.setColor(1, 1, 1, focused and 1 or 0.7)
      love.graphics.draw(img, x + (cell_w - iw*sc)/2, y + (cell_h - ih*sc)/2, 0, sc, sc)
    else
      col(acc, 0.15)
      love.graphics.rectangle("fill", x, y, cell_w, cell_h, 2, 2)
    end

    if focused then
      col(acc, 0.95)
      love.graphics.setLineWidth(1.6)
      love.graphics.rectangle("line", x - 1.5, y - 1.5, cell_w + 3, cell_h + 3, 3, 3)
      love.graphics.setLineWidth(1)
    end
  end
  love.graphics.setScissor()

  Frame.draw_top("FGD", "plugins")
  Frame.draw_bottom({
    { key = "dpad", label = "Move" },
    { key = "a",    label = "Fullscreen" },
    { key = "x",    label = "Delete" },
    { key = "y",    label = "Rescan" },
    { key = "b",    label = "Back" },
  })
  Modal.draw()
  D.scanlines(W, H, 0.06)
end

return S
