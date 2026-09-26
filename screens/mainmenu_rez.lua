-- mainmenu_rez.lua -- radial cyberpunk ring. 6 nodes in space.
-- Navigation: L/R rotates the ring. UP/DOWN jumps +-2. A activates.
local A     = require("core.assets")
local State = require("core.state")
local Input = require("core.input_map")
local Frame = require("ui.frame")
local D     = require("ui.draw")
local Modal = require("ui.modal")

local S = {}
local W, H = 640, 480
local RED = {0.95, 0.30, 0.25}
local function col(c, a) love.graphics.setColor(c[1], c[2], c[3], a or 1) end

-- 6 distinct nodes with own colour, icon-shape and target
local NODES = {
  { key = "XPLORER",  code = "01", target = "filex_home", colour = {0.94, 0.66, 0.35}, shape = "cube"   },
  { key = "PULSE",    code = "02", target = "device",     colour = {0.48, 0.80, 0.90}, shape = "sphere" },
  { key = "WIRED",    code = "03", target = "net_sphere", colour = {0.30, 0.85, 0.95}, shape = "tetra"  },
  { key = "STORE",    code = "04", target = "plugins",    colour = {0.70, 0.55, 0.92}, shape = "octa"   },
  { key = "TUNE",     code = "05", target = "settings",   colour = {0.55, 0.85, 0.45}, shape = "ring"   },
  { key = "EJECT",    code = "06", target = nil,          colour = {0.95, 0.30, 0.25}, shape = "cross"  },
}
local N = #NODES

local CX, CY = 200, 250
local RA, RB = 175, 65
local DIAG = -0.42

local sel, spin, target_spin = 1, 0, 0
local t = 0
local last_dt = 0.016

local CR, SR = math.cos(DIAG), math.sin(DIAG)

local function ring_pos(phase)
  local a = math.pi/2 + phase
  local ex = math.cos(a) * RA
  local ey = math.sin(a) * RB
  return CX + ex * CR - ey * SR, CY + ex * SR + ey * CR, math.sin(a)
end

function S.enter() sel = 1; spin = 0; target_spin = 0; t = 0 end
function S.leave() end

function S.update(dt)
  t = t + dt
  last_dt = dt
  spin = spin + (target_spin - spin) * math.min(1, dt * 4.5)
end

local function move(d)
  sel = sel + d
  if sel < 1 then sel = N end
  if sel > N then sel = 1 end
  target_spin = target_spin + d
  local ok, SFX = pcall(require, "core.audio")
  if ok and SFX.play then SFX.play("nav2") end
end

local function activate()
  local n = NODES[sel]
  if not n then return end
  local ok, SFX = pcall(require, "core.audio")
  if ok and SFX.play then SFX.play("enter") end
  if n.target then
    State.go(n.target)
  else
    Modal.show("Disconnect", "Quit File-GD X?",
      { accept_label = "QUIT", cancel_label = "STAY", accept_color = RED,
        on_accept = function() love.event.quit() end })
  end
end

function S.pad(b)
  if Modal.is_open() then
    if b == Input.A then Modal.accept() elseif b == Input.B then Modal.cancel() end
    return
  end
  if b == Input.RIGHT or b == Input.DOWN then move(1)
  elseif b == Input.LEFT or b == Input.UP then move(-1)
  elseif b == Input.A then activate()
  elseif b == Input.B or b == Input.SELECT then
    Modal.show("Disconnect", "Quit File-GD X?",
      { accept_label = "QUIT", cancel_label = "STAY", accept_color = RED,
        on_accept = function() love.event.quit() end })
  end
end

function S.hat(d)
  if Modal.is_open() then return end
  if d == "right" or d == "down" then move(1)
  elseif d == "left" or d == "up" then move(-1) end
end

function S.key(k)
  if Modal.is_open() then
    if k == "return" then Modal.accept() elseif k == "escape" then Modal.cancel() end
    return
  end
  if k == "right" or k == "down" then move(1)
  elseif k == "left" or k == "up" then move(-1)
  elseif k == "return" or k == "space" then activate()
  elseif k == "escape" then S.pad(Input.B) end
end

-- ── shapes ─────────────────────────────────────────────
local function wire_cube(cx, cy, r, c, a, rot)
  local base = {{-1,-1,-1},{1,-1,-1},{1,1,-1},{-1,1,-1},{-1,-1,1},{1,-1,1},{1,1,1},{-1,1,1}}
  local v = {}
  for i, s in ipairs(base) do
    local x2 = s[1]*math.cos(rot) - s[3]*math.sin(rot)
    local z2 = s[1]*math.sin(rot) + s[3]*math.cos(rot)
    local k = 1 / (1 + z2 * 0.0018)
    v[i] = { x2 * r * k, s[2] * r * k }
  end
  col(c, a); love.graphics.setLineWidth(2)
  for _, e in ipairs({{1,2},{2,3},{3,4},{4,1},{5,6},{6,7},{7,8},{8,5},{1,5},{2,6},{3,7},{4,8}}) do
    love.graphics.line(cx+v[e[1]][1], cy+v[e[1]][2], cx+v[e[2]][1], cy+v[e[2]][2])
  end
  love.graphics.setLineWidth(1)
end

local function wire_sphere(cx, cy, r, c, a, rot)
  col(c, a); love.graphics.setLineWidth(1.8)
  for i = -2, 2 do
    local rr = r * math.cos(i * 0.35)
    local yy = cy + math.sin(i * 0.35) * r
    love.graphics.ellipse("line", cx, yy, rr, rr * 0.25)
  end
  for i = 0, 3 do
    local ang = i * math.pi/4 + rot * 0.6
    love.graphics.ellipse("line", cx, cy, math.abs(math.sin(ang)) * r, r)
  end
  love.graphics.setLineWidth(1)
end

local function wire_tetra(cx, cy, r, c, a, rot)
  local base = {{0,-1,0},{1,0.5,0},{-0.5,0.5,0.866},{-0.5,0.5,-0.866}}
  local v = {}
  for i, s in ipairs(base) do
    local x2 = s[1]*math.cos(rot) - s[3]*math.sin(rot)
    local z2 = s[1]*math.sin(rot) + s[3]*math.cos(rot)
    local k = 1 / (1 + z2 * 0.0018)
    v[i] = { x2 * r * k, s[2] * r * k }
  end
  col(c, a); love.graphics.setLineWidth(2)
  for _, e in ipairs({{1,2},{1,3},{1,4},{2,3},{3,4},{4,2}}) do
    love.graphics.line(cx+v[e[1]][1], cy+v[e[1]][2], cx+v[e[2]][1], cy+v[e[2]][2])
  end
  love.graphics.setLineWidth(1)
end

local function wire_octa(cx, cy, r, c, a, rot)
  local base = {{0,-1,0},{1,0,0},{0,0,1},{-1,0,0},{0,0,-1},{0,1,0}}
  local v = {}
  for i, s in ipairs(base) do
    local x2 = s[1]*math.cos(rot) - s[3]*math.sin(rot)
    local z2 = s[1]*math.sin(rot) + s[3]*math.cos(rot)
    local k = 1 / (1 + z2 * 0.0018)
    v[i] = { x2 * r * k, s[2] * r * k }
  end
  col(c, a); love.graphics.setLineWidth(2)
  for _, e in ipairs({{1,2},{2,6},{6,4},{4,1},{1,3},{3,6},{6,5},{5,1},{3,2},{3,4},{5,2},{5,4}}) do
    love.graphics.line(cx+v[e[1]][1], cy+v[e[1]][2], cx+v[e[2]][1], cy+v[e[2]][2])
  end
  love.graphics.setLineWidth(1)
end

local function wire_ring(cx, cy, r, c, a, rot)
  col(c, a); love.graphics.setLineWidth(2)
  love.graphics.circle("line", cx, cy, r)
  love.graphics.setLineWidth(1)
  for i = 0, 7 do
    local ang = i * math.pi/4 + rot
    love.graphics.circle("fill", cx + math.cos(ang) * r, cy + math.sin(ang) * r, 2.5)
  end
end

local function wire_cross(cx, cy, r, c, a, rot)
  col(c, a); love.graphics.setLineWidth(2.6)
  love.graphics.line(cx-r, cy-r, cx+r, cy+r)
  love.graphics.line(cx-r, cy+r, cx+r, cy-r)
  love.graphics.setLineWidth(1.4)
  love.graphics.line(cx-r*0.6, cy, cx+r*0.6, cy)
  love.graphics.line(cx, cy-r*0.6, cx, cy+r*0.6)
  love.graphics.setLineWidth(1)
end

local SHAPES = {
  cube = wire_cube, sphere = wire_sphere, tetra = wire_tetra,
  octa = wire_octa, ring = wire_ring, cross = wire_cross,
}

function S.draw()
  D.bg()

  -- grid floor
  local th = State.theme
  col(th.grid_dim, 0.25)
  local hz = H * 0.55
  for i = -12, 12 do
    love.graphics.line(W/2 + i*60, hz, W/2 + i*20, H)
  end
  for i = 0, 12 do
    local p = (i + (t*0.3) % 1) / 12
    love.graphics.line(0, hz + (H-hz)*p, W, hz + (H-hz)*p)
  end

  -- stars
  for i = 1, 40 do
    local sx = (i * 137) % W
    local sy = (i * 89) % math.floor(hz)
    local a = 0.3 + 0.5 * math.abs(math.sin(t*2 + i))
    col({1,1,1}, a)
    love.graphics.rectangle("fill", sx, sy, 1, 1)
  end

  -- ring outline
  local pts = {}
  for i = 0, 72 do
    local a = (i/72) * math.pi * 2
    local ex = math.cos(a) * RA
    local ey = math.sin(a) * RB
    pts[#pts+1] = CX + ex*CR - ey*SR
    pts[#pts+1] = CY + ex*SR + ey*CR
  end
  col(th.grid_dim, 0.4); love.graphics.setLineWidth(1.4)
  love.graphics.line(pts); love.graphics.setLineWidth(1)

  -- nodes (depth sort)
  local vis = {}
  for i, n in ipairs(NODES) do
    local phase = (i - spin) * (2 * math.pi / N)
    local x, y, depth = ring_pos(phase)
    vis[#vis+1] = { n = n, i = i, x = x, y = y, depth = depth, foc = (i == sel) }
  end
  table.sort(vis, function(a,b)
    if a.foc then return false end
    if b.foc then return true end
    return a.depth < b.depth
  end)

  for _, d in ipairs(vis) do
    local r = d.foc and 32 or (14 + (d.depth + 1) * 8)
    local a = d.foc and 1 or (0.55 + (d.depth + 1) * 0.22)
    local rot = d.foc and (t * 1.5) or (t * 0.5)
    if d.foc then D.glow(d.x, d.y, r * 2.4, d.n.colour, 0.9) end
    local fn = SHAPES[d.n.shape] or wire_cube
    fn(d.x, d.y, r, d.n.colour, a, rot)

    love.graphics.setFont(A.font(A.FONT_MONO, d.foc and 11 or 9))
    local lw = love.graphics.getFont():getWidth(d.n.key)
    col({0,0,0}, 0.75)
    love.graphics.rectangle("fill", d.x - lw/2 - 4, d.y + r + 4, lw + 8, 14, 2, 2)
    col(d.n.colour, a)
    love.graphics.print(d.n.key, d.x - lw/2, d.y + r + 6)
  end

  -- reticle on focused node
  local phase = (sel - spin) * (2 * math.pi / N)
  local fx, fy = ring_pos(phase)
  local focus_node = NODES[sel]
  local br = 50
  for k, sp in ipairs({0.5, -0.8, 1.2}) do
    local rr = br + (k-1) * 12
    local rot = t * sp
    col(focus_node.colour, 0.55 - k*0.10)
    love.graphics.setLineWidth(1.2)
    for i = 0, 5 do
      local a1 = i * math.pi/3 + rot
      love.graphics.arc("line", "open", fx, fy, rr, a1, a1 + math.pi/8)
    end
  end
  love.graphics.setLineWidth(1)
  for i = 0, 3 do
    local a = i * math.pi/2 + t * 0.9
    love.graphics.setLineWidth(1.8)
    col(focus_node.colour, 0.9)
    love.graphics.line(fx + math.cos(a)*br, fy + math.sin(a)*br,
                       fx + math.cos(a)*(br+10), fy + math.sin(a)*(br+10))
  end
  love.graphics.setLineWidth(1)

  -- INFO PANEL
  local px, py, pw, ph = 400, 130, 220, 240
  col({0.020, 0.018, 0.026}, 0.95)
  love.graphics.rectangle("fill", px, py, pw, ph, 4, 4)
  col(focus_node.colour, 0.9); love.graphics.setLineWidth(1.6)
  love.graphics.rectangle("line", px + 0.5, py + 0.5, pw - 1, ph - 1, 4, 4)
  love.graphics.setLineWidth(1)
  D.corner_ticks(px + 6, py + 6, pw - 12, ph - 12, 10, focus_node.colour, 0.9)

  love.graphics.setFont(A.font(A.FONT_MONO, 11))
  col(focus_node.colour, 0.95)
  love.graphics.print(string.format("%02d / %02d", sel, N), px + 14, py + 12)
  love.graphics.setFont(A.font(A.FONT_BODY_BOLD, 9))
  col(State.theme.text_dim, 1)
  love.graphics.printf("FOCUSED NODE", 0, py + 12, px + pw - 14, "right")

  col(focus_node.colour, 0.35)
  love.graphics.rectangle("fill", px + 14, py + 30, pw - 28, 1)

  local icx, icy = px + pw/2, py + 72
  D.glow(icx, icy, 60, focus_node.colour, 0.55)
  local fn = SHAPES[focus_node.shape] or wire_cube
  fn(icx, icy, 30, focus_node.colour, 1, t * 1.2)

  love.graphics.setFont(A.font(A.FONT_TITLE, 18))
  col(focus_node.colour, 1)
  love.graphics.printf(focus_node.key, px, py + 120, pw, "center")

  love.graphics.setFont(A.font(A.FONT_MONO, 9))
  col(State.theme.text_dim, 1)
  local sub = focus_node.target and ("→ " .. focus_node.target)
              or "terminate session"
  love.graphics.printf(sub, px, py + 146, pw, "center")

  col(focus_node.colour, 0.35)
  love.graphics.rectangle("fill", px + 14, py + ph - 52, pw - 28, 1)

  -- hints
  love.graphics.setFont(A.font(A.FONT_BODY, 10))
  col(State.theme.text, 1)
  love.graphics.print("A ENTER", px + 30, py + ph - 36)
  love.graphics.print("B QUIT",  px + 130, py + ph - 36)

  Frame.draw_top("FGD", "mainmenu")
  Frame.draw_bottom({
    { key = "l/r", label = "Rotate" },
    { key = "a",   label = "Enter"  },
    { key = "l2",  label = "View"   },
    { key = "b",   label = "Quit"   },
  })
  Modal.draw()
  D.scanlines(W, H, 0.07)
  D.vignette(W, H, 0.62)
end

return S
