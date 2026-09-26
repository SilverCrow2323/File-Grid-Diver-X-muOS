-- ui/richtext.lua -- text renderer with inline button tokens.
-- Tokens: [A] [B] [X] [Y] [L1] [R1] [L2] [R2]
--         [START] [SELECT] [UP] [DOWN] [LEFT] [RIGHT] [D-PAD]
-- Multi-line, word wrap, alignment left/center/right.
local A  = require("core.assets")
local BI = require("ui.button_icons")

local M = {}

local TOKEN_MAP = {
  ["[A]"]="a", ["[B]"]="b", ["[X]"]="x", ["[Y]"]="y",
  ["[L1]"]="l1", ["[R1]"]="r1",
  ["[L2]"]="l2", ["[R2]"]="r2",
  ["[START]"]="start", ["[SELECT]"]="select",
  ["[UP]"]="up", ["[DOWN]"]="down",
  ["[LEFT]"]="left", ["[RIGHT]"]="right",
  ["[D-PAD]"]="dpad", ["[DPAD]"]="dpad",
}

local function tokenize(line)
  local toks, buf, i = {}, "", 1
  while i <= #line do
    local ch = line:sub(i, i)
    if ch == "[" then
      local j = line:find("]", i, true)
      if j then
        local tok = line:sub(i, j)
        if TOKEN_MAP[tok] then
          if buf ~= "" then
            toks[#toks+1] = { kind="text", value=buf }; buf = ""
          end
          toks[#toks+1] = { kind="icon", value=TOKEN_MAP[tok] }
          i = j + 1
        else
          buf = buf .. ch; i = i + 1
        end
      else
        buf = buf .. ch; i = i + 1
      end
    else
      buf = buf .. ch; i = i + 1
    end
  end
  if buf ~= "" then toks[#toks+1] = { kind="text", value=buf } end
  return toks
end

-- Draw rich text. Returns total height drawn.
-- opts:
--   font_path, font_size   (optional; defaults to FONT_BODY 12)
--   colour                 (optional; {r,g,b} base color)
--   icon_scale             (optional; default 0.9)
function M.draw(text, x, y, w, align, alpha, opts)
  opts = opts or {}
  alpha = alpha or 1
  local fpath = opts.font_path or A.FONT_BODY
  local fsize = opts.font_size or 12
  local f = A.font(fpath, fsize)
  love.graphics.setFont(f)
  local line_h = f:getHeight() + 2
  local icon_size = opts.icon_scale and (fsize * opts.icon_scale) or (fsize * 0.9)
  local base = opts.colour or {0.85, 0.82, 0.76}

  local function measure(tok)
    if tok.kind == "text" then return f:getWidth(tok.value) end
    return BI.width(icon_size, tok.value) + 2
  end

  local lines = {}
  for raw in (tostring(text) .. "\n"):gmatch("([^\n]*)\n") do
    local toks = tokenize(raw)
    local cur, cur_w = {}, 0
    for _, t in ipairs(toks) do
      -- split text tokens on spaces to enable wrapping
      if t.kind == "text" then
        local segments = {}
        for word in t.value:gmatch("[^%s]+%s*") do segments[#segments+1] = word end
        if #segments == 0 then segments = { t.value } end
        for _, seg in ipairs(segments) do
          local segw = f:getWidth(seg)
          if cur_w + segw > w and #cur > 0 then
            lines[#lines+1] = cur; cur = {}; cur_w = 0
          end
          cur[#cur+1] = { kind="text", value=seg }
          cur_w = cur_w + segw
        end
      else
        local iw = measure(t)
        if cur_w + iw > w and #cur > 0 then
          lines[#lines+1] = cur; cur = {}; cur_w = 0
        end
        cur[#cur+1] = t
        cur_w = cur_w + iw
      end
    end
    lines[#lines+1] = cur
  end

  local cy = y
  for _, line in ipairs(lines) do
    local lw = 0
    for _, t in ipairs(line) do lw = lw + measure(t) end
    local lx
    if align == "center" then lx = x + (w - lw) / 2
    elseif align == "right" then lx = x + w - lw
    else lx = x end

    for _, t in ipairs(line) do
      if t.kind == "text" then
        love.graphics.setColor(base[1], base[2], base[3], alpha)
        love.graphics.print(t.value, lx, cy)
        lx = lx + f:getWidth(t.value)
      else
        BI.draw(lx + icon_size, cy + line_h/2 - 1, icon_size, t.value)
        lx = lx + BI.width(icon_size, t.value) + 2
      end
    end
    cy = cy + line_h
  end
  return cy - y
end

-- Measure only (does not draw). Returns height that draw() would use.
function M.height(text, w, opts)
  opts = opts or {}
  local fpath = opts.font_path or A.FONT_BODY
  local fsize = opts.font_size or 12
  local f = A.font(fpath, fsize)
  local line_h = f:getHeight() + 2
  local icon_size = opts.icon_scale and (fsize * opts.icon_scale) or (fsize * 0.9)
  local function measure(tok)
    if tok.kind == "text" then return f:getWidth(tok.value) end
    return BI.width(icon_size, tok.value) + 2
  end
  local lines = 0
  for raw in (tostring(text) .. "\n"):gmatch("([^\n]*)\n") do
    local toks = tokenize(raw)
    local cur_w = 0
    local cur_has = false
    for _, t in ipairs(toks) do
      if t.kind == "text" then
        for word in t.value:gmatch("[^%s]+%s*") do
          local ww = f:getWidth(word)
          if cur_w + ww > w and cur_has then
            lines = lines + 1; cur_w = 0; cur_has = false
          end
          cur_w = cur_w + ww; cur_has = true
        end
      else
        local iw = measure(t)
        if cur_w + iw > w and cur_has then
          lines = lines + 1; cur_w = 0; cur_has = false
        end
        cur_w = cur_w + iw; cur_has = true
      end
    end
    lines = lines + 1
  end
  return lines * line_h
end

return M
