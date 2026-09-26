-- screens/plugin_info.lua -- Rich showcase for any plugin without a dedicated screen.
-- Reads metadata from the catalog, shows hero + features + status.
local A     = require("core.assets")
local State = require("core.state")
local Input = require("core.input_map")
local Frame = require("ui.frame")
local D     = require("ui.draw")
local Notify= require("ui.notify")
local sh    = require("core.sh")
local Cat   = require("services.catalog")
local PR    = require("services.plugin_registry")

local S = {}
local W, H = 640, 480

local function col(c, a) love.graphics.setColor(c[1], c[2], c[3], a or 1) end

local plugin_id = nil
local plugin    = nil
local acc       = {0.70, 0.55, 0.92}
local t_enter   = 0

local function draw_icon(kind, cx, cy, r, colour, alpha)
  col(colour, alpha or 1)
  love.graphics.setLineWidth(1.8)
  if kind == "pdf" then
    love.graphics.rectangle("line", cx - r*0.6, cy - r*0.75, r*1.2, r*1.5, 2, 2)
    love.graphics.line(cx - r*0.35, cy - r*0.45, cx + r*0.35, cy - r*0.45)
    love.graphics.line(cx - r*0.35, cy - r*0.15, cx + r*0.35, cy - r*0.15)
  elseif kind == "archive" then
    love.graphics.rectangle("line", cx - r*0.75, cy - r*0.15, r*1.5, r*0.75, 2, 2)
    love.graphics.rectangle("line", cx - r*0.75, cy - r*0.55, r*1.5, r*0.35, 2, 2)
    love.graphics.rectangle("fill", cx - r*0.15, cy - r*0.15, r*0.3, r*0.35)
  elseif kind == "office" then
    love.graphics.rectangle("line", cx - r*0.6, cy - r*0.75, r*1.2, r*1.5, 2, 2)
    love.graphics.rectangle("fill", cx - r*0.4, cy + r*0.10, r*0.18, r*0.35)
    love.graphics.rectangle("fill", cx - r*0.09, cy - r*0.15, r*0.18, r*0.60)
    love.graphics.rectangle("fill", cx + r*0.22, cy - r*0.40, r*0.18, r*0.85)
  elseif kind == "web" then
    love.graphics.circle("line", cx, cy, r*0.80)
    love.graphics.ellipse("line", cx, cy, r*0.32, r*0.80)
    love.graphics.line(cx - r*0.80, cy, cx + r*0.80, cy)
  elseif kind == "media" then
    love.graphics.rectangle("line", cx - r*0.75, cy - r*0.75, r*1.5, r*1.5, 3, 3)
    love.graphics.polygon("fill", cx - r*0.20, cy - r*0.40, cx - r*0.20, cy + r*0.40, cx + r*0.45, cy)
  elseif kind == "comic" then
    love.graphics.rectangle("line", cx - r*0.75, cy - r*0.75, r*0.65, r*1.5, 2, 2)
    love.graphics.rectangle("line", cx + r*0.10, cy - r*0.75, r*0.65, r*1.5, 2, 2)
  elseif kind == "font" then
    love.graphics.line(cx - r*0.35, cy + r*0.35, cx - r*0.15, cy - r*0.55)
    love.graphics.line(cx - r*0.15, cy - r*0.55, cx + r*0.05, cy + r*0.35)
    love.graphics.line(cx - r*0.28, cy - r*0.05, cx - r*0.02, cy - r*0.05)
  elseif kind == "hex" then
    love.graphics.rectangle("line", cx - r*0.75, cy - r*0.75, r*1.5, r*1.5, 2, 2)
    for i = 0, 3 do love.graphics.line(cx - r*0.55, cy - r*0.55 + i * r*0.36, cx + r*0.55, cy - r*0.55 + i * r*0.36) end
  else
    love.graphics.circle("line", cx, cy, r*0.8)
  end
  love.graphics.setLineWidth(1)
end

local function status_of(p)
  if p.coming_soon then return "COMING SOON", {0.30, 0.85, 0.95} end
  if PR.is_disabled(p.id) then return "DISABLED", {0.55, 0.55, 0.60} end
  if p.builtin then return "READY", {0.35, 0.90, 0.50} end
  local out = sh.read(p.installed_check or "echo no")
  if out and out:find("ok", 1, true) then return "READY", {0.35, 0.90, 0.50} end
  return "NOT INSTALLED", {0.95, 0.35, 0.30}
end

function S.enter()
  t_enter = 0
  plugin_id = State.plugin_info_id
  State.plugin_info_id = nil
  plugin = plugin_id and Cat.plugin_by_id(plugin_id) or nil
  if plugin and plugin.colour then acc = plugin.colour end
end
function S.leave() end
function S.update(dt) t_enter = t_enter + dt end

function S.pad(b)
  if b == Input.A then
    -- If plugin has open_screen, jump there
    if plugin and plugin.open_screen and plugin.open_screen ~= "plugin_info" then
      State.go(plugin.open_screen)
    end
  elseif b == Input.B or b == Input.SELECT then
    State.back()
  end
end
function S.hat(_) end
function S.key(k)
  if k == "escape" or k == "backspace" then State.back()
  elseif k == "return" or k == "space" then S.pad(Input.A) end
end

function S.draw()
  local th = State.theme
  D.bg()
  col(acc, 0.06)
  for gy = Frame.TOP_H, H - Frame.BOTTOM_H, 18 do
    for gx = 0, W, 18 do love.graphics.rectangle("fill", gx, gy, 1, 1) end
  end

  if not plugin then
    love.graphics.setFont(A.font(A.FONT_BODY, 14))
    col(th.text_dim, 0.9)
    love.graphics.printf("plugin not found", 0, H/2, W, "center")
    return
  end

  -- Hero panel
  local hy = Frame.TOP_H + 12
  local hw = W - 40
  local hh = 90
  col({0.030, 0.020, 0.045}, 0.95)
  love.graphics.rectangle("fill", 20, hy, hw, hh, 5, 5)
  col(acc, 0.85)
  love.graphics.setLineWidth(1.6)
  love.graphics.rectangle("line", 20.5, hy + 0.5, hw - 1, hh - 1, 5, 5)
  love.graphics.setLineWidth(1)
  D.corner_ticks(28, hy + 8, hw - 16, hh - 16, 12, acc, 0.9)

  -- Icon
  local icx = 20 + 46
  local icy = hy + hh / 2
  col(acc, 0.25)
  love.graphics.circle("fill", icx, icy, 28)
  col(acc, 0.95)
  love.graphics.circle("line", icx, icy, 28)
  draw_icon(plugin.icon or "?", icx, icy, 20, acc, 1)

  -- Name + tagline + version
  love.graphics.setFont(A.font(A.FONT_TITLE, 18))
  col(acc, 1)
  love.graphics.print(plugin.name or "?", 20 + 88, hy + 12)

  love.graphics.setFont(A.font(A.FONT_BODY, 11))
  col(th.text, 0.9)
  love.graphics.print(plugin.tagline or "", 20 + 88, hy + 36)

  love.graphics.setFont(A.font(A.FONT_MONO, 9))
  col(th.text_dim, 0.85)
  love.graphics.print("v" .. (plugin.version or "?") .. "  ·  " ..
    (plugin.author or "sirpips") .. "  ·  " .. (plugin.source or "?"),
    20 + 88, hy + 58)

  -- Status pill
  local label, colr = status_of(plugin)
  local f = A.font(A.FONT_MONO, 9)
  love.graphics.setFont(f)
  local tw = f:getWidth(label) + 20
  local pill_x = 20 + hw - tw - 12
  col({colr[1]*0.22, colr[2]*0.22, colr[3]*0.22}, 1)
  love.graphics.rectangle("fill", pill_x, hy + 12, tw, 18, 9, 9)
  col(colr, 0.95)
  love.graphics.rectangle("line", pill_x + 0.5, hy + 12.5, tw - 1, 17, 9, 9)
  col(colr, 1)
  love.graphics.circle("fill", pill_x + 9, hy + 21, 2.5)
  col({1,1,1}, 1)
  love.graphics.printf(label, pill_x + 14, hy + 17, tw - 18, "left")

  -- Two-column body
  local body_y = hy + hh + 8
  local left_x = 20
  local left_w = (W - 40 - 8) * 0.58
  local right_x = left_x + left_w + 8
  local right_w = W - 40 - left_w - 8

  -- Left: description + features
  local body_h = H - Frame.BOTTOM_H - body_y - 8

  -- Description panel
  local desc_h = 76
  col({0.025, 0.020, 0.035}, 0.9)
  love.graphics.rectangle("fill", left_x, body_y, left_w, desc_h, 4, 4)
  col(acc, 0.45)
  love.graphics.rectangle("line", left_x + 0.5, body_y + 0.5, left_w - 1, desc_h - 1, 4, 4)
  love.graphics.setFont(A.font(A.FONT_MONO, 9))
  col(acc, 0.9)
  love.graphics.print("DESCRIPTION", left_x + 10, body_y + 6)
  col(acc, 0.3)
  love.graphics.rectangle("fill", left_x + 10, body_y + 20, left_w - 20, 1)
  love.graphics.setFont(A.font(A.FONT_BODY, 10))
  col(th.text, 0.95)
  love.graphics.printf(plugin.description or "", left_x + 10, body_y + 26, left_w - 20, "left")

  -- Features panel
  local feat_y = body_y + desc_h + 6
  local feat_h = body_h - desc_h - 6
  col({0.025, 0.020, 0.035}, 0.9)
  love.graphics.rectangle("fill", left_x, feat_y, left_w, feat_h, 4, 4)
  col(acc, 0.45)
  love.graphics.rectangle("line", left_x + 0.5, feat_y + 0.5, left_w - 1, feat_h - 1, 4, 4)
  love.graphics.setFont(A.font(A.FONT_MONO, 9))
  col(acc, 0.9)
  love.graphics.print("FEATURES", left_x + 10, feat_y + 6)
  col(acc, 0.3)
  love.graphics.rectangle("fill", left_x + 10, feat_y + 20, left_w - 20, 1)
  love.graphics.setFont(A.font(A.FONT_BODY, 10))
  local fy = feat_y + 26
  for _, feat in ipairs(plugin.features or {}) do
    if fy > feat_y + feat_h - 12 then break end
    col({0.35, 0.90, 0.50}, 1)
    love.graphics.print(">", left_x + 12, fy)
    col(th.text, 0.95)
    love.graphics.print(feat, left_x + 24, fy)
    fy = fy + 14
  end

  -- Right: requires + info
  local dep_h = 24 + #(plugin.dependencies or {}) * 14
  if dep_h < 60 then dep_h = 60 end
  col({0.025, 0.020, 0.035}, 0.9)
  love.graphics.rectangle("fill", right_x, body_y, right_w, dep_h, 4, 4)
  col(acc, 0.45)
  love.graphics.rectangle("line", right_x + 0.5, body_y + 0.5, right_w - 1, dep_h - 1, 4, 4)
  love.graphics.setFont(A.font(A.FONT_MONO, 9))
  col(acc, 0.9)
  love.graphics.print("REQUIRES", right_x + 10, body_y + 6)
  col(acc, 0.3)
  love.graphics.rectangle("fill", right_x + 10, body_y + 20, right_w - 20, 1)
  local dy = body_y + 26
  for _, dep in ipairs(plugin.dependencies or {}) do
    local ok = true
    if dep ~= "built-in engine" then
      ok = (sh.exec("command -v " .. dep .. " >/dev/null 2>&1") == 0)
    end
    love.graphics.setFont(A.font(A.FONT_MONO, 9))
    if ok then col({0.35, 0.90, 0.50}, 1); love.graphics.print("OK", right_x + 10, dy)
    else col({0.95, 0.35, 0.30}, 1); love.graphics.print("--", right_x + 10, dy) end
    love.graphics.setFont(A.font(A.FONT_BODY, 10))
    col(th.text, 0.95)
    love.graphics.print(dep, right_x + 30, dy)
    dy = dy + 14
  end

  -- Info panel
  local info_y = body_y + dep_h + 6
  local info_h = body_h - dep_h - 6
  col({0.025, 0.020, 0.035}, 0.9)
  love.graphics.rectangle("fill", right_x, info_y, right_w, info_h, 4, 4)
  col(acc, 0.45)
  love.graphics.rectangle("line", right_x + 0.5, info_y + 0.5, right_w - 1, info_h - 1, 4, 4)
  love.graphics.setFont(A.font(A.FONT_MONO, 9))
  col(acc, 0.9)
  love.graphics.print("INFO", right_x + 10, info_y + 6)
  col(acc, 0.3)
  love.graphics.rectangle("fill", right_x + 10, info_y + 20, right_w - 20, 1)
  local ty = info_y + 26
  local function row(k, v)
    love.graphics.setFont(A.font(A.FONT_MONO, 8))
    col(th.text_dim, 0.8)
    love.graphics.print(k, right_x + 10, ty)
    love.graphics.setFont(A.font(A.FONT_BODY, 9))
    col(th.text, 0.9)
    local short = v or "-"
    if #short > 24 then short = short:sub(1, 23) .. "." end
    love.graphics.print(short, right_x + 10, ty + 10)
    ty = ty + 22
  end
  row("USAGE", plugin.usage)
  row("LICENSE", plugin.license)
  row("DATE", plugin.date_added)

  Frame.draw_top("FGD", "plugins")
  local hints
  if plugin.open_screen and plugin.open_screen ~= "plugin_info" then
    hints = { { key = "a", label = "Open" }, { key = "b", label = "Back" } }
  else
    hints = { { key = "b", label = "Back" } }
  end
  Frame.draw_bottom(hints)
  D.scanlines(W, H, 0.06)
end

return S
