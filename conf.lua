-- conf.lua -- File-GD X
function love.errhand(msg)
  local trace = debug.traceback(tostring(msg), 2)
  io.stderr:write("\n===== FGD ERROR =====\n" .. trace .. "\n===== END =====\n\n")
  io.stderr:flush()
  pcall(function()
    local f = io.open("data/fgd_error.log", "a")
    if f then
      f:write(os.date("%Y-%m-%d %H:%M:%S ") .. trace .. "\n\n")
      f:close()
    end
  end)
  return function()
    love.graphics.clear(0.02, 0.02, 0.02, 1)
    love.graphics.setColor(1, 0.4, 0.4, 1)
    love.graphics.print("FGD ERROR - see terminal / data/fgd_error.log", 20, 20)
    love.graphics.setColor(0.8, 0.8, 0.8, 1)
    love.graphics.printf(trace, 20, 50, 600)
    love.graphics.present()
    love.timer.sleep(0.1)
  end
end

function love.conf(t)
  t.identity          = "FileGDX"
  t.window.title      = "File-GD X"
  t.window.width      = 640
  t.window.height     = 480
  t.window.fullscreen = false
  t.window.vsync      = 1
  t.modules.physics   = false
  t.modules.joystick  = true
end
