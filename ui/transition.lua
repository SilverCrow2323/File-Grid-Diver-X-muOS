-- ui/transition.lua -- global screen fade + input pulse.
-- Ogni cambio schermata: fade out (0.12s) -> switch -> fade in (0.14s).
-- Ogni pressione di navigazione: pulse visivo sottile sul bordo.
local LOG = _G.LOG or require("core.log")
local M = {
  active   = false,
  t        = 0,
  alpha    = 0,
  phase    = "idle",
  duration_out = 0.12,
  duration_in  = 0.14,
  queue    = {},
}

-- pulse separato (indipendente dalla transizione schermata)
local pulse = { t = 0, active = false, duration = 0.16 }

-- ============================================================
--  Screen transition (queue-based: nessun input perso)
-- ============================================================
function M.start(switch_fn, name, opts)
  if not switch_fn then return end
  M.queue[#M.queue + 1] = { fn = switch_fn, name = name, opts = opts }
  if not M.active then
    M.active = true
    M.phase  = "out"
    M.t      = 0
    M.alpha  = 0
  end
end

function M.update(dt)
  -- screen transition
  if M.active then
    M.t = M.t + dt
    if M.phase == "out" then
      M.alpha = math.min(1, M.t / M.duration_out)
      if M.t >= M.duration_out then
        local p = table.remove(M.queue, 1)
        if p and p.fn then
          local ok, err = pcall(p.fn, p.name, p.opts)
          if not ok then
            LOG.info("[transition] switch error: " .. tostring(err))
          end
        end
        if #M.queue > 0 then
          -- altri pending: continua a schermo nero, esegui il prossimo
          M.t = 0
          M.alpha = 1
        else
          M.phase = "in"
          M.t = 0
          M.alpha = 1
        end
      end
    else -- "in"
      M.alpha = 1 - math.min(1, M.t / M.duration_in)
      if M.t >= M.duration_in then
        M.active = false
        M.alpha  = 0
        M.phase  = "idle"
      end
    end
  end

  -- input pulse
  if pulse.active then
    pulse.t = pulse.t + dt
    if pulse.t >= pulse.duration then
      pulse.active = false
    end
  end
end

function M.draw()
  local W, H = love.graphics.getWidth(), love.graphics.getHeight()
  if M.active and M.alpha > 0.001 then
    love.graphics.setColor(0, 0, 0, M.alpha)
    love.graphics.rectangle("fill", 0, 0, W, H)
    love.graphics.setColor(1, 1, 1, 1)
  end
  if pulse.active then
    local p = 1 - pulse.t / pulse.duration
    p = p * p
    love.graphics.setColor(1, 1, 1, p * 0.10)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", 1, 1, W - 2, H - 2)
    love.graphics.setLineWidth(1)
    love.graphics.setColor(1, 1, 1, 1)
  end
end

function M.pulse()
  pulse.active = true
  pulse.t = 0
end

function M.is_active() return M.active end

return M
