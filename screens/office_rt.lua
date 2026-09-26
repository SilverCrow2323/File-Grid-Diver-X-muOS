-- screens/office_rt.lua -- Office:Rt viewer (docx / xlsx / pptx).
local A     = require("core.assets")
local State = require("core.state")
local Input = require("core.input_map")
local Frame = require("ui.frame")
local D     = require("ui.draw")
local Notify= require("ui.notify")
local OE    = require("services.office_engine")

local S = {}
local W, H = 640, 480

local acc = {0.94, 0.66, 0.35}   -- amber

local doc      = nil
local path     = nil
local scroll   = 0
local t_enter  = 0

local function col(c, a) love.graphics.setColor(c[1], c[2], c[3], a or 1) end
local function basename(p) return (p or ""):match("([^/]+)$") or p or "?" end

function S.enter()
  t_enter = 0
  scroll = 0
  path = State.office_path
  if not path then
    Notify.show("warning", "no file")
    State.back(); return
  end
  local d, err = OE.open(path)
  if not d then
    Notify.show("error", err or "cannot open")
    State.back(); return
  end
  doc = d
end

function S.leave() end
function S.update(dt) t_enter = t_enter + dt end

function S.pad(b)
  if     b == Input.B or b == Input.SELECT then State.back()
  elseif b == Input.UP   then scroll = math.max(0, scroll - 30)
  elseif b == Input.DOWN then scroll = scroll + 30
  elseif b == Input.A    then scroll = scroll + 30 end
end

function S.hat(dir)
  if     dir == "up"   then scroll = math.max(0, scroll - 30)
  elseif dir == "down" then scroll = scroll + 30 end
end

function S.key(k)
  if     k == "escape" or k == "backspace" then State.back()
  elseif k == "up"   then scroll = math.max(0, scroll - 30)
  elseif k == "down" then scroll = scroll + 30 end
end

local function draw_header()
  local x, y = 20, Frame.TOP_H + 4
  local w = W - 40
  local h = 34
  col({0.035, 0.025, 0.015}, 0.95)
  love.graphics.rectangle("fill", x, y, w, h, 4, 4)
  col(acc, 0.9)
  love.graphics.setLineWidth(1.4)
  love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, 4, 4)
  love.graphics.setLineWidth(1)

  love.graphics.setFont(A.font(A.FONT_TITLE, 13))
  col(acc, 1)
  love.graphics.print("OFFICE:RT", x + 12, y + 5)

  love.graphics.setFont(A.font(A.FONT_BODY_BOLD, 12))
  col({1,1,1}, 1)
  local t = basename(path)
  if #t > 42 then t = t:sub(1, 41) .. "…" end
  love.graphics.print(t, x + 130, y + 5)

  love.graphics.setFont(A.font(A.FONT_MONO, 10))
  col(acc, 0.85)
  love.graphics.printf(doc and doc.kind:upper() or "?", x, y + 6, w - 12, "right")
end

local function draw_docx()
  local th = State.theme
  local f = A.font(A.FONT_BODY, 12)
  love.graphics.setFont(f)
  local x, w = 30, W - 60
  local y = Frame.TOP_H + 48 - scroll
  local lh = 18

  love.graphics.setScissor(0, Frame.TOP_H + 42, W, H - Frame.TOP_H - Frame.BOTTOM_H - 46)
  for para in (doc.text or ""):gmatch("[^\n]*\n?") do
    para = para:gsub("\n$", "")
    if para ~= "" then
      col(th.text, 1)
      love.graphics.printf(para, x, y, w, "left")
      y = y + lh * (1 + math.floor(f:getWidth(para) / w))
    else
      y = y + lh
    end
    if y > H + 200 then break end
  end
  love.graphics.setScissor()
end

local function draw_xlsx()
  local th = State.theme
  local rows = doc.rows or {}
  local f = A.font(A.FONT_MONO, 11)
  love.graphics.setFont(f)
  local x = 20
  local y = Frame.TOP_H + 48 - scroll
  local lh = 16

  love.graphics.setScissor(0, Frame.TOP_H + 42, W, H - Frame.TOP_H - Frame.BOTTOM_H - 46)
  for ri, row in ipairs(rows) do
    local row_h = lh
    local cx = x
    for ci, cell in ipairs(row) do
      local cw = 100
      if ci == 1 then cw = 50 end
      col(acc, 0.15)
      love.graphics.rectangle("fill", cx, y, cw - 2, row_h)
      col(ri == 1 and acc or th.text, 1)
      local txt = cell
      if #txt > 14 then txt = txt:sub(1, 13) .. "…" end
      love.graphics.print(txt, cx + 3, y + 2)
      cx = cx + cw
      if cx > W - 20 then break end
    end
    y = y + row_h
    if y > H + 200 then break end
  end
  love.graphics.setScissor()
end

local function draw_pptx()
  local th = State.theme
  local slides = doc.slides or {}
  local f = A.font(A.FONT_BODY, 12)
  love.graphics.setFont(f)
  local x, w = 30, W - 60
  local y = Frame.TOP_H + 48 - scroll
  love.graphics.setScissor(0, Frame.TOP_H + 42, W, H - Frame.TOP_H - Frame.BOTTOM_H - 46)
  for i, s in ipairs(slides) do
    col(acc, 1)
    love.graphics.setFont(A.font(A.FONT_TITLE, 14))
    love.graphics.print("SLIDE " .. i, x, y)
    y = y + 20
    love.graphics.setFont(f)
    for line in (s or ""):gmatch("[^\n]*\n?") do
      line = line:gsub("\n$", "")
      if line ~= "" then
        col(th.text, 1)
        love.graphics.printf(line, x, y, w, "left")
        y = y + 18
      end
    end
    y = y + 14
    if y > H + 200 then break end
  end
  love.graphics.setScissor()
end

function S.draw()
  D.bg()
  col(acc, 0.06)
  for gy = Frame.TOP_H, H - Frame.BOTTOM_H, 18 do
    for gx = 0, W, 18 do love.graphics.rectangle("fill", gx, gy, 1, 1) end
  end

  draw_header()
  if doc then
    if doc.kind == "docx" then draw_docx()
    elseif doc.kind == "xlsx" then draw_xlsx()
    elseif doc.kind == "pptx" then draw_pptx() end
  end

  Frame.draw_top("FGD", "grid")
  Frame.draw_bottom({
    { key = "up",  label = "Scroll" },
    { key = "down",label = "Scroll" },
    { key = "b",   label = "Exit" },
  })
  D.scanlines(W, H, 0.06)
end

return S
