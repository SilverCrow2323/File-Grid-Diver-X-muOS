-- screens/archive_rt.lua -- Archive Rt viewer.
-- Read-only tree of archive contents. Checkbox selection.
-- Actions: Extract all / Extract selected / Extract here / Extract to...
local A     = require("core.assets")
local State = require("core.state")
local Input = require("core.input_map")
local Frame = require("ui.frame")
local D     = require("ui.draw")
local Notify= require("ui.notify")
local Modal = require("ui.modal")
local KB    = require("ui.keyboard")
local ART   = require("services.archive_rt")
local Dialog= require("ui.dialogs")

local S = {}
local W, H = 640, 480

local acc = {0.30, 0.85, 0.95}   -- cyan/teal for Archive Rt

local path       = nil
local kind       = nil
local tree_root  = nil
local flat       = {}
local sel        = 1
local scroll     = 0
local max_scroll = 0
local t_enter    = 0
local marks      = {}     -- [path] = true
local act_sel    = 1
local focus      = "tree" -- "tree" | "actions"
local error_msg  = nil
local total_size = 0
local file_count = 0

local ACTIONS = {
  { id = "all",      label = "Extract all",         colour = {0.55, 0.85, 0.45} },
  { id = "selected", label = "Extract selected",    colour = {0.48, 0.80, 0.90} },
  { id = "here",     label = "Extract here",        colour = {0.94, 0.66, 0.35} },
  { id = "to",       label = "Extract to...",       colour = {0.70, 0.55, 0.92} },
}

local function col(c, a) love.graphics.setColor(c[1], c[2], c[3], a or 1) end
local function human(n)
  if not n or n <= 0 then return "0 B" end
  local u = {"B","KB","MB","GB","TB"}; local i = 1
  while n >= 1024 and i < #u do n = n / 1024; i = i + 1 end
  if i == 1 then return string.format("%d %s", n, u[i]) end
  return string.format("%.1f %s", n, u[i])
end

local function basename(p) return (p or ""):match("([^/]+)$") or p or "" end

-- Flatten the tree respecting expansion state
local function flatten(node, out)
  out = out or {}
  for _, c in ipairs(node.children or {}) do
    out[#out+1] = c
    if c.is_dir and c.expanded then
      flatten(c, out)
    end
  end
  return out
end

local function rebuild_flat()
  flat = flatten(tree_root)
end

local function count_selected()
  local n = 0
  for _ in pairs(marks) do n = n + 1 end
  return n
end

-- ============================================================
--  Lifecycle
-- ============================================================
function S.enter()
  t_enter = 0
  path = State.archive_path
  if not path or path == "" then
    Notify.show("warning", "no archive")
    State.back()
    return
  end
  kind = ART.detect(path)
  if not kind then
    Notify.show("warning", "unsupported archive")
    State.back()
    return
  end
  marks = {}
  act_sel = 1
  focus = "tree"
  error_msg = nil
  total_size = 0
  file_count = 0

  local entries, err = ART.list(path)
  if not entries then
    error_msg = err or "cannot list"
    tree_root = { children = {}, depth = 0 }
    flat = {}
    return
  end
  for _, e in ipairs(entries) do
    if not e.is_dir then
      file_count = file_count + 1
      total_size = total_size + (e.size or 0)
    end
  end
  tree_root = ART.build_tree(entries)
  -- Expand the root's direct children that are dirs? No, start collapsed.
  tree_root.expanded = true
  rebuild_flat()
  sel = 1
  scroll = 0
end

function S.leave() end

function S.update(dt)
  t_enter = t_enter + dt
end

-- ============================================================
--  Navigation
-- ============================================================
local function move(d)
  if #flat == 0 then return end
  sel = sel + d
  if sel < 1 then sel = 1 end
  if sel > #flat then sel = #flat end
end

local function tree_left()
  if #flat == 0 then return end
  local n = flat[sel]
  if not n then return end
  if n.is_dir and n.expanded then
    n.expanded = false
    rebuild_flat()
    if sel > #flat then sel = math.max(1, #flat) end
  else
    -- jump to parent
    for i = sel - 1, 1, -1 do
      if flat[i].depth < n.depth then sel = i; break end
    end
  end
end

local function tree_right()
  if #flat == 0 then return end
  local n = flat[sel]
  if not n then return end
  if n.is_dir and not n.expanded then
    n.expanded = true
    rebuild_flat()
  elseif n.is_dir and n.expanded and #flat > sel then
    sel = sel + 1
  end
end

local function toggle_mark()
  if #flat == 0 then return end
  local n = flat[sel]
  if not n then return end
  marks[n.path] = (not marks[n.path]) or nil
end

-- ============================================================
--  Actions
-- ============================================================
local function collect_selected_paths()
  local out = {}
  -- If a dir is selected, include it (extract recursively via tool)
  for _, n in ipairs(flat) do
    if marks[n.path] then out[#out+1] = n.path end
  end
  return out
end

local function run_extract(opts)
  local ok, err = ART.extract(path, opts)
  if ok then
    Notify.show("success", "extracted to " .. (opts.to or "current folder"))
  else
    Notify.show("error", err or "extract failed")
  end
end

local function confirm_and_extract_all(target, here)
  local dst_txt = here and "the current folder" or target
  Dialog.confirm("Extract all",
    "Extract every file from\n" .. basename(path) .. "\nto " .. dst_txt .. "?",
    { accept_label = "EXTRACT", cancel_label = "CANCEL",
      accept_color = {0.55, 0.85, 0.45},
      on_accept = function()
        run_extract({ to = target })
      end })
end

local function confirm_and_extract_selected()
  local sel_paths = collect_selected_paths()
  if #sel_paths == 0 then
    Dialog.info("Nothing selected",
      "Mark one or more items with A,\nthen press X to extract them.",
      { color = {0.95, 0.72, 0.25} })
    return
  end
  local target = path:match("^(.*)/[^/]+$") or "."
  Dialog.confirm("Extract selected",
    "Extract " .. #sel_paths .. " item(s)\nto the current folder?",
    { accept_label = "EXTRACT", cancel_label = "CANCEL",
      accept_color = {0.48, 0.80, 0.90},
      on_accept = function()
        run_extract({ to = target, selected = sel_paths })
      end })
end

local function ask_extract_to()
  local base = path:match("^(.*)/[^/]+$") or "."
  KB.open({
    title = "Extract to folder",
    initial = base .. "/" .. (basename(path):gsub("%.[^%.]+$", "")),
    on_accept = function(folder)
      if not folder or folder == "" then return end
      run_extract({ to = folder })
    end,
    on_cancel = function() end,
  })
end

local function run_action(id)
  if id == "all" then
    confirm_and_extract_all(path:match("^(.*)/[^/]+$") or ".", true)
  elseif id == "selected" then
    confirm_and_extract_selected()
  elseif id == "here" then
    confirm_and_extract_all(path:match("^(.*)/[^/]+$") or ".", true)
  elseif id == "to" then
    ask_extract_to()
  end
end

-- ============================================================
--  Input
-- ============================================================
function S.pad(b)
  if KB.is_open() then KB.pad(b); return end
  if Modal.is_open() then
    if b == Input.A then Modal.accept()
    elseif b == Input.B then Modal.cancel() end
    return
  end

  if b == Input.L1 or b == Input.R1 or b == Input.START then
    focus = (focus == "tree") and "actions" or "tree"
    return
  end

  if focus == "tree" then
    if     b == Input.UP    then move(-1)
    elseif b == Input.DOWN  then move( 1)
    elseif b == Input.LEFT  then tree_left()
    elseif b == Input.RIGHT then tree_right()
    elseif b == Input.A     then toggle_mark()
    elseif b == Input.Y     then tree_right()
    elseif b == Input.X     then confirm_and_extract_selected()
    elseif b == Input.B or b == Input.SELECT then State.back() end
  else
    if     b == Input.UP    then act_sel = math.max(1, act_sel - 1)
    elseif b == Input.DOWN  then act_sel = math.min(#ACTIONS, act_sel + 1)
    elseif b == Input.A     then run_action(ACTIONS[act_sel].id)
    elseif b == Input.B or b == Input.SELECT then State.back() end
  end
end

function S.hat(dir)
  if KB.is_open() then KB.hat(dir); return end
  if Modal.is_open() then return end
  if focus == "tree" then
    if     dir == "up"    then move(-1)
    elseif dir == "down"  then move( 1)
    elseif dir == "left"  then tree_left()
    elseif dir == "right" then tree_right() end
  else
    if     dir == "up"   then act_sel = math.max(1, act_sel - 1)
    elseif dir == "down" then act_sel = math.min(#ACTIONS, act_sel + 1) end
  end
end

function S.key(k)
  if KB.is_open() then KB.key(k); return end
  if Modal.is_open() then
    if k == "return" then Modal.accept()
    elseif k == "escape" then Modal.cancel() end
    return
  end
  if k == "tab" then focus = (focus == "tree") and "actions" or "tree"
  elseif k == "escape" or k == "backspace" then State.back()
  elseif focus == "tree" then
    if     k == "up"    then move(-1)
    elseif k == "down"  then move( 1)
    elseif k == "left"  then tree_left()
    elseif k == "right" then tree_right()
    elseif k == "return" or k == "space" then toggle_mark() end
  else
    if     k == "up"   then act_sel = math.max(1, act_sel - 1)
    elseif k == "down" then act_sel = math.min(#ACTIONS, act_sel + 1)
    elseif k == "return" or k == "space" then run_action(ACTIONS[act_sel].id) end
  end
end

-- ============================================================
--  Drawing
-- ============================================================
local function draw_header()
  local x, y = 20, Frame.TOP_H + 6
  local w = W - 40
  local h = 58
  col({0.020, 0.030, 0.040}, 0.95)
  love.graphics.rectangle("fill", x, y, w, h, 4, 4)
  col(acc, 0.9)
  love.graphics.setLineWidth(1.6)
  love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, 4, 4)
  love.graphics.setLineWidth(1)
  D.corner_ticks(x + 8, y + 8, w - 16, h - 16, 12, acc, 0.85)

  love.graphics.setFont(A.font(A.FONT_TITLE, 14))
  col(acc, 1)
  love.graphics.print("ARCHIVE:RT", x + 14, y + 10)

  love.graphics.setFont(A.font(A.FONT_BODY_BOLD, 12))
  col({1,1,1}, 1)
  love.graphics.print(basename(path), x + 14, y + 28)

  love.graphics.setFont(A.font(A.FONT_MONO, 10))
  col(State.theme.text_dim, 0.85)
  love.graphics.print(ART.kind_label(kind) .. "  ·  " ..
    file_count .. " files  ·  " .. human(total_size), x + 14, y + 44)

  -- selected counter on the right
  local nsel = count_selected()
  if nsel > 0 then
    love.graphics.setFont(A.font(A.FONT_MONO, 10))
    col({0.55, 0.85, 0.45}, 1)
    love.graphics.printf(nsel .. " selected", x, y + 10, w - 14, "right")
  end
end

local function draw_tree(x, y, w, h)
  local th = State.theme
  col({0.020, 0.020, 0.016}, 0.95)
  love.graphics.rectangle("fill", x, y, w, h, 3, 3)
  local acc_a = (focus == "tree") and 0.95 or 0.4
  col(acc, acc_a)
  love.graphics.setLineWidth((focus == "tree") and 1.6 or 1.2)
  love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, 3, 3)
  love.graphics.setLineWidth(1)

  love.graphics.setFont(A.font(A.FONT_MONO, 10))
  col(acc, 0.9)
  love.graphics.print("CONTENTS", x + 10, y + 6)
  col(acc, 0.3)
  love.graphics.rectangle("fill", x + 10, y + 20, w - 20, 1)

  if error_msg then
    col({0.95, 0.35, 0.30}, 0.9)
    love.graphics.setFont(A.font(A.FONT_BODY, 11))
    love.graphics.printf(error_msg, x, y + h/2 - 8, w, "center")
    return
  end

  if #flat == 0 then
    col(th.text_dim, 0.8)
    love.graphics.setFont(A.font(A.FONT_BODY, 11))
    love.graphics.printf("(empty)", x, y + h/2 - 8, w, "center")
    return
  end

  local row_h = 18
  local top = y + 26
  local vis = math.max(1, math.floor((h - 30) / row_h))

  -- Smooth scroll: keep sel 3 from bottom / 1 from top
  local MARGIN_BOTTOM = 3
  local MARGIN_TOP    = 1
  if sel > scroll + vis - MARGIN_BOTTOM then
    scroll = sel - vis + MARGIN_BOTTOM
  elseif sel < scroll + MARGIN_TOP + 1 then
    scroll = math.max(0, sel - MARGIN_TOP - 1)
  end
  scroll = math.max(0, math.min(scroll, math.max(0, #flat - vis)))

  love.graphics.setScissor(x + 1, top, w - 2, h - 28)
  local first = scroll + 1
  local last  = math.min(#flat, first + vis - 1)

  for i = first, last do
    local n = flat[i]
    local ry = top + (i - first) * row_h
    local focused = (focus == "tree") and (i == sel)
    local marked  = marks[n.path]

    if focused then
      col(acc, 0.20)
      love.graphics.rectangle("fill", x + 4, ry - 1, w - 8, row_h, 2, 2)
    elseif marked then
      col({0.55, 0.85, 0.45}, 0.10)
      love.graphics.rectangle("fill", x + 4, ry - 1, w - 8, row_h, 2, 2)
    end

    -- checkbox
    local cbx = x + 10
    local cby = ry + row_h/2 - 1
    if marked then
      col({0.55, 0.85, 0.45}, 1)
      love.graphics.rectangle("fill", cbx - 5, cby - 5, 10, 10, 2, 2)
      col({0.02, 0.05, 0.02}, 1)
      love.graphics.setLineWidth(1.8)
      love.graphics.line(cbx - 2, cby, cbx - 1, cby + 2, cbx + 3, cby - 3)
      love.graphics.setLineWidth(1)
    else
      col(acc, 0.55)
      love.graphics.rectangle("line", cbx - 5, cby - 5, 10, 10, 2, 2)
    end

    -- expand arrow
    local indent = cbx + 12 + (n.depth - 1) * 12
    if n.is_dir then
      col(acc, 0.9)
      if n.expanded then
        love.graphics.polygon("fill",
          indent, ry + 4, indent + 6, ry + 4, indent + 3, ry + 9)
      else
        love.graphics.polygon("fill",
          indent, ry + 3, indent + 5, ry + 7, indent, ry + 11)
      end
    end

    -- icon
    love.graphics.setFont(A.font(A.FONT_BODY, 11))
    col(focused and {1,1,1} or th.text, 1)
    local nm = n.name
    if n.is_dir then nm = nm .. "/" end
    if #nm > 34 then nm = nm:sub(1, 33) .. "…" end
    love.graphics.print(nm, indent + 10, ry + 1)

    -- size on the right
    if not n.is_dir then
      love.graphics.setFont(A.font(A.FONT_MONO, 9))
      col(th.text_dim, 0.7)
      love.graphics.printf(human(n.size), x, ry + 2, w - 8, "right")
    end
  end
  love.graphics.setScissor()

  -- scrollbar
  if #flat > vis then
    local bar_x = x + w - 4
    local bar_y = top
    local bar_h = h - 28
    local thumb_h = math.max(20, bar_h * (vis / #flat))
    local thumb_y = bar_y + (bar_h - thumb_h) * (scroll / (#flat - vis))
    col(acc, 0.55)
    love.graphics.rectangle("fill", bar_x, thumb_y, 2, thumb_h, 1, 1)
  end
end

local function draw_actions(x, y, w, h)
  local th = State.theme
  col({0.020, 0.020, 0.016}, 0.95)
  love.graphics.rectangle("fill", x, y, w, h, 3, 3)
  local amber = {0.94, 0.66, 0.35}
  local acc_a = (focus == "actions") and 0.95 or 0.4
  col(amber, acc_a)
  love.graphics.setLineWidth((focus == "actions") and 1.6 or 1.2)
  love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, 3, 3)
  love.graphics.setLineWidth(1)

  love.graphics.setFont(A.font(A.FONT_MONO, 10))
  col(amber, 0.9)
  love.graphics.print("ACTIONS", x + 10, y + 6)
  col(amber, 0.3)
  love.graphics.rectangle("fill", x + 10, y + 20, w - 20, 1)

  local row_h = 34
  local top = y + 28
  for i, a in ipairs(ACTIONS) do
    local ry = top + (i - 1) * (row_h + 4)
    local focused = (focus == "actions") and (i == act_sel)
    local c = a.colour

    if focused then
      col(c, 0.22)
      love.graphics.rectangle("fill", x + 6, ry, w - 12, row_h, 3, 3)
      col(c, 0.95)
      love.graphics.setLineWidth(1.5)
      love.graphics.rectangle("line", x + 6.5, ry + 0.5, w - 13, row_h - 1, 3, 3)
      love.graphics.setLineWidth(1)
      D.glow(x + w/2, ry + row_h/2, w * 0.6, c, 0.4)
    else
      col(c, 0.12)
      love.graphics.rectangle("fill", x + 6, ry, w - 12, row_h, 3, 3)
      col(c, 0.35)
      love.graphics.rectangle("line", x + 6.5, ry + 0.5, w - 13, row_h - 1, 3, 3)
    end

    love.graphics.setFont(A.font(A.FONT_BODY_BOLD, 11))
    col(focused and {1,1,1} or th.text, 1)
    love.graphics.print(a.label, x + 14, ry + row_h/2 - 7)
  end

  -- Bottom hint
  love.graphics.setFont(A.font(A.FONT_MONO, 9))
  col(th.text_dim, 0.75)
  love.graphics.printf("[A] toggle mark  [X] extract marked\n[TAB] switch panel",
    x, y + h - 30, w, "center")
end

function S.draw()
  local th = State.theme
  D.bg()
  col(th.grid_faint, 0.08)
  for gy = Frame.TOP_H, H - Frame.BOTTOM_H, 16 do
    for gx = 0, W, 16 do love.graphics.rectangle("fill", gx, gy, 1, 1) end
  end

  draw_header()

  local content_y = Frame.TOP_H + 72
  local content_h = H - Frame.BOTTOM_H - content_y - 6

  local tree_w = 380
  local act_w  = W - tree_w - 40 - 8

  draw_tree(20, content_y, tree_w, content_h)
  draw_actions(20 + tree_w + 8, content_y, act_w, content_h)

  Frame.draw_top("FGD", "grid")
  Frame.draw_bottom({
    { key = "l/r",  label = "Expand" },
    { key = "a",    label = "Mark" },
    { key = "x",    label = "Extract marked" },
    { key = "tab",  label = "Actions" },
    { key = "b",    label = "Back" },
  })
  Modal.draw()
  KB.draw()
  D.scanlines(W, H, 0.06)
end

return S
