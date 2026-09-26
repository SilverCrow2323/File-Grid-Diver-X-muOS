-- core/input_diag.lua -- prints the button map once, at startup.
local Input = require("core.input_map")
local M = {}

function M.print()
  local lines = {
    "[input] Schema B (SDL2 / LÖVE) mapping",
    "[input] 1=VOL-  2=VOL+  3=A  4=B  5=Y  6=X",
    "[input] 7=L1    8=R1    9=SELECT  10=START  11=MENU",
    "[input] 13=L2   14=R2   (D-pad via HAT)",
  }
  for _, l in ipairs(lines) do print(l) end
end

return M
