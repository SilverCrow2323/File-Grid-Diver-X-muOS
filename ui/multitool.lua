-- ui/multitool.lua -- context action menu on the focused item.
local A     = require("core.assets")
local D     = require("ui.draw")

local M = { open_flag = false, item = nil, sel = 1, actions = {}, t = 0 }

local function build_actions(item, ctx)
  if not item then return {} end
  local a = {}
  if item.is_dir then
    a[#a+1] = { key = "open",    label = "Open folder" }
    a[#a+1] = { key = "zip",     label = "Compress to .zip" }
    a[#a+1] = { key = "targz",   label = "Compress to .tar.gz" }
  elseif ctx.is_archive then
    a[#a+1] = { key = "extract", label = "Extract here" }
    a[#a+1] = { key = "exfold",  label = "Extract to folder" }
    a[#a+1] = { key = "list",    label = "List contents" }
    a[#a+1] = { key = "edit",    label = "Open in editor" }
  else
    a[#a+1] = { key = "edit",    label = "Open in editor" }
    a[#a+1] = { key = "zip",     label = "Compress to .zip" }
    a[#a+1] = { key = "targz",   label = "Compress to .tar.gz" }
  end
  a[#a+1] = { key = "sep" }
  a[#a+1] = { key = "copy",      label = "Copy" }
  a[#a+1] = { key = "cut",       label = "Cut" }
  a[#a+1] = { key = "paste",     label = "Paste here" }
  a[#a+1] = { key = "sep" }
  a[#a+1] = { key = "rename",    label = "Rename" }
  a[#a+1] = { key = "delete",    label = "Delete (to trash)" }
  a[#a+1] = { key = "sep" }
  a[#a+1] = { key = "props",     label = "Properties" }
  a[#a+1] = { key = "chmodx",    label = "chmod +x" }
  a[#a+1] = { key = "chmod-x",   label = "chmod -x" }
  a[#a+1] = { key = "checksum",  label = "Checksum (md5)" }
  a[#a+1] = { key = "symlink",   label = "Create symlink" }
  a[#a+1] = { key = "sep" }
  a[#a+1] = { key = "cancel",    label = "Cancel" }
  return a
end

function M.show(item, ctx)
  M.item = item
  M.actions = build_actions(item, ctx or {})
  M.sel = 1
  M.t = 0
  M.open_flag = true
end

function M.close() M.open_flag = false; M.item = nil end
function M.is_open() return M.open_flag end

function M.update(dt)
  if M.open_flag then M.t = M.t + dt end
end

local function skip_sep(dir)
  local n = #M.actions
  local t = 0
  while M.actions[M.sel] and M.actions[M.sel].key == "sep" do
    M.sel = M.sel + dir
    if M.sel < 1 then M.sel = n end
    if M.sel > n then M.sel = 1 end
    t = t + 1
    if t > n then break end
  end
end

function M.move(dir)
  M.sel = M.sel + dir
  if M.sel < 1 then M.sel = #M.actions end
  if M.sel > #M.actions then M.sel = 1 end
  skip_sep(dir)
end

function M.get_selected()
  return M.actions[M.sel] and M.actions[M.sel].key
end

local function col(x, y, w, h, a)
  love.graphics.setColor(a[1], a[2], a[3], a[4] or 1)
  love.graphics.rectangle("fill", x, y, w, h)
end

function M.draw()
  if not M.open_flag then return end
  local ok, State = pcall(require, "core.state")
  local th = ok and State.theme or {
    text = {0.85, 0.82, 0.76}, text_dim = {0.44, 0.42, 0.38},
    panel = {0.05, 0.05, 0.04}, amber = {0.94, 0.66, 0.35},
    amber_hi = {0.94, 0.66, 0.35}, amber_lo = {0.35, 0.22, 0.10},
  }
  local W = love.graphics.getWidth()
  local H = love.graphics.getHeight()

  love.graphics.setColor(0, 0, 0, 0.55)
  love.graphics.rectangle("fill", 0, 0, W, H)

  local row_h = 20
  local pad   = 10
  local item_h = 20
  local total_h = pad * 2
  for _, a in ipairs(M.actions) do
    total_h = total_h + (a.key == "sep" and 8 or item_h)
  end
  local w = 260
  local h = total_h
  local x = math.floor((W - w) / 2)
  local y = math.floor((H - h) / 2)

  love.graphics.setColor(th.panel)
  love.graphics.rectangle("fill", x, y, w, h)
  love.graphics.setColor(th.amber_lo[1], th.amber_lo[2], th.amber_lo[3], 0.9)
  love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1)
  D.corner_ticks(x + 6, y + 6, w - 12, h - 12, 12, th.amber_hi, 0.9)

  love.graphics.setColor(th.amber_hi)
  love.graphics.setFont(A.font(A.FONT_BODY_BOLD, 14))
  local name = M.item and (M.item.path:match("([^/]+)$") or "?") or "?"
  love.graphics.print("> ACTION", x + 14, y + 6)
  love.graphics.setColor(th.text_dim)
  love.graphics.setFont(A.font(A.FONT_BODY, 12))
  love.graphics.print(name:sub(1, 30), x + 14, y + 22)

  local ry = y + 42
  for i, a in ipairs(M.actions) do
    if a.key == "sep" then
      love.graphics.setColor(th.amber_lo[1], th.amber_lo[2], th.amber_lo[3], 0.4)
      love.graphics.rectangle("fill", x + 12, ry + 3, w - 24, 1)
      ry = ry + 8
    else
      local focused = (i == M.sel)
      if focused then
        love.graphics.setColor(th.amber_hi[1], th.amber_hi[2], th.amber_hi[3], 0.20)
        love.graphics.rectangle("fill", x + 8, ry - 1, w - 16, item_h, 2, 2)
      end
      love.graphics.setColor(focused and th.amber_hi or th.text)
      love.graphics.setFont(A.font(A.FONT_BODY, 14))
      love.graphics.print(a.label, x + 18, ry + 3)
      ry = ry + item_h
    end
  end
end

return M
