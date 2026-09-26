-- screens/about.lua -- About File-GD X.
-- Project info, creator avatar, SPDW Factory logo, Minoru mascot.
-- B returns to Settings with "About File-GD X" highlighted.
local A     = require("core.assets")
local State = require("core.state")
local Input = require("core.input_map")
local Frame = require("ui.frame")
local D     = require("ui.draw")
local sh    = require("core.sh")

local S = {}
local W, H = 640, 480

-- ============================================================
--  Project metadata
-- ============================================================
local ABOUT = {
  product  = "File-GD X",
  tagline  = "the system console for a muOS handheld",
  version  = "v1.5.0",
  project  = "SPDW Factory",
  author   = "sirpips",
  aka      = "aka SilverCrow2323",
  license  = "GPL-3.0-or-later",
  built    = "LOVE 11.5 / LuaJIT / muOS H700",
}

local info = {}
local t_enter = 0

-- ============================================================
--  Live info gathering
-- ============================================================
local function read_cpu()
  local model = "unknown"
  local f = io.open("/proc/cpuinfo", "r")
  if f then
    for line in f:lines() do
      local m = line:match("^model name%s*:%s*(.+)$")
             or line:match("^Hardware%s*:%s*(.+)$")
      if m then model = m; break end
    end
    f:close()
  end
  return model
end

local function read_uptime()
  local f = io.open("/proc/uptime", "r")
  if not f then return "?" end
  local s = f:read("*l") or "0"
  f:close()
  local up = math.floor(tonumber(s:match("^(%d+)")) or 0)
  return string.format("%dd %02dh %02dm",
    math.floor(up / 86400),
    math.floor((up % 86400) / 3600),
    math.floor((up % 3600) / 60))
end

function S.enter()
  t_enter = 0
  info.cpu    = read_cpu()
  info.uptime = read_uptime()
  info.kernel = (sh.read("uname -srm") or "?"):gsub("\n", "")
  info.home   = os.getenv("HOME") or "?"
  info.cwd    = State.cwd or "?"
  info.love   = string.format("%d.%d.%d", love.getVersion())
  info.lua    = _VERSION or "?"
end

function S.leave() end
function S.update(dt) t_enter = t_enter + dt end

-- ============================================================
--  Input
-- ============================================================
function S.pad(b)
  if b == Input.B or b == Input.SELECT or b == Input.A then
    State.back()
  end
end

function S.hat(_) end

function S.key(k)
  if k == "escape" or k == "backspace" or k == "return" then
    State.back()
  end
end

-- ============================================================
--  Drawing helpers
-- ============================================================
local function col(c, a) love.graphics.setColor(c[1], c[2], c[3], a or 1) end

local function draw_bg_grid()
  local th = State.theme
  col(th.grid_faint, 0.08)
  for gy = Frame.TOP_H, H - Frame.BOTTOM_H, 16 do
    for gx = 0, W, 16 do
      love.graphics.rectangle("fill", gx, gy, 1, 1)
    end
  end
end

-- Draw an image fitted inside a box (keeps aspect ratio)
local function draw_image_fit(path, x, y, w, h, alpha)
  local img = A.image(path)
  if not img then return false end
  local iw, ih = img:getDimensions()
  local sc = math.min(w / iw, h / ih)
  local dw, dh = iw * sc, ih * sc
  local dx = x + (w - dw) / 2
  local dy = y + (h - dh) / 2
  love.graphics.setColor(1, 1, 1, alpha or 1)
  love.graphics.draw(img, dx, dy, 0, sc, sc)
  love.graphics.setColor(1, 1, 1, 1)
  return true
end

-- Draw a rounded rect panel with subtle border
local function panel(x, y, w, h, accent, focused)
  col({0.025, 0.022, 0.030}, 0.95)
  love.graphics.rectangle("fill", x, y, w, h, 5, 5)

  if focused then
    col(accent, 0.85)
    love.graphics.setLineWidth(1.6)
  else
    col(accent, 0.35)
    love.graphics.setLineWidth(1)
  end
  love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, 5, 5)
  love.graphics.setLineWidth(1)

  D.corner_ticks(x + 6, y + 6, w - 12, h - 12, 10, accent,
    focused and 0.9 or 0.4)
end

-- ============================================================
--  Main draw
-- ============================================================
function S.draw()
  local th = State.theme
  D.bg()
  draw_bg_grid()

  -- ==========================================================
  --  HERO: title4.png with SPDW Factory
  -- ==========================================================
  local hero_y = Frame.TOP_H + 8
  local hero_h = 100

  local title_img = A.image("assets/images/titles/title4.png")
  if title_img then
    local iw, ih = title_img:getDimensions()
    local target_w = math.min(W - 80, 460)
    local sc = target_w / iw
    local dh = ih * sc
    local dx = (W - target_w) / 2
    local dy = hero_y + (hero_h - dh) / 2
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(title_img, dx, dy, 0, sc, sc)
    love.graphics.setColor(1, 1, 1, 1)
  else
    -- Fallback: logo + testo
    draw_image_fit("assets/images/fgd_logo.png", 20, hero_y, 260, hero_h - 20, 1)
    love.graphics.setFont(A.font(A.FONT_TITLE, 22))
    col(th.text_bright, 1)
    love.graphics.print(ABOUT.product, 300, hero_y + 12)
    love.graphics.setFont(A.font(A.FONT_BODY, 11))
    col(th.text_dim, 0.9)
    love.graphics.print(ABOUT.tagline, 302, hero_y + 44)
    love.graphics.setFont(A.font(A.FONT_MONO, 11))
    col(th.amber_hi, 1)
    love.graphics.print(ABOUT.version .. "  ·  " .. ABOUT.project, 302, hero_y + 64)
  end

  -- Separator
  col(th.amber_lo, 0.4)
  love.graphics.rectangle("fill", 20, hero_y + hero_h, W - 40, 1)

  -- ==========================================================
  --  CREATOR panel (left) + SPDW Factory / Minoru (right)
  -- ==========================================================
  local y = hero_y + hero_h + 10
  local panel_h = 120

  -- Left: creator card
  local left_w = 300
  panel(20, y, left_w, panel_h, th.amber_hi, true)

  -- Avatar
  local avatar_x = 34
  local avatar_y = y + 14
  local avatar_s = 92
  local avatar_ok = draw_image_fit("assets/images/sirpips.jpeg",
    avatar_x, avatar_y, avatar_s, avatar_s, 1)

  if not avatar_ok then
    -- Fallback: circle with initials
    col(th.amber_hi, 0.25)
    love.graphics.circle("fill",
      avatar_x + avatar_s / 2, avatar_y + avatar_s / 2, avatar_s / 2)
    col(th.amber_hi, 1)
    love.graphics.setLineWidth(2)
    love.graphics.circle("line",
      avatar_x + avatar_s / 2, avatar_y + avatar_s / 2, avatar_s / 2)
    love.graphics.setLineWidth(1)
    love.graphics.setFont(A.font(A.FONT_TITLE, 32))
    love.graphics.printf("SP", avatar_x, avatar_y + avatar_s / 2 - 18,
      avatar_s, "center")
  end

  -- Creator name
  local tx = avatar_x + avatar_s + 14
  love.graphics.setFont(A.font(A.FONT_MONO, 9))
  col(th.amber_hi, 0.9)
  love.graphics.print("CREATOR", tx, y + 16)

  love.graphics.setFont(A.font(A.FONT_TITLE, 17))
  col(th.text_bright, 1)
  love.graphics.print(ABOUT.author, tx, y + 30)

  love.graphics.setFont(A.font(A.FONT_BODY, 10))
  col(th.text_dim, 0.9)
  love.graphics.print(ABOUT.aka, tx, y + 52)

  love.graphics.setFont(A.font(A.FONT_MONO, 9))
  col(th.text_dim, 0.85)
  love.graphics.print("design · code · stubborn", tx, y + 74)
  love.graphics.print("refusal to ship a bad UI", tx, y + 86)

  -- Right: SPDW Factory + Minoru
  local right_x = 20 + left_w + 10
  local right_w = W - right_x - 20
  panel(right_x, y, right_w, panel_h, th.cyan_hi, false)

  -- SPDW Factory logo on top half
  local spdw_h = 60
  local spdw_ok = draw_image_fit("assets/images/spdwfactory_logo.png",
    right_x + 8, y + 6, right_w - 16, spdw_h, 1)
  if not spdw_ok then
    love.graphics.setFont(A.font(A.FONT_MONO, 11))
    col(th.cyan_hi, 1)
    love.graphics.printf("SPDW FACTORY", right_x, y + 20, right_w, "center")
  end

  -- Divider
  col(th.cyan_hi, 0.25)
  love.graphics.rectangle("fill", right_x + 12, y + spdw_h + 10,
    right_w - 24, 1)

  -- Minoru icon + name
  local minu_y = y + spdw_h + 16
  local minu_h = panel_h - (spdw_h + 24)
  local minu_size = minu_h - 8
  local minu_ok = draw_image_fit("assets/images/minoru_icon.png",
    right_x + 12, minu_y, minu_size, minu_size, 1)
  if not minu_ok then
    col(th.green, 0.8)
    love.graphics.setLineWidth(1.6)
    love.graphics.circle("line",
      right_x + 12 + minu_size / 2, minu_y + minu_size / 2, minu_size / 2)
    love.graphics.setLineWidth(1)
  end

  love.graphics.setFont(A.font(A.FONT_MONO, 9))
  col(th.green, 0.9)
  love.graphics.print("MASCOT", right_x + minu_size + 20, minu_y + 2)

  love.graphics.setFont(A.font(A.FONT_BODY_BOLD, 12))
  col(th.text_bright, 1)
  love.graphics.print("Minoru-sensei", right_x + minu_size + 20, minu_y + 16)

  love.graphics.setFont(A.font(A.FONT_MONO, 9))
  col(th.text_dim, 0.85)
  love.graphics.print("guardian of the store", right_x + minu_size + 20,
    minu_y + 36)

  -- ==========================================================
  --  TECH INFO (bottom, 2 columns)
  -- ==========================================================
  local ty = y + panel_h + 10
  local tech_h = H - Frame.BOTTOM_H - ty - 8

  panel(20, ty, W - 40, tech_h, th.amber_hi, false)

  love.graphics.setFont(A.font(A.FONT_MONO, 10))
  col(th.amber_hi, 1)
  love.graphics.print("TECHNICAL", 34, ty + 8)

  -- left column
  local lx = 34
  local rx = W / 2 + 10
  local ry = ty + 28
  local step = 15

  local function row(x, yy, k, v)
    love.graphics.setFont(A.font(A.FONT_MONO, 9))
    col(th.text_dim, 0.85)
    love.graphics.print(k, x, yy)
    love.graphics.setFont(A.font(A.FONT_BODY_BOLD, 10))
    col(th.text_bright, 1)
    love.graphics.print(v, x + 62, yy - 1)
  end

  -- left col
  row(lx, ry, "ENGINE", ABOUT.built); ry = ry + step
  row(lx, ry, "LOVE",   info.love);   ry = ry + step
  row(lx, ry, "LUA",    info.lua);    ry = ry + step
  row(lx, ry, "LICENSE", ABOUT.license)

  -- right col
  ry = ty + 28
  row(rx, ry, "KERNEL", info.kernel or "?"); ry = ry + step
  row(rx, ry, "CPU",    (info.cpu or "?"):sub(1, 30)); ry = ry + step
  row(rx, ry, "UPTIME", info.uptime or "?"); ry = ry + step
  row(rx, ry, "HOME",   (info.home or "?"):sub(1, 26))

  -- Footer credit
  love.graphics.setFont(A.font(A.FONT_MONO, 9))
  col(th.text_dim, 0.7)
  love.graphics.printf(
    "for muOS / Anbernic H700  ·  part of the SPDW Factory family",
    0, ty + tech_h - 16, W, "center")

  -- ==========================================================
  --  Frame
  -- ==========================================================
  Frame.draw_top("FGD", "about")
  Frame.draw_bottom({
    { key = "b", label = "Back" },
  })
  D.scanlines(W, H, 0.06)
  D.vignette(W, H, 0.55)
end

return S
