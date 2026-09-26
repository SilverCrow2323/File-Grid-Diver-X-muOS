-- screens/image_viewer.lua — real image viewer.
local A     = require("core.assets")
local State = require("core.state")
local Input = require("core.input_map")
local Frame = require("ui.frame")
local D     = require("ui.draw")
local FS    = require("services.fs")

local S = {}
local W, H = 640, 480

local img     = nil
local img_w, img_h = 0, 0
local scale   = 1
local rot     = 0        -- radians
local offx    = 0
local offy    = 0
local fit     = true
local path    = nil
local err     = nil
local siblings = {}
local sib_idx  = 0

local function load_file(p)
  err = nil
  img = nil
  path = p
  if not p or p == "" then err = "no file"; return end
  local ok, data = pcall(function()
    local f = io.open(p, "rb")
    if not f then return nil end
    local bytes = f:read("*a")
    f:close()
    return bytes
  end)
  if not ok or not data then err = "cannot read " .. tostring(p); return end
  local ok2, fd = pcall(love.filesystem.newFileData, data, p:match("([^/]+)$") or "img")
  if not ok2 or not fd then err = "cannot wrap FileData"; return end
  local ok3, im = pcall(love.graphics.newImage, fd)
  if not ok3 or not im then err = "cannot decode image"; return end
  img = im
  img_w, img_h = img:getDimensions()
  if fit then
    scale = math.min((W - 40) / img_w, (H - 100) / img_h)
    offx, offy = 0, 0
  end
end

local function collect_siblings()
  siblings = {}
  if not path then return end
  local dir = path:match("^(.*)/[^/]+$") or "."
  local entries = FS.list(dir)
  for _, e in ipairs(entries) do
    if not e.is_dir and FS.classify(e) == "image" then
      siblings[#siblings + 1] = e.path
    end
  end
  table.sort(siblings)
  for i, s in ipairs(siblings) do
    if s == path then sib_idx = i; return end
  end
  sib_idx = 1
end

function S.enter()
  local p = State.selected_path
  if not p then
    local e = State.selected_entry
    if e then p = e.path end
  end
  path = p
  fit = true
  scale = 1
  rot = 0
  offx, offy = 0, 0
  load_file(p)
  collect_siblings()
end
function S.leave() img = nil end
function S.update(dt) end

local function next_image(delta)
  if #siblings == 0 then return end
  sib_idx = sib_idx + delta
  if sib_idx < 1 then sib_idx = #siblings end
  if sib_idx > #siblings then sib_idx = 1 end
  load_file(siblings[sib_idx])
  fit = true
  local s = math.min((W - 40) / img_w, (H - 100) / img_h)
  scale = s
  rot = 0
  offx, offy = 0, 0
end

local function zoom(d)
  fit = false
  scale = math.max(0.1, math.min(8, scale * (d > 0 and 1.15 or 0.87)))
end

function S.pad(b)
  if b == Input.B or b == Input.SELECT then State.back()
  elseif b == Input.X then
    fit = not fit
    if fit then
      scale = math.min((W - 40) / img_w, (H - 100) / img_h)
      offx, offy = 0, 0
    else
      scale = 1
    end
  elseif b == Input.Y then zoom( 1)
  elseif b == Input.L1 then rot = rot - math.pi/2
  elseif b == Input.R1 then rot = rot + math.pi/2
  elseif b == Input.L2 then next_image(-1)
  elseif b == Input.R2 then next_image( 1)
  end
end
function S.hat(dir)
  if not img then return end
  local step = 24
  if     dir == "up"    then offy = offy + step
  elseif dir == "down"  then offy = offy - step
  elseif dir == "left"  then offx = offx + step
  elseif dir == "right" then offx = offx - step end
end
function S.key(k)
  if k == "escape" or k == "backspace" then State.back()
  elseif k == "=" or k == "kp+" then zoom( 1)
  elseif k == "kp-" or k == "-" then zoom(-1)
  elseif k == "left"  then offx = offx + 24
  elseif k == "right" then offx = offx - 24
  elseif k == "up"    then offy = offy + 24
  elseif k == "down"  then offy = offy - 24
  elseif k == "r"     then rot = rot + math.pi/2
  elseif k == "tab"   then next_image(1)
  end
end

function S.draw()
  local th = State.theme
  D.bg()

  if not img then
    love.graphics.setColor(th.red_hi)
    love.graphics.setFont(A.font(A.FONT_BODY_BOLD, 14))
    love.graphics.printf("cannot open image", 0, H/2 - 20, W, "center")
    love.graphics.setColor(th.text_dim)
    love.graphics.setFont(A.font(A.FONT_BODY, 13))
    love.graphics.printf(tostring(err or path or "?"), 0, H/2, W, "center")
  else
    local cx = W / 2 + offx
    local cy = H / 2 + offy
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(img, cx, cy, rot, scale, scale,
      img_w / 2, img_h / 2)

    -- Info panel
    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.rectangle("fill", 0, Frame.TOP_H, W, 16)
    love.graphics.setColor(th.amber_hi)
    love.graphics.setFont(A.font(A.FONT_MONO, 12))
    local name = path and path:match("([^/]+)$") or "?"
    love.graphics.print(name, 8, Frame.TOP_H + 3)

    love.graphics.setColor(th.text_dim)
    love.graphics.printf(
      string.format("%dx%d  ·  %.0f%%  ·  %s  ·  %d/%d",
        img_w, img_h, scale * 100,
        fit and "FIT" or "FREE",
        math.max(1, sib_idx), math.max(1, #siblings)),
      0, Frame.TOP_H + 3, W - 8, "right")
  end

  Frame.draw_top("FGD", "image")
  Frame.draw_bottom({
    { key = "D-PAD",  label = "Pan" },
    { key = "X",      label = "Fit" },
    { key = "Y",      label = "Zoom+" },
    { key = "L1/R1",  label = "Rotate" },
    { key = "L2/R2",  label = "Prev/Next" },
    { key = "B",      label = "Back" },
  })
  D.scanlines(W, H, 0.06)
  D.vignette(W, H, 0.45)
end

return S
