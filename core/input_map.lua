-- core/input_map.lua -- centralized input constants.
-- Raw button numbers verified on RG35XX H (muOS):
--   2=VOL-, 3=VOL+, 4=A, 5=B, 6=Y, 7=X,
--   8=L1, 9=R1, 10=SELECT, 11=START,
--   12=M1, 13=L3, 14=L2, 15=R2, 16=R3, 17=M2.
-- M1 and M2 both map to MENU (guide / status overlay).

local M = {}

M.raw_to_logical = {
  [2]  = "VOL_DOWN",
  [3]  = "VOL_UP",
  [4]  = "A",
  [5]  = "B",
  [6]  = "Y",
  [7]  = "X",
  [8]  = "L1",
  [9]  = "R1",
  [10] = "SELECT",
  [11] = "START",
  [12] = "MENU",
  [13] = "L3",
  [14] = "L2",
  [15] = "R2",
  [16] = "R3",
  [17] = "MENU",
}

M.logical_to_sdl = {
  A        = "a",
  B        = "b",
  X        = "x",
  Y        = "y",
  L1       = "leftshoulder",
  R1       = "rightshoulder",
  L2       = "lefttrigger",
  R2       = "righttrigger",
  L3       = "leftstick",
  R3       = "rightstick",
  SELECT   = "back",
  START    = "start",
  MENU     = "guide",
  UP       = "dpup",
  DOWN     = "dpdown",
  LEFT     = "dpleft",
  RIGHT    = "dpright",
  VOL_UP   = "volup",
  VOL_DOWN = "voldown",
}

M.sdl_to_logical = {}
for k, v in pairs(M.logical_to_sdl) do
  M.sdl_to_logical[v] = k
end

M.A      = "a"
M.B      = "b"
M.X      = "x"
M.Y      = "y"
M.L1     = "leftshoulder"
M.R1     = "rightshoulder"
M.L2     = "lefttrigger"
M.R2     = "righttrigger"
M.L3     = "leftstick"
M.R3     = "rightstick"
M.SELECT = "back"
M.START  = "start"
M.MENU   = "guide"
M.UP     = "dpup"
M.DOWN   = "dpdown"
M.LEFT   = "dpleft"
M.RIGHT  = "dpright"

return M
