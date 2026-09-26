-- ui/perm_dialog.lua -- cyberpunk permission consent screen.
local A     = require("core.assets")
local State = require("core.state")
local Input = require("core.input_map")
local D     = require("ui.draw")
local BI    = require("ui.button_icons")
local RT    = require("ui.richtext")

local M = {}

local EXPLAIN = {
  ["filesystem.read"]  = "Reads files and folders from the device.",
  ["filesystem.write"] = "Creates, modifies or deletes files.",
  ["shell.exec"]       = "Runs system shell commands.",
  ["love.filesystem"]  = "Accesses the app's data directory.",
}

local ICON_KIND = {
  ["filesystem.read"]  = "eye",
  ["filesystem.write"] = "pencil",
  ["shell.exec"]       = "terminal",
  ["love.filesystem"]  = "folder",
}

local function draw_perm_icon(kind, cx, cy, r, col, alpha)
  love.graphics.setColor(col[1], col[2], col[3], alpha or 1)
  love.graphics.setLineWidth(1.6)
  if kind == "eye" then
    love.graphics.ellipse("line", cx, cy, r, r * 0.55)
    love.graphics.circle("fill", cx, cy, r * 0.28)
  elseif kind == "pencil" then
    love.graphics.line(cx - r*0.55, cy + r*0.55, cx + r*0.55, cy - r*0.55)
    love.graphics.line(cx + r*0.55, cy - r*0.55, cx + r*0.75, cy - r*0.75)
    love.graphics.line(cx + r*0.75, cy - r*0.75, cx + r*0.65, cy - r*0.35)
  elseif kind == "terminal" then
    love.graphics.rectangle("line", cx - r*0.85, cy - r*0.7, r*1.7, r*1.4)
    love.graphics.line(cx - r*0.55, cy - r*0.3, cx - r*0.15, cy)
    love.graphics.line(cx - r*0.55, cy + r*0.3, cx - r*0.15, cy)
    love.graphics.line(cx + r*0.1, cy + r*0.3, cx + r*0.55, cy + r*0.3)
  elseif kind == "folder" then
    love.graphics.rectangle("line", cx - r*0.85, cy - r*0.4, r*1.7, r*1.05)
    love.graphics.rectangle("fill", cx - r*0.85, cy - r*0.7, r*0.65, r*0.35)
  else
    love.graphics.circle("line", cx, cy, r * 0.8)
  end
  love.graphics.setLineWidth(1)
end

local function ease_out(p) return 1 - (1 - p) ^ 3 end

function M.make(pkg, manifest, requested_perms, opts)
  opts = opts or {}
  local S = {}
  local W, H = 640, 480

  S.pkg       = pkg
  S.manifest  = manifest
  S.perms     = requested_perms or {}
  S.decisions = {}
  S.sel       = 1
  S.phase     = 0
  S.closing   = false
  S.close_t   = 0
  S.warn      = false
  S.warn_t    = 0
  S._next     = nil
  S.manage_only = opts.manage_only or false

  local function all_answered()
    for _, p in ipairs(S.perms) do
      if not S.decisions[p] then return false end
    end
    return true
  end

  local function apply_grants()
    local API = require("plugins.api")
    API.revoke(pkg)
    local granted = {}
    for _, p in ipairs(S.perms) do
      if S.decisions[p] == "granted" then granted[#granted + 1] = p end
    end
    if #granted > 0 then API.grant(pkg, granted) end
    API.mark_decided(pkg)
  end

  local function finish_and_open()
    apply_grants()
    require("plugins.loader").rescan()
    S._next = "open"
    S.closing = true
    S.close_t = 0
  end

  local function close_and_back()
    S._next = "back"
    S.closing = true
    S.close_t = 0
  end

  local function do_confirm()
    for _, p in ipairs(S.perms) do
      if S.decisions[p] == "denied" then
        S.warn = true
        S.warn_t = 0
        return
      end
    end
    finish_and_open()
  end

  function S.enter()
    S.phase = 0
    S.closing = false
    S.close_t = 0
    S.warn = false
    S.warn_t = 0
    S.sel = 1
    S.decisions = {}
    local API = require("plugins.api")
    local cur = API.granted(pkg) or {}
    local cur_set = {}
    for _, p in ipairs(cur) do cur_set[p] = true end
    for _, p in ipairs(S.perms) do
      if cur_set[p] then S.decisions[p] = "granted" end
    end
  end

  function S.leave() end

  function S.update(dt)
    if S.warn then S.warn_t = S.warn_t + dt end
    if S.closing then
      S.close_t = math.min(1, S.close_t + dt / 0.26)
      S.phase = 1 - S.close_t
      if S.close_t >= 1 then
        local nxt = S._next
        S._next = nil
        S.closing = false
        if nxt == "back" then
          State.back()
        elseif nxt == "open" then
          State.go((manifest and manifest.key) or pkg, { replace = true })
        end
      end
    else
      S.phase = math.min(1, S.phase + dt / 0.30)
    end
  end

  local function move(d)
    local total = #S.perms + 2
    S.sel = S.sel + d
    if S.sel < 1 then S.sel = total end
    if S.sel > total then S.sel = 1 end
  end

  function S.pad(b)
    if S.warn then
      if b == Input.A then S.warn = false; finish_and_open()
      elseif b == Input.B or b == Input.SELECT then S.warn = false end
      return
    end
    if S.closing then return end

    if b == Input.UP then move(-1)
    elseif b == Input.DOWN then move(1)
    elseif b == Input.Y then
      if S.sel >= 1 and S.sel <= #S.perms then
        S.decisions[S.perms[S.sel]] = "granted"
      end
    elseif b == Input.X then
      if S.sel >= 1 and S.sel <= #S.perms then
        S.decisions[S.perms[S.sel]] = "denied"
      end
    elseif b == Input.A then
      local total = #S.perms
      if S.sel >= 1 and S.sel <= total then
        -- QUICK GRANT ALL: A su una riga permesso concede tutto e conferma.
        for _, p in ipairs(S.perms) do
          S.decisions[p] = "granted"
        end
        do_confirm()
      elseif S.sel == total + 1 and all_answered() then
        do_confirm()
      elseif S.sel == total + 2 then
        close_and_back()
      end
    elseif b == Input.B or b == Input.SELECT then
      close_and_back()
    end
  end

  function S.hat(dir)
    if S.warn or S.closing then return end
    if dir == "up" then move(-1)
    elseif dir == "down" then move(1) end
  end

  function S.key(k)
    if S.warn then
      if k == "return" or k == "space" then S.pad(Input.A)
      elseif k == "escape" or k == "backspace" then S.pad(Input.B) end
      return
    end
    if     k == "up"    then move(-1)
    elseif k == "down"  then move(1)
    elseif k == "y"     then S.pad(Input.Y)
    elseif k == "x"     then S.pad(Input.X)
    elseif k == "return" or k == "space" then S.pad(Input.A)
    elseif k == "escape" or k == "backspace" then S.pad(Input.B) end
  end

  function S.draw()
    local th = State.theme
    local acc = manifest.colour or {0.94, 0.66, 0.35}
    local p = S.phase

    D.bg()

    love.graphics.setColor(acc[1], acc[2], acc[3], 0.06)
    for y = 0, H, 18 do
      for x = 0, W, 18 do
        love.graphics.rectangle("fill", x, y, 1, 1)
      end
    end
    D.corner_ticks(6, 6, W - 12, H - 12, 20, acc, 0.45 * p)

    local pw = W - 60
    local ph = H - 90
    local px = 30
    local py0 = 50
    local py = py0 + (1 - ease_out(p)) * 22

    D.glow(px + pw/2, py + ph/2, pw * 0.6, acc, 0.45 * p)

    love.graphics.setColor(0.014, 0.011, 0.020, 0.98 * p)
    love.graphics.rectangle("fill", px, py, pw, ph, 4, 4)
    love.graphics.setColor(acc[1], acc[2], acc[3], 0.95 * p)
    love.graphics.setLineWidth(1.6)
    love.graphics.rectangle("line", px + 0.5, py + 0.5, pw - 1, ph - 1, 4, 4)
    love.graphics.setLineWidth(1)
    love.graphics.setColor(acc[1], acc[2], acc[3], 0.30 * p)
    love.graphics.rectangle("line", px + 6.5, py + 6.5, pw - 13, ph - 13, 3, 3)
    D.corner_ticks(px + 10, py + 10, pw - 20, ph - 20, 18, acc, 0.95 * p)

    if p < 1 then
      local sy = py + ph * ease_out(p)
      love.graphics.setColor(acc[1], acc[2], acc[3], 0.6 * (1 - p))
      love.graphics.rectangle("fill", px + 8, sy - 1, pw - 16, 2)
    end

    if p < 0.35 then return end
    local ca = math.min(1, (p - 0.35) / 0.65)

    love.graphics.setFont(A.font(A.FONT_TITLE, 18))
    love.graphics.setColor(acc[1], acc[2], acc[3], ca)
    love.graphics.printf(manifest.name or pkg, px + 20, py + 16, pw - 40, "center")

    local t_y = py + 48
    local title = "PERMISSIONS REQUIRED"
    local f_t   = A.font(A.FONT_TITLE, 22)
    love.graphics.setFont(f_t)
    local t_w   = f_t:getWidth(title)
    local icon_r = 10
    local gap   = 14
    local total_w = t_w + (icon_r * 2 + gap) * 2
    local start_x = px + (pw - total_w) / 2
    local i_cy = t_y + f_t:getHeight() / 2

    local function draw_warn(cx, cy)
      love.graphics.setColor(acc[1], acc[2], acc[3], ca)
      love.graphics.setLineWidth(1.8)
      love.graphics.polygon("line",
        cx, cy - icon_r,
        cx + icon_r, cy + icon_r * 0.8,
        cx - icon_r, cy + icon_r * 0.8)
      love.graphics.line(cx, cy - icon_r * 0.4, cx, cy + icon_r * 0.3)
      love.graphics.circle("fill", cx, cy + icon_r * 0.55, 1)
      love.graphics.setLineWidth(1)
    end

    draw_warn(start_x + icon_r, i_cy)
    love.graphics.setColor(acc[1], acc[2], acc[3], ca)
    love.graphics.setFont(f_t)
    love.graphics.print(title, start_x + icon_r * 2 + gap, t_y)
    draw_warn(start_x + icon_r * 2 + gap + t_w + gap + icon_r, i_cy)

    love.graphics.setColor(acc[1], acc[2], acc[3], 0.35 * ca)
    love.graphics.rectangle("fill", px + 24, py + 82, pw - 48, 1)

    local row_h  = 50
    local list_x = px + 26
    local list_w = pw - 52
    local list_y = py + 92

    for i, perm in ipairs(S.perms) do
      local ry = list_y + (i - 1) * row_h
      if ry + row_h > py + ph - 56 then break end
      local focused = (S.sel == i)
      local dec = S.decisions[perm]

      if focused then
        love.graphics.setColor(acc[1], acc[2], acc[3], 0.15 * ca)
        love.graphics.rectangle("fill", list_x, ry, list_w, row_h - 4, 3, 3)
        love.graphics.setColor(acc[1], acc[2], acc[3], 0.92 * ca)
        love.graphics.setLineWidth(1.5)
        love.graphics.rectangle("line", list_x + 0.5, ry + 0.5, list_w - 1, row_h - 5, 3, 3)
        love.graphics.setLineWidth(1)
      else
        love.graphics.setColor(acc[1], acc[2], acc[3], 0.10 * ca)
        love.graphics.rectangle("fill", list_x, ry, list_w, row_h - 4, 3, 3)
      end

      draw_perm_icon(ICON_KIND[perm] or "folder",
        list_x + 22, ry + 14, 11, acc, ca)

      love.graphics.setFont(A.font(A.FONT_MONO, 12))
      love.graphics.setColor(th.text_bright, ca)
      love.graphics.print(perm, list_x + 44, ry + 6)

      love.graphics.setFont(A.font(A.FONT_BODY, 9))
      love.graphics.setColor(th.text_dim, ca * 0.92)
      love.graphics.print(EXPLAIN[perm] or "", list_x + 44, ry + 24)

      local cbx = list_x + list_w - 30
      local cby = ry + 14
      if dec == "granted" then
        love.graphics.setColor(0.35, 0.95, 0.45, ca)
        love.graphics.setLineWidth(2.4)
        love.graphics.line(cbx - 9, cby, cbx - 2, cby + 7, cbx + 10, cby - 8)
        love.graphics.setLineWidth(1)
      elseif dec == "denied" then
        love.graphics.setColor(0.95, 0.28, 0.22, ca)
        love.graphics.setLineWidth(2.4)
        love.graphics.line(cbx - 9, cby - 8, cbx + 10, cby + 8)
        love.graphics.line(cbx - 9, cby + 8, cbx + 10, cby - 8)
        love.graphics.setLineWidth(1)
      else
        love.graphics.setColor(0.5, 0.5, 0.55, ca * 0.7)
        love.graphics.setLineWidth(1.4)
        love.graphics.rectangle("line", cbx - 9, cby - 9, 19, 19, 2, 2)
        love.graphics.setLineWidth(1)
      end

      if focused then
        love.graphics.setFont(A.font(A.FONT_MONO, 8))
        love.graphics.setColor(th.text_dim, ca * 0.75)
        love.graphics.print("[Y] Grant   [X] Deny   [A] Grant all", list_x + 44, ry + 37)
      end
    end

    -- Legenda fissa
    love.graphics.setFont(A.font(A.FONT_MONO, 9))
    love.graphics.setColor(th.text_dim, 0.9 * ca)
    love.graphics.printf(
      "Y = Grant selected   X = Deny selected   A = Grant all & confirm   B = Back",
      px, py + ph - 64, pw, "center")

    local by = py + ph - 42
    local bh = 26
    local f_btn = A.font(A.FONT_BODY_BOLD, 12)

    local ok_x = px + 26
    local ok_w = 160
    local ce = all_answered()
    local focused_ok = (S.sel == #S.perms + 1)

    if ce then
      love.graphics.setColor(acc[1]*0.30, acc[2]*0.30, acc[3]*0.30, ca)
      love.graphics.rectangle("fill", ok_x, by, ok_w, bh, 3, 3)
      love.graphics.setColor(acc[1], acc[2], acc[3], ca)
      love.graphics.setLineWidth(focused_ok and 2.0 or 1.4)
      love.graphics.rectangle("line", ok_x + 0.5, by + 0.5, ok_w - 1, bh - 1, 3, 3)
      love.graphics.setLineWidth(1)
      love.graphics.setFont(f_btn)
      love.graphics.setColor(1, 1, 1, ca)
      love.graphics.printf("CONFIRM", ok_x, by + 6, ok_w, "center")
    else
      love.graphics.setColor(0.10, 0.10, 0.12, ca)
      love.graphics.rectangle("fill", ok_x, by, ok_w, bh, 3, 3)
      love.graphics.setColor(0.30, 0.30, 0.34, ca)
      love.graphics.rectangle("line", ok_x + 0.5, by + 0.5, ok_w - 1, bh - 1, 3, 3)
      love.graphics.setFont(f_btn)
      love.graphics.setColor(0.42, 0.42, 0.46, ca)
      love.graphics.printf("CONFIRM", ok_x, by + 6, ok_w, "center")
    end

    local bk_w = 160
    local bk_x = px + pw - 26 - bk_w
    local focused_bk = (S.sel == #S.perms + 2)
    love.graphics.setColor(0.10, 0.08, 0.10, ca)
    love.graphics.rectangle("fill", bk_x, by, bk_w, bh, 3, 3)
    love.graphics.setColor(0.80, 0.40, 0.35, ca)
    love.graphics.setLineWidth(focused_bk and 2.0 or 1.4)
    love.graphics.rectangle("line", bk_x + 0.5, by + 0.5, bk_w - 1, bh - 1, 3, 3)
    love.graphics.setLineWidth(1)
    love.graphics.setFont(f_btn)
    love.graphics.setColor(1, 0.88, 0.88, ca)
    love.graphics.printf("BACK", bk_x, by + 6, bk_w, "center")

    if S.warn then
      local wp = math.min(1, S.warn_t * 5)
      love.graphics.setColor(0, 0, 0, 0.75 * wp)
      love.graphics.rectangle("fill", 0, 0, W, H)

      local ww, wh = 440, 190
      local wx = (W - ww) / 2
      local wy = (H - wh) / 2 + (1 - wp) * 15
      local red = {0.95, 0.30, 0.25}

      D.glow(wx + ww/2, wy + wh/2, ww * 0.7, red, 0.6 * wp)
      love.graphics.setColor(0.030, 0.010, 0.010, 0.97 * wp)
      love.graphics.rectangle("fill", wx, wy, ww, wh, 4, 4)
      love.graphics.setColor(red[1], red[2], red[3], 0.95 * wp)
      love.graphics.setLineWidth(2)
      love.graphics.rectangle("line", wx + 0.5, wy + 0.5, ww - 1, wh - 1, 4, 4)
      love.graphics.setLineWidth(1)
      D.corner_ticks(wx + 8, wy + 8, ww - 16, wh - 16, 14, red, wp)

      love.graphics.setFont(A.font(A.FONT_TITLE, 16))
      love.graphics.setColor(red[1], red[2], red[3], wp)
      love.graphics.printf("WARNING", wx, wy + 18, ww, "center")

      love.graphics.setColor(red[1], red[2], red[3], 0.30 * wp)
      love.graphics.rectangle("fill", wx + 24, wy + 44, ww - 48, 1)

      RT.draw(
        "Some permissions were denied.\nThe plugin may not work correctly.\nProceed anyway?",
        wx + 20, wy + 58, ww - 40, "center", wp,
        { colour = State.theme.text, font_size = 12 })

      local btn_r = 10
      local f = A.font(A.FONT_BODY_BOLD, 12)
      love.graphics.setFont(f)
      local la = "PROCEED"
      local lb = "CANCEL"
      local wa = btn_r * 2 + 8 + f:getWidth(la)
      local wb = btn_r * 2 + 8 + f:getWidth(lb)
      local gap = 40
      local tot = wa + wb + gap
      local bx = wx + (ww - tot) / 2
      local byy = wy + wh - 40

      BI.draw(bx + btn_r, byy + btn_r, btn_r, "a")
      love.graphics.setColor(State.theme.text_bright, wp)
      love.graphics.print(la, bx + btn_r*2 + 8, byy + btn_r - 7)

      local bx2 = bx + wa + gap
      BI.draw(bx2 + btn_r, byy + btn_r, btn_r, "b")
      love.graphics.setColor(State.theme.text, wp)
      love.graphics.print(lb, bx2 + btn_r*2 + 8, byy + btn_r - 7)
    end

    D.scanlines(W, H, 0.06)
  end

  return S
end

return M
