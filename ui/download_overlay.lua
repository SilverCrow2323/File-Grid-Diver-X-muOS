-- ui/download_overlay.lua -- full-screen download status overlay.
local A     = require("core.assets")
local D     = require("ui.draw")

local M = { open_flag = false, t = 0 }

function M.toggle() M.open_flag = not M.open_flag; M.t = 0 end
function M.close()   M.open_flag = false end
function M.is_open() return M.open_flag end
function M.update(dt) if M.open_flag then M.t = M.t + dt end end

function M.draw()
  if not M.open_flag then return end
  local ok, State = pcall(require, "core.state")
  local th = ok and State.theme or {
    text = {0.85, 0.82, 0.76}, text_dim = {0.44, 0.42, 0.38},
    panel = {0.05, 0.05, 0.04}, amber_hi = {0.94, 0.66, 0.35},
  }

  local W = love.graphics.getWidth()
  local H = love.graphics.getHeight()

  love.graphics.setColor(0, 0, 0, 0.80)
  love.graphics.rectangle("fill", 0, 0, W, H)

  local pw, ph = 500, 340
  local px = (W - pw) / 2
  local py = (H - ph) / 2

  love.graphics.setColor(th.panel)
  love.graphics.rectangle("fill", px, py, pw, ph, 4, 4)
  love.graphics.setColor(0.30, 0.85, 0.40, 0.9)
  love.graphics.setLineWidth(2)
  love.graphics.rectangle("line", px + 0.5, py + 0.5, pw - 1, ph - 1, 4, 4)
  love.graphics.setLineWidth(1)

  D.corner_ticks(px + 8, py + 8, pw - 16, ph - 16, 12, {0.40, 0.95, 0.45}, 0.9)

  love.graphics.setFont(A.font(A.FONT_TITLE, 18))
  love.graphics.setColor(0.40, 0.95, 0.45, 1)
  love.graphics.print("DOWNLOAD STATUS", px + 20, py + 16)

  local ok2, DL = pcall(require, "services.downloader")
  if not ok2 then
    love.graphics.setColor(th.text_dim)
    love.graphics.setFont(A.font(A.FONT_BODY, 11))
    love.graphics.print("downloader not available", px + 20, py + 60)
    return
  end

  local jobs = DL.all()
  if #jobs == 0 then
    love.graphics.setColor(th.text_dim)
    love.graphics.setFont(A.font(A.FONT_BODY, 12))
    love.graphics.print("(no downloads in this session)", px + 20, py + 60)
  else
    local y = py + 60
    for i, j in ipairs(jobs) do
      if i > 6 then break end
      love.graphics.setFont(A.font(A.FONT_BODY_BOLD, 11))
      love.graphics.setColor(0.85, 1.0, 0.85, 1)
      love.graphics.print(j.label:sub(1, 48), px + 20, y)
      y = y + 16

      -- progress bar
      local bw, bh = pw - 40, 8
      love.graphics.setColor(0.05, 0.10, 0.05, 1)
      love.graphics.rectangle("fill", px + 20, y, bw, bh, 2, 2)
      local col = j.done and (j.rc == 0 and {0.40, 0.95, 0.45} or {0.95, 0.35, 0.30})
                  or {0.40, 0.85, 0.45}
      love.graphics.setColor(col[1], col[2], col[3], 1)
      local pct = j.pct > 0 and j.pct or (j.done and 1 or 0)
      love.graphics.rectangle("fill", px + 20, y, bw * pct, bh, 2, 2)
      love.graphics.setColor(col[1], col[2], col[3], 0.5)
      love.graphics.rectangle("line", px + 20.5, y + 0.5, bw - 1, bh - 1, 2, 2)
      y = y + 12

      love.graphics.setFont(A.font(A.FONT_MONO, 9))
      love.graphics.setColor(th.text_dim)
      local status
      if j.done then
        status = j.rc == 0 and "COMPLETE" or ("FAILED rc=" .. tostring(j.rc))
      else
        status = string.format("%s / %s   %s/s   %ds",
          DL.human(j.bytes), DL.human(j.total),
          DL.human(j.speed), j.elapsed)
      end
      love.graphics.print(status, px + 20, y)
      y = y + 20
      if y > py + ph - 30 then break end
    end
  end

  love.graphics.setFont(A.font(A.FONT_MONO, 10))
  love.graphics.setColor(th.text_dim)
  love.graphics.printf("[M] close    downloads continue in background",
    px, py + ph - 22, pw, "center")
end

return M
