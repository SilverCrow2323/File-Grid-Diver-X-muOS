local A = require("core.assets")
local D = require("ui.draw")

local N = { items = {} }
local TYPES = {
  info    = { tag = "INFO", col = {0.29, 0.62, 0.72} },
  success = { tag = "OK  ", col = {0.42, 0.60, 0.35} },
  warning = { tag = "WARN", col = {0.83, 0.54, 0.24} },
  error   = { tag = "ERR ", col = {0.66, 0.20, 0.16} },
}

local function play_kind_sfx(kind)
  local ok, SFX = pcall(require, "core.audio")
  if not ok then return end
  if kind == "success" then SFX.play("success")
  elseif kind == "error" or kind == "warning" then SFX.play("error")
  else SFX.play("beep") end
end

function N.show(kind, message, ttl)
  play_kind_sfx(kind)
  table.insert(N.items, {
    kind = kind or "info",
    message = message or "",
    t = 0,
    ttl = ttl or 2.8,
  })
end

function N.update(dt)
  for i = #N.items, 1, -1 do
    local it = N.items[i]
    it.t = it.t + dt
    if it.t > it.ttl then table.remove(N.items, i) end
  end
end

function N.draw(w, h)
  local ok, State = pcall(require, "core.state")
  local th = ok and State.theme or {
    text = {0.85, 0.82, 0.76},
    text_dim = {0.44, 0.42, 0.38},
    panel = {0.05, 0.05, 0.04},
  }
  local font_msg = A.font(A.FONT_BODY, 13)
  local font_tag = A.font(A.FONT_BODY_BOLD, 12)

  for i, it in ipairs(N.items) do
    local p = it.t / it.ttl
    local alpha = 1
    if p > 0.85 then alpha = (1 - p) / 0.15 end
    if p < 0.10 then alpha = p / 0.10 end
    alpha = math.max(0, math.min(1, alpha))

    local ty = TYPES[it.kind] or TYPES.info
    local c = ty.col

    -- Measure
    love.graphics.setFont(font_msg)
    local msg_w = font_msg:getWidth(it.message)
    love.graphics.setFont(font_tag)
    local tag_w = font_tag:getWidth(ty.tag)

    local pad = 8
    local w_ = math.min(w - 30, tag_w + 8 + msg_w + pad * 2)
    local h_ = 22
    local bx = w - w_ - 14
    local by = h - 92 - (i - 1) * (h_ + 4)

    -- Panel
    love.graphics.setColor(th.panel[1], th.panel[2], th.panel[3], 0.96 * alpha)
    love.graphics.rectangle("fill", bx, by, w_, h_)

    -- Left accent bar (colored)
    love.graphics.setColor(c[1], c[2], c[3], alpha)
    love.graphics.rectangle("fill", bx, by, 3, h_)

    -- Hairline border
    love.graphics.setColor(c[1], c[2], c[3], 0.35 * alpha)
    love.graphics.rectangle("line", bx + 0.5, by + 0.5, w_ - 1, h_ - 1)

    -- Tag
    love.graphics.setFont(font_tag)
    love.graphics.setColor(c[1], c[2], c[3], alpha)
    love.graphics.print(ty.tag, bx + 8, by + 6)

    -- Vertical divider
    love.graphics.setColor(c[1], c[2], c[3], 0.35 * alpha)
    love.graphics.line(bx + 8 + tag_w + 4, by + 4,
                       bx + 8 + tag_w + 4, by + h_ - 4)

    -- Message
    love.graphics.setFont(font_msg)
    love.graphics.setColor(th.text[1], th.text[2], th.text[3], alpha)
    love.graphics.print(it.message, bx + 8 + tag_w + 10, by + 6)
  end
end

return N
