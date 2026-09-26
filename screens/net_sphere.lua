-- screens/net_sphere.lua -- Net-Sphere Reader² HTML reader.
-- Two modes: RENDER (parsed blocks) and SOURCE (raw text).
-- X toggles mode. L1/R1 for prev/next file in same folder.
local A     = require("core.assets")
local State = require("core.state")
local Input = require("core.input_map")
local Frame = require("ui.frame")
local D     = require("ui.draw")
local Notify= require("ui.notify")
local HParse= require("services.html_parse")
local ExtImg= require("core.external_image")
local FS    = require("services.fs")

local S = {}
local W, H = 640, 480

local acc = {0.30, 0.85, 0.95}   -- cyan

local path       = nil
local raw        = nil
local blocks     = nil
local mode       = "render"       -- "render" | "source"
local scroll     = 0
local t_enter    = 0
local siblings   = {}
local sib_idx    = 1
local html_index = nil    -- { { text=, y=, level= } }
local index_open = false
local index_sel  = 1
local line_heights = {}   -- per sapere a che Y è ogni heading

local function col(c, a) love.graphics.setColor(c[1], c[2], c[3], a or 1) end
local function basename(p) return (p or ""):match("([^/]+)$") or p or "?" end

local function build_html_index(blocks_list)
  html_index = {}
  local y_est = 0
  for _, blk in ipairs(blocks_list or {}) do
    if blk.kind == "h1" or blk.kind == "h2" or blk.kind == "h3"
       or blk.kind == "h4" or blk.kind == "h5" or blk.kind == "h6" then
      local text = ""
      for _, r in ipairs(blk.runs) do text = text .. (r.text or "") end
      if text ~= "" then
        html_index[#html_index + 1] = {
          text = text, y_est = y_est, level = tonumber(blk.kind:sub(2)) or 1,
        }
      end
    end
    -- Estimazione Y: ogni blocco p/h ~ 20px, pre ~14px, hr ~14px
    if blk.kind == "p" then y_est = y_est + 40
    elseif blk.kind == "hr" then y_est = y_est + 14
    elseif blk.kind == "img" then y_est = y_est + 14
    elseif blk.kind == "pre" then y_est = y_est + 14 * 3
    else y_est = y_est + 30 end
  end
end

local function load_file(p)
  path = p
  scroll = 0
  local f = io.open(p, "r")
  if not f then
    raw = "cannot read " .. p
    blocks = { { kind = "p", runs = { { text = raw } } } }
    html_index = {}
    return
  end
  raw = f:read("*a"); f:close()
  blocks = HParse.parse(raw)
  build_html_index(blocks)
end

local function collect_siblings()
  siblings = {}
  if not path then return end
  local dir = path:match("^(.*)/[^/]+$") or "."
  local entries = FS.list(dir)
  for _, e in ipairs(entries or {}) do
    if not e.is_dir then
      local ext = FS.ext_of(e.name)
      if ext == "html" or ext == "htm" then
        siblings[#siblings+1] = e.path
      end
    end
  end
  table.sort(siblings)
  for i, s in ipairs(siblings) do if s == path then sib_idx = i; return end end
  sib_idx = 1
end

local function next_file(delta)
  if #siblings < 2 then return end
  sib_idx = sib_idx + delta
  if sib_idx < 1 then sib_idx = #siblings end
  if sib_idx > #siblings then sib_idx = 1 end
  load_file(siblings[sib_idx])
end

-- ============================================================
--  Lifecycle
-- ============================================================
function S.enter()
  t_enter = 0
  scroll = 0
  mode = "render"
  path = State.net_sphere_path
  if not path then
    Notify.show("warning", "no HTML file")
    State.back(); return
  end
  load_file(path)
  collect_siblings()
end

function S.leave() end
function S.update(dt) t_enter = t_enter + dt end

-- ============================================================
--  Input
-- ============================================================
function S.pad(b)
  -- Index open
  if index_open then
    if     b == Input.UP   then index_sel = math.max(1, index_sel - 1)
    elseif b == Input.DOWN then index_sel = math.min(#html_index, index_sel + 1)
    elseif b == Input.A then
      local item = html_index[index_sel]
      if item then scroll = item.y_est end
      index_open = false
    elseif b == Input.B or b == Input.SELECT then index_open = false end
    return
  end

  if     b == Input.B or b == Input.SELECT then State.back()
  elseif b == Input.X then mode = (mode == "render") and "source" or "render"; scroll = 0
  elseif b == Input.Y then
    if html_index and #html_index > 0 then
      index_open = true
      index_sel = 1
    end
  elseif b == Input.L1 then next_file(-1)
  elseif b == Input.R1 then next_file(1)
  elseif b == Input.A then scroll = scroll + 30 end
end

function S.hat(dir)
  if     dir == "up"   then scroll = scroll - 30
  elseif dir == "down" then scroll = scroll + 30 end
end

function S.key(k)
  if index_open then
    if     k == "up"   then index_sel = math.max(1, index_sel - 1)
    elseif k == "down" then index_sel = math.min(#html_index, index_sel + 1)
    elseif k == "return" or k == "space" then S.pad(Input.A)
    elseif k == "escape" then index_open = false end
    return
  end
  if     k == "escape" or k == "backspace" then State.back()
  elseif k == "up"   then scroll = scroll - 30
  elseif k == "down" then scroll = scroll + 30
  elseif k == "tab"  then mode = (mode == "render") and "source" or "render"; scroll = 0
  elseif k == "y" then S.pad(Input.Y)
  elseif k == "return" or k == "space" then scroll = scroll + 30 end
end

-- ============================================================
--  Drawing
-- ============================================================
local function draw_header()
  local x, y = 20, Frame.TOP_H + 4
  local w = W - 40
  local h = 34
  col({0.020, 0.035, 0.045}, 0.95)
  love.graphics.rectangle("fill", x, y, w, h, 4, 4)
  col(acc, 0.9)
  love.graphics.setLineWidth(1.4)
  love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, 4, 4)
  love.graphics.setLineWidth(1)

  love.graphics.setFont(A.font(A.FONT_TITLE, 12))
  col(acc, 1)
  -- "Net-Sphere Reader²" with superscript 2
  love.graphics.print("NET-SPHERE READER", x + 12, y + 5)
  -- superscript 2
  local f = love.graphics.getFont()
  local wmain = f:getWidth("NET-SPHERE READER")
  love.graphics.setFont(A.font(A.FONT_TITLE, 8))
  love.graphics.print("2", x + 12 + wmain + 2, y + 2)

  love.graphics.setFont(A.font(A.FONT_BODY_BOLD, 11))
  col({1,1,1}, 1)
  love.graphics.print(basename(path), x + 220, y + 5)

  love.graphics.setFont(A.font(A.FONT_MONO, 10))
  col(acc, 0.85)
  love.graphics.printf("[" .. mode .. "]", x, y + 6, w - 12, "right")
end

local function draw_render()
  local x = 30
  local w = W - 60
  local y = Frame.TOP_H + 48 - scroll
  local th = State.theme

  love.graphics.setScissor(0, Frame.TOP_H + 42, W, H - Frame.TOP_H - Frame.BOTTOM_H - 46)

  local function font_for(kind)
    if kind == "h1" then return A.font(A.FONT_TITLE, 22), 30
    elseif kind == "h2" then return A.font(A.FONT_TITLE, 18), 26
    elseif kind == "h3" then return A.font(A.FONT_TITLE, 15), 22
    elseif kind == "h4" then return A.font(A.FONT_BODY_BOLD, 13), 20
    elseif kind == "h5" then return A.font(A.FONT_BODY_BOLD, 12), 18
    elseif kind == "h6" then return A.font(A.FONT_BODY_BOLD, 11), 16
    elseif kind == "pre" then return A.font(A.FONT_MONO, 11), 14
    else return A.font(A.FONT_BODY, 12), 18 end
  end

  for _, blk in ipairs(blocks or {}) do
    if blk.kind == "hr" then
      col(acc, 0.4)
      love.graphics.rectangle("fill", x, y + 6, w, 1)
      y = y + 14
    elseif blk.kind == "img" then
      y = y + 6
      col(th.text_dim, 0.8)
      love.graphics.setFont(A.font(A.FONT_MONO, 10))
      love.graphics.print("[img] " .. (blk.alt or blk.src or ""), x, y)
      y = y + 14
    else
      local f, lh = font_for(blk.kind)
      love.graphics.setFont(f)
      local line = {}
      for _, r in ipairs(blk.runs) do line[#line+1] = r.text end
      local txt = table.concat(line)
      if txt ~= "" then
        if blk.kind == "h1" or blk.kind == "h2" or blk.kind == "h3" then
          col(acc, 1)
        else
          col(th.text, 1)
        end
        love.graphics.printf(txt, x, y, w, "left")
        y = y + lh * (1 + math.floor(f:getWidth(txt) / w))
      end
    end
    if y > H + 200 then break end
  end
  love.graphics.setScissor()
end

local function draw_source()
  local th = State.theme
  local f = A.font(A.FONT_MONO, 10)
  love.graphics.setFont(f)
  local lh = 12
  local y = Frame.TOP_H + 48 - scroll
  local line_i = 0
  love.graphics.setScissor(0, Frame.TOP_H + 42, W, H - Frame.TOP_H - Frame.BOTTOM_H - 46)
  for line in (raw or ""):gmatch("[^\n]*\n?") do
    if line == "" then break end
    line_i = line_i + 1
    col(th.text_dim, 0.55)
    love.graphics.print(string.format("%4d", line_i), 12, y)
    col(th.text, 1)
    love.graphics.print(line:gsub("\n$", ""), 52, y)
    y = y + lh
    if y > H + 200 then break end
  end
  love.graphics.setScissor()
end

local function draw_index_overlay()
  if not index_open or not html_index or #html_index == 0 then return end
  love.graphics.setColor(0, 0, 0, 0.80)
  love.graphics.rectangle("fill", 0, 0, W, H)
  local x = 40
  local y = 40
  local w = W - 80
  local h = H - 80
  col({0.020, 0.035, 0.045}, 0.98)
  love.graphics.rectangle("fill", x, y, w, h, 5, 5)
  col(acc, 0.9)
  love.graphics.setLineWidth(1.6)
  love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, 5, 5)
  love.graphics.setLineWidth(1)
  D.corner_ticks(x + 8, y + 8, w - 16, h - 16, 12, acc, 0.9)

  love.graphics.setFont(A.font(A.FONT_TITLE, 16))
  col(acc, 1)
  love.graphics.print("DOCUMENT OUTLINE", x + 20, y + 14)
  col(acc, 0.3)
  love.graphics.rectangle("fill", x + 20, y + 36, w - 40, 1)

  local row_h = 22
  local vis = math.floor((h - 60) / row_h)
  local first = math.max(1, index_sel - vis + 3)

  for i = first, math.min(#html_index, first + vis - 1) do
    local item = html_index[i]
    local ry = y + 46 + (i - first) * row_h
    local focused = (i == index_sel)
    local indent = 14 + (item.level - 1) * 10

    if focused then
      col(acc, 0.20)
      love.graphics.rectangle("fill", x + 10, ry - 2, w - 20, row_h - 2, 3, 3)
    end

    love.graphics.setFont(A.font(A.FONT_MONO, 9))
    col(acc, 0.7)
    love.graphics.print("H" .. item.level, x + indent, ry + 4)

    love.graphics.setFont(A.font(A.FONT_BODY, 12))
    col(focused and {1,1,1} or State.theme.text, 1)
    local title = item.text
    if #title > 44 then title = title:sub(1, 43) .. "." end
    love.graphics.print(title, x + indent + 22, ry + 2)
  end
end

function S.draw()
  D.bg()
  col(acc, 0.06)
  for gy = Frame.TOP_H, H - Frame.BOTTOM_H, 18 do
    for gx = 0, W, 18 do love.graphics.rectangle("fill", gx, gy, 1, 1) end
  end

  draw_header()
  if mode == "render" then draw_render() else draw_source() end

  Frame.draw_top("FGD", "grid")
  Frame.draw_bottom({
    { key = "up",  label = "Scroll" },
    { key = "y",   label = "Outline" },
    { key = "x",   label = "Mode" },
    { key = "b",   label = "Exit" },
  })
  draw_index_overlay()
  D.scanlines(W, H, 0.06)
end

return S
