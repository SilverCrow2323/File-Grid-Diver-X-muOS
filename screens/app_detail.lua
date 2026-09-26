-- screens/app_detail.lua -- muOS app detail.
-- Top: icon + name + size.
-- Left: tree view of files (left/right collapse/expand).
-- Right: action buttons (Migrate / Build muxapp / Uninstall / Info).
-- Tab or L1/R1 to switch focus between tree and actions.
local A     = require("core.assets")
local State = require("core.state")
local Input = require("core.input_map")
local Frame = require("ui.frame")
local D     = require("ui.draw")
local sh    = require("core.sh")
local Notify= require("ui.notify")
local Modal = require("ui.modal")
local FS    = require("services.fs")
local ExtImg= require("core.external_image")

local S = {}
local W, H = 640, 480

local app_path  = nil
local app_name  = nil
local app_icon  = nil
local app_size  = 0
local app_root  = nil
local tree_root = nil
local flat      = {}
local tree_sel  = 1
local scroll    = 0
local focus     = "tree"
local act_sel   = 1
local t_enter   = 0
local icon_img  = nil

local ACTIONS = {
  { id = "migrate",    label = "Migrate to SD2",       colour = {0.48, 0.80, 0.90} },
  { id = "build",      label = "Build muxapp archive", colour = {0.55, 0.85, 0.45} },
  { id = "uninstall",  label = "Uninstall app",        colour = {0.95, 0.35, 0.30} },
  { id = "info",       label = "Info & details",       colour = {0.94, 0.66, 0.35} },
}

local function col(c, a) love.graphics.setColor(c[1], c[2], c[3], a or 1) end
local function human(n)
  if not n or n <= 0 then return "0 B" end
  local u = {"B","KB","MB","GB","TB"}; local i = 1
  while n >= 1024 and i < #u do n = n / 1024; i = i + 1 end
  if i == 1 then return string.format("%d %s", n, u[i]) end
  return string.format("%.1f %s", n, u[i])
end

local function load_children(node)
  if node.children_loaded then return end
  node.children_loaded = true
  node.children = {}
  if not node.is_dir then return end
  local entries = FS.list(node.path)
  FS.sort(entries, "name", true)
  for _, e in ipairs(entries) do
    if e.name ~= ".." then
      node.children[#node.children+1] = {
        name = e.name, path = e.path, is_dir = e.is_dir,
        depth = node.depth + 1, expanded = false,
        children_loaded = false, children = nil,
      }
    end
  end
end

local function flatten(node, out)
  out = out or {}
  for _, n in ipairs(node.children or {}) do
    out[#out+1] = n
    if n.is_dir and n.expanded then flatten(n, out) end
  end
  return out
end

local function rebuild_flat()
  if not tree_root then flat = {} return end
  load_children(tree_root)
  flat = flatten(tree_root)
end

local function init_tree()
  tree_root = {
    name = app_name, path = app_path,
    is_dir = true, depth = 0, expanded = true,
    children_loaded = false, children = nil,
  }
  rebuild_flat()
  tree_sel = 1
  scroll = 0
end

-- ============================================================
--  Actions
-- ============================================================
local function do_migrate()
  local dst_root = "/mnt/sdcard/MUOS/application"
  if not sh.is_dir(dst_root) then
    Notify.show("warning", "SD2 not mounted")
    return
  end
  local dst = dst_root .. "/" .. app_name
  if sh.exists(dst) then
    Modal.show("Already on SD2",
      dst .. "\n\nOverwrite?",
      { accept_label = "OVERWRITE", cancel_label = "CANCEL",
        on_accept = function()
          sh.exec("rm -rf " .. sh.shq(dst))
          local rc = sh.exec("cp -a " .. sh.shq(app_path) .. " " .. sh.shq(dst))
          if rc == 0 then
            Notify.show("success", "copied to SD2")
            sh.exec("rm -rf " .. sh.shq(app_path))
            Notify.show("info", "removed from SD1")
            State.back()
          else
            Notify.show("error", "copy failed")
          end
        end })
    return
  end
  Modal.show("Migrate to SD2",
    "Copy " .. app_name .. "\nto SD2 then remove from SD1?",
    { accept_label = "MIGRATE", cancel_label = "CANCEL",
      on_accept = function()
        local rc = sh.exec("cp -a " .. sh.shq(app_path) .. " " .. sh.shq(dst))
        if rc == 0 then
          Notify.show("success", "copied to SD2")
          sh.exec("rm -rf " .. sh.shq(app_path))
          Notify.show("info", "removed from SD1")
          State.back()
        else
          Notify.show("error", "copy failed")
        end
      end })
end

local function do_build_muxapp()
  local sd1_arch = "/mnt/mmc/ARCHIVE"
  sh.exec("mkdir -p " .. sh.shq(sd1_arch))
  local ts = os.date("%Y%m%d_%H%M%S")
  local out_zip = sd1_arch .. "/" .. app_name .. "_" .. ts .. ".zip"
  local out_muxapp = sd1_arch .. "/" .. app_name .. "_" .. ts .. ".muxapp"
  local parent = app_path:match("^(.*)/[^/]+$") or "."
  Modal.show("Build muxapp",
    "Zip " .. app_name .. "\nand save to SD1/ARCHIVE?",
    { accept_label = "BUILD", cancel_label = "CANCEL",
      on_accept = function()
        local cmd = "cd " .. sh.shq(parent) .. " && zip -r -q " ..
          sh.shq(out_zip) .. " " .. sh.shq(app_name)
        if sh.exec(cmd) == 0 then
          os.rename(out_zip, out_muxapp)
          Notify.show("success", "saved " .. (out_muxapp:match("([^/]+)$") or "?"))
        else
          Notify.show("error", "zip failed")
        end
      end })
end

local function do_uninstall()
  Modal.show("Uninstall " .. app_name,
    "Permanently delete:\n" .. app_path .. "?",
    { accept_label = "DELETE", cancel_label = "CANCEL",
      on_accept = function()
        if sh.exec("rm -rf " .. sh.shq(app_path)) == 0 then
          Notify.show("warning", app_name .. " removed")
          State.back()
        else
          Notify.show("error", "uninstall failed")
        end
      end })
end

local function do_info()
  local lines = {
    "Path:     " .. app_path,
    "Size:     " .. human(app_size),
    "Icon:     " .. (app_icon and app_icon:match("([^/]+)$") or "none"),
    "On SD:    " .. (app_path:match("^/mnt/mmc") and "SD1" or
                     app_path:match("^/mnt/sdcard") and "SD2" or "other"),
  }
  Modal.show("App info", table.concat(lines, "\n"),
    { accept_label = "OK", hide_cancel = true })
end

local function run_action(id)
  if id == "migrate"   then do_migrate()
  elseif id == "build" then do_build_muxapp()
  elseif id == "uninstall" then do_uninstall()
  elseif id == "info"  then do_info() end
end

-- ============================================================
--  Lifecycle
-- ============================================================
function S.enter()
  t_enter = 0
  app_path = State.app_detail_path
  app_name = State.app_detail_name or (app_path and app_path:match("([^/]+)$"))
  app_icon = State.app_detail_icon
  app_size = State.app_detail_size or 0
  app_root = State.app_detail_root
  focus = "tree"
  act_sel = 1

  if app_icon then icon_img = ExtImg.load(app_icon) end
  init_tree()
end
function S.leave() end
function S.update(dt) t_enter = t_enter + dt end

-- ============================================================
--  Input
-- ============================================================
local function tree_move(d)
  if #flat == 0 then return end
  tree_sel = tree_sel + d
  if tree_sel < 1 then tree_sel = 1 end
  if tree_sel > #flat then tree_sel = #flat end
end

local function tree_toggle_expand(node, expand)
  if not node.is_dir then return end
  load_children(node)
  if expand then node.expanded = true else node.expanded = false end
  rebuild_flat()
  if tree_sel > #flat then tree_sel = math.max(1, #flat) end
end

local function tree_left()
  if #flat == 0 then return end
  local n = flat[tree_sel]
  if not n then return end
  if n.is_dir and n.expanded then
    n.expanded = false
    rebuild_flat()
    if tree_sel > #flat then tree_sel = math.max(1, #flat) end
  else
    -- move to parent
    for i = tree_sel - 1, 1, -1 do
      if flat[i].depth < n.depth then tree_sel = i; break end
    end
  end
end

local function tree_right()
  if #flat == 0 then return end
  local n = flat[tree_sel]
  if not n then return end
  if n.is_dir and not n.expanded then
    tree_toggle_expand(n, true)
  elseif n.is_dir and n.expanded and #flat > tree_sel then
    tree_sel = tree_sel + 1
  end
end

function S.pad(b)
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
    if     b == Input.UP    then tree_move(-1)
    elseif b == Input.DOWN  then tree_move( 1)
    elseif b == Input.LEFT  then tree_left()
    elseif b == Input.RIGHT then tree_right()
    elseif b == Input.A     then tree_right()
    elseif b == Input.B or b == Input.SELECT then State.back() end
  else
    if     b == Input.UP    then act_sel = math.max(1, act_sel - 1)
    elseif b == Input.DOWN  then act_sel = math.min(#ACTIONS, act_sel + 1)
    elseif b == Input.A     then run_action(ACTIONS[act_sel].id)
    elseif b == Input.B or b == Input.SELECT then State.back() end
  end
end

function S.hat(dir)
  if Modal.is_open() then return end
  if focus == "tree" then
    if     dir == "up"   then tree_move(-1)
    elseif dir == "down" then tree_move( 1)
    elseif dir == "left" then tree_left()
    elseif dir == "right" then tree_right() end
  else
    if     dir == "up"   then act_sel = math.max(1, act_sel - 1)
    elseif dir == "down" then act_sel = math.min(#ACTIONS, act_sel + 1) end
  end
end

function S.key(k)
  if Modal.is_open() then
    if k == "return" then Modal.accept()
    elseif k == "escape" then Modal.cancel() end
    return
  end
  if k == "tab" then
    focus = (focus == "tree") and "actions" or "tree"
  elseif k == "escape" or k == "backspace" then State.back()
  elseif focus == "tree" then
    if     k == "up"   then tree_move(-1)
    elseif k == "down" then tree_move( 1)
    elseif k == "left" then tree_left()
    elseif k == "right" then tree_right()
    elseif k == "return" or k == "space" then tree_right() end
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
  local h = 66
  col({0.030, 0.035, 0.030}, 0.95)
  love.graphics.rectangle("fill", x, y, w, h, 4, 4)
  col({0.55, 0.85, 0.45}, 0.9)
  love.graphics.setLineWidth(1.6)
  love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, 4, 4)
  love.graphics.setLineWidth(1)
  D.corner_ticks(x + 8, y + 8, w - 16, h - 16, 12, {0.55,0.85,0.45}, 0.85)

  -- icon
  local icx, icy = x + 40, y + h/2
  local ir = 22
  col({0.55*0.22, 0.85*0.22, 0.45*0.22}, 1)
  love.graphics.circle("fill", icx, icy, ir)
  col({0.55,0.85,0.45}, 0.9)
  love.graphics.circle("line", icx, icy, ir)
  if icon_img then
    local iw, ih = icon_img:getDimensions()
    local sc = (ir * 1.6) / math.max(iw, ih)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(icon_img, icx - iw*sc/2, icy - ih*sc/2, 0, sc, sc)
    love.graphics.setColor(1, 1, 1, 1)
  else
    col({0.55,0.85,0.45}, 0.9)
    love.graphics.setLineWidth(1.8)
    for i = 0, 2 do
      for j = 0, 2 do
        love.graphics.rectangle("line",
          icx - ir*0.85 + i * ir*0.62, icy - ir*0.85 + j * ir*0.62,
          ir*0.5, ir*0.5, 1, 1)
      end
    end
    love.graphics.setLineWidth(1)
  end

  love.graphics.setFont(A.font(A.FONT_TITLE, 16))
  col({1, 1, 1}, 1)
  love.graphics.print(app_name or "?", x + 76, y + 12)

  love.graphics.setFont(A.font(A.FONT_MONO, 10))
  col(State.theme.text_dim, 0.85)
  love.graphics.print(app_path or "?", x + 76, y + 34)
  col({0.55,0.85,0.45}, 0.9)
  love.graphics.print(human(app_size), x + 76, y + 48)
end

local function draw_tree(x, y, w, h)
  local th = State.theme
  col({0.020, 0.020, 0.016}, 0.95)
  love.graphics.rectangle("fill", x, y, w, h, 3, 3)
  local acc = {0.48, 0.80, 0.90}
  local acc_alpha = (focus == "tree") and 0.95 or 0.4
  col(acc, acc_alpha)
  love.graphics.setLineWidth((focus == "tree") and 1.6 or 1.2)
  love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, 3, 3)
  love.graphics.setLineWidth(1)

  love.graphics.setFont(A.font(A.FONT_MONO, 10))
  col(acc, 0.9)
  love.graphics.print("FILES", x + 10, y + 6)
  col(acc, 0.3)
  love.graphics.rectangle("fill", x + 10, y + 20, w - 20, 1)

  local row_h = 16
  local top = y + 26
  local vis = math.max(1, math.floor((h - 30) / row_h))
  local first = 1
  if tree_sel > vis - 2 then first = math.max(1, tree_sel - vis + 3) end
  first = math.min(first, math.max(1, #flat - vis + 1))

  for i = first, math.min(#flat, first + vis - 1) do
    local n = flat[i]
    local ry = top + (i - first) * row_h
    local focused = (focus == "tree") and (i == tree_sel)

    if focused then
      col(acc, 0.20)
      love.graphics.rectangle("fill", x + 4, ry - 1, w - 8, row_h, 2, 2)
    end

    local indent = 8 + (n.depth - 1) * 12
    -- arrow / dot
    col(acc, 0.9)
    if n.is_dir then
      if n.expanded then
        love.graphics.polygon("fill",
          x + indent, ry + 3,
          x + indent + 6, ry + 3,
          x + indent + 3, ry + 8)
      else
        love.graphics.polygon("fill",
          x + indent, ry + 2,
          x + indent + 5, ry + 6,
          x + indent, ry + 10)
      end
    else
      love.graphics.rectangle("fill", x + indent + 1, ry + 5, 4, 4)
    end

    love.graphics.setFont(A.font(A.FONT_BODY, 11))
    col(focused and {1,1,1} or th.text, 1)
    local nm = n.name
    if #nm > 30 then nm = nm:sub(1, 29) .. "…" end
    love.graphics.print(nm, x + indent + 12, ry)
  end
end

local function draw_actions(x, y, w, h)
  local th = State.theme
  col({0.020, 0.020, 0.016}, 0.95)
  love.graphics.rectangle("fill", x, y, w, h, 3, 3)
  local acc = {0.94, 0.66, 0.35}
  local acc_alpha = (focus == "actions") and 0.95 or 0.4
  col(acc, acc_alpha)
  love.graphics.setLineWidth((focus == "actions") and 1.6 or 1.2)
  love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, 3, 3)
  love.graphics.setLineWidth(1)

  love.graphics.setFont(A.font(A.FONT_MONO, 10))
  col(acc, 0.9)
  love.graphics.print("ACTIONS", x + 10, y + 6)
  col(acc, 0.3)
  love.graphics.rectangle("fill", x + 10, y + 20, w - 20, 1)

  local row_h = 32
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
end

function S.draw()
  local th = State.theme
  D.bg()
  col(th.grid_faint, 0.08)
  for gy = Frame.TOP_H, H - Frame.BOTTOM_H, 16 do
    for gx = 0, W, 16 do love.graphics.rectangle("fill", gx, gy, 1, 1) end
  end

  draw_header()

  local content_y = Frame.TOP_H + 78
  local content_h = H - Frame.BOTTOM_H - content_y - 6

  local tree_w = 340
  local act_w  = W - tree_w - 40 - 8

  draw_tree(20, content_y, tree_w, content_h)
  draw_actions(20 + tree_w + 8, content_y, act_w, content_h)

  Frame.draw_top("FGD", "plugins")
  Frame.draw_bottom({
    { key = "l/r",  label = "Expand" },
    { key = "tab",  label = "Switch" },
    { key = "a",    label = "Run" },
    { key = "b",    label = "Back" },
  })
  Modal.draw()
  D.scanlines(W, H, 0.06)
end

return S
