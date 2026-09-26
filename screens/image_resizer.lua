-- screens/image_resizer.lua -- Image Resizer plugin.
local A     = require("core.assets")
local State = require("core.state")
local Input = require("core.input_map")
local Frame = require("ui.frame")
local D     = require("ui.draw")
local Notify= require("ui.notify")
local Modal = require("ui.modal")
local sh    = require("core.sh")
local PathSel = require("ui.path_selector")

local S = {}
local W, H = 640, 480
local acc = {0.85, 0.55, 0.35}

local items = {}    -- { path, name }
local sel = 1
local scroll = 0
local marks = {}
local t_enter = 0

local PRESETS = {
  { name = "640x480",    w = 640,  h = 480  },
  { name = "480x640",    w = 480,  h = 640  },
  { name = "720x720",    w = 720,  h = 720  },
  { name = "1024x768",   w = 1024, h = 768  },
  { name = "1280x720",   w = 1280, h = 720  },
  { name = "256x256",    w = 256,  h = 256  },
  { name = "128x128",    w = 128,  h = 128  },
  { name = "64x64",      w = 64,   h = 64   },
}
local preset_i = 1

local custom_paths = {}

local SCAN_ROOTS = {
  "/mnt/mmc/Pictures", "/mnt/mmc/pictures", "/mnt/mmc/Images",
  "/mnt/sdcard/Pictures", "/mnt/sdcard/Images",
  os.getenv("HOME") .. "/Pictures",
}

local function col(c, a) love.graphics.setColor(c[1], c[2], c[3], a or 1) end

local function scan()
  items = {}
  local seen = {}
  local all_roots = {}
  for _, r in ipairs(SCAN_ROOTS) do all_roots[#all_roots+1] = r end
  for _, p in ipairs(custom_paths) do all_roots[#all_roots+1] = p end
  for _, dir in ipairs(all_roots) do
    if sh.is_dir(dir) then
      local h = io.popen("find " .. sh.shq(dir) ..
        " -maxdepth 3 -type f \\( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' \\) 2>/dev/null | sort | head -200")
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

local function count_marks()
  local n = 0
  for _ in pairs(marks) do n = n + 1 end
  return n
end

local function has_ffmpeg()
  return sh.exec("command -v ffmpeg >/dev/null 2>&1") == 0
end

local function run_resize()
  if not has_ffmpeg() then
    Notify.show("error", "ffmpeg not installed")
    return
  end
  local n = count_marks()
  if n == 0 then
    Notify.show("warning", "mark at least one image with SELECT")
    return
  end
  local p = PRESETS[preset_i]
  local out_dir = "data/resized"
  sh.exec("mkdir -p " .. sh.shq(out_dir))
  local ok_n = 0
  for path in pairs(marks) do
    local name = path:match("([^/]+)$") or "out.png"
    local base = name:gsub("%.[^.]+$", "")
    local ext = name:match("%.([^.]+)$") or "png"
    local target = out_dir .. "/" .. base .. "_" .. p.w .. "x" .. p.h .. "." .. ext
    local cmd = "ffmpeg -y -loglevel error -i " .. sh.shq(path) ..
      " -vf 'scale=" .. p.w .. ":" .. p.h .. ":force_original_aspect_ratio=decrease,pad=" ..
      p.w .. ":" .. p.h .. ":(ow-iw)/2:(oh-ih)/2' " ..
      sh.shq(target) .. " 2>&1"
    if sh.exec(cmd) == 0 then ok_n = ok_n + 1 end
  end
  Notify.show("success", ok_n .. " images resized to " .. p.name .. " (data/resized)")
end

function S.enter()
  t_enter = 0
  sel = 1
  scroll = 0
  marks = {}
  preset_i = 1
  scan()
end
function S.leave() end
function S.update(dt) t_enter = t_enter + dt end

function S.pad(b)
  if Modal.is_open() then
    if b == Input.A then Modal.accept()
    elseif b == Input.B then Modal.cancel() end
    return
  end
  if #items == 0 then
    PathSel.pad(b, {
      paths = SCAN_ROOTS,
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
  elseif b == Input.LEFT then preset_i = math.max(1, preset_i - 1)
  elseif b == Input.RIGHT then preset_i = math.min(#PRESETS, preset_i + 1)
  elseif b == Input.SELECT then
    local it = items[sel]
    if it then marks[it.path] = (not marks[it.path]) or nil end
  elseif b == Input.A then
    if count_marks() == 0 then
      local it = items[sel]
      if it then marks[it.path] = true end
    end
    run_resize()
  elseif b == Input.X then
    marks = {}
    Notify.show("info", "marks cleared")
  elseif b == Input.B or b == Input.SELECT then State.back() end
end

function S.hat(dir)
  if     dir == "up"   then sel = math.max(1, sel - 1)
  elseif dir == "down" then sel = math.min(#items, sel + 1)
  elseif dir == "left" then preset_i = math.max(1, preset_i - 1)
  elseif dir == "right" then preset_i = math.min(#PRESETS, preset_i + 1) end
end

function S.key(k)
  if     k == "escape" or k == "backspace" then S.pad(Input.B)
  elseif k == "up"    then S.pad(Input.UP)
  elseif k == "down"  then S.pad(Input.DOWN)
  elseif k == "left"  then S.pad(Input.LEFT)
  elseif k == "right" then S.pad(Input.RIGHT)
  elseif k == "x"     then S.pad(Input.X)
  elseif k == "space" then S.pad(Input.SELECT)
  elseif k == "return" then S.pad(Input.A) end
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
  love.graphics.printf("IMAGE RESIZER", 0, Frame.TOP_H + 8, W, "center")

  -- Preset selector
  local py = Frame.TOP_H + 36
  local p = PRESETS[preset_i]
  love.graphics.setFont(A.font(A.FONT_MONO, 12))
  col(acc, 1)
  love.graphics.printf("< " .. p.name .. " >", 0, py, W, "center")

  love.graphics.setFont(A.font(A.FONT_MONO, 10))
  col(acc, 0.75)
  love.graphics.printf(#items .. " images  ·  " .. count_marks() .. " marked",
    0, py + 20, W, "center")

  local vp_y = py + 44
  local vp_h = H - Frame.BOTTOM_H - vp_y - 4
  local row_h = 26

  if #items == 0 then
    PathSel.draw({
      title = "IMAGE RESIZER",
      message = "No images found.\n\n" ..
                "This plugin scans common picture folders on both SD cards " ..
                "and the home directory.\n\n" ..
                "Press X to rescan.\nPress Y to add a custom folder.\nPress B to go back.",
      paths = SCAN_ROOTS,
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

  local total_h = #items * row_h
  local max_scroll = math.max(0, total_h - vp_h)
  local st_top = (sel - 1) * row_h
  if st_top < scroll then scroll = st_top end
  if st_top + row_h > scroll + vp_h then scroll = st_top + row_h - vp_h end
  scroll = math.max(0, math.min(max_scroll, scroll))

  love.graphics.setScissor(0, vp_y, W, vp_h)
  for i, it in ipairs(items) do
    local ry = vp_y + (i - 1) * row_h - scroll
    if ry + row_h > vp_y and ry < vp_y + vp_h then
      local focused = (i == sel)
      local marked = marks[it.path]
      if focused then
        col(acc, 0.20)
        love.graphics.rectangle("fill", 20, ry, W - 40, row_h - 2, 3, 3)
      elseif marked then
        col({0.35, 0.90, 0.50}, 0.10)
        love.graphics.rectangle("fill", 20, ry, W - 40, row_h - 2, 3, 3)
      end

      if marked then
        col({0.35, 0.90, 0.50}, 1)
        love.graphics.rectangle("fill", 24, ry + 8, 10, 10, 2, 2)
        col({0.02, 0.05, 0.02}, 1)
        love.graphics.setLineWidth(1.8)
        love.graphics.line(26, ry + 13, 28, ry + 15, 32, ry + 10)
        love.graphics.setLineWidth(1)
      end

      love.graphics.setFont(A.font(A.FONT_MONO, 11))
      col(focused and {1,1,1} or th.text, 1)
      local name = it.name
      if #name > 50 then name = name:sub(1, 49) .. "." end
      love.graphics.print(name, 42, ry + 6)
    end
  end
  love.graphics.setScissor()

  Frame.draw_top("FGD", "plugins")
  Frame.draw_bottom({
    { key = "dpad",   label = "Move/Preset" },
    { key = "select", label = "Mark" },
    { key = "a",      label = "Resize" },
    { key = "x",      label = "Clear" },
    { key = "b",      label = "Back" },
  })
  Modal.draw()
  D.scanlines(W, H, 0.06)
end

return S
