-- plugins/archive_extender/main.lua
local A     = require("core.assets")
local State = require("core.state")
local Input = require("core.input_map")
local Frame = require("ui.frame")
local D     = require("ui.draw")
local Notify= require("ui.notify")

local S = {}
local W, H = 640, 480
local acc = {0.60, 0.50, 0.80}

function S.enter() end
function S.leave() end
function S.update(dt) end

function S.pad(b)
  if b == Input.B or b == Input.SELECT then State.back() end
  if b == Input.A then Notify.show("info", "Archive Extender is built-in, no download needed") end
end
function S.hat(d) end
function S.key(k)
  if k == "escape" or k == "backspace" then State.back() end
end

function S.draw()
  D.bg()
  love.graphics.setColor(acc[1], acc[2], acc[3], 1)
  love.graphics.setFont(A.font(A.FONT_TITLE, 22))
  love.graphics.printf("ARCHIVE EXTENDER", 0, 100, W, "center")

  love.graphics.setFont(A.font(A.FONT_BODY, 12))
  love.graphics.setColor(0.85, 0.85, 0.85, 1)
  love.graphics.printf(
    "This is a built-in extension.\n" ..
    "It unlocks RAR, CBR, CB7, CBT, ISO, IMG, TAR.ZST and TAR.LZ4\n" ..
    "using the 7z and unrar tools already present on muOS.\n\n" ..
    "No download required.",
    0, 160, W, "center")

  Frame.draw_top("FGD", "plugins")
  Frame.draw_bottom({ { key = "b", label = "Back" } })
  D.scanlines(W, H, 0.06)
end

return S
