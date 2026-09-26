-- screens/help.lua -- Key guide, updated for the current build.
-- Every section is shown with real button icons via ui.button_icons.
local A     = require("core.assets")
local State = require("core.state")
local Input = require("core.input_map")
local Frame = require("ui.frame")
local D     = require("ui.draw")
local BI    = require("ui.button_icons")

local S = {}
local W, H = 640, 480

local scroll = 0
local max_scroll = 0

-- ============================================================
--  Sections
-- ============================================================
local SECTIONS = {
  { title = "GLOBAL",
    rows = {
      { key="a",      label="Confirm / activate" },
      { key="b",      label="Cancel / back" },
      { key="x",      label="Quick actions (context menu)" },
      { key="y",      label="Extra (sort, log, etc.)" },
      { key="start",  label="SPDW panel in file manager" },
      { key="select", label="Back to main menu" },
      { key="m",      label="Toggle status overlay (downloads / system)" },
      { key="any",    label="Start+Select  or  Ctrl+Q  = quit app" },
    } },
  { title = "MAIN MENU",
    rows = {
      { key="up",     label="Previous item" },
      { key="down",   label="Next item" },
      { key="a",      label="Enter section" },
      { key="b",      label="Quit application" },
      { key="any",    label="Konami sequence unlocks GRID-DEV" },
    } },
  { title = "FILE EXPLORER  -  single pane",
    rows = {
      { key="dpad",   label="Navigate" },
      { key="a",      label="Open folder or file" },
      { key="b",      label="Go to parent folder" },
      { key="x",      label="Context menu (copy, rename, archive...)" },
      { key="y",      label="Cycle sort: name / size / date / type" },
      { key="l1",     label="Page up" },
      { key="r1",     label="Page down" },
      { key="l2",     label="Cycle view: list / grid / compact / details" },
      { key="r2",     label="Toggle preview pane" },
      { key="select", label="Mark / unmark item" },
      { key="start",  label="Open SPDW panel (pause menu)" },
    } },
  { title = "FILE EXPLORER  -  dual pane",
    rows = {
      { key="l1",     label="Switch to pane 1" },
      { key="r1",     label="Switch to pane 2" },
      { key="dpad",   label="Navigate in the active pane" },
      { key="a",      label="Open in the active pane" },
      { key="tab",    label="Switch pane (keyboard)" },
    } },
  { title = "SPDW PANEL",
    rows = {
      { key="up",     label="Move up" },
      { key="down",   label="Move down" },
      { key="left",   label="Jump to previous group" },
      { key="right",  label="Jump to next group" },
      { key="a",      label="Activate item" },
      { key="b",      label="Close panel" },
      { key="start",  label="Close panel" },
    } },
  { title = "EDITOR",
    rows = {
      { key="dpad",   label="Move cursor" },
      { key="a",      label="Insert text (opens on-screen keyboard)" },
      { key="b",      label="Exit (asks to save if dirty)" },
      { key="x",      label="Delete current line" },
      { key="y",      label="Save" },
      { key="start",  label="Save" },
      { key="l1",     label="Scroll up 20 lines" },
      { key="r1",     label="Scroll down 20 lines" },
      { key="select", label="Toggle line numbers" },
      { key="any",    label="L stick: rapid cursor move" },
      { key="any",    label="R stick: scroll text" },
    } },
  { title = "ON-SCREEN KEYBOARD",
    rows = {
      { key="dpad",   label="Navigate keys (or L stick)" },
      { key="a",      label="Type selected character" },
      { key="b",      label="Hide keyboard (buffer kept)" },
      { key="y",      label="Backspace" },
      { key="x",      label="Insert space" },
      { key="l1",     label="Move cursor left" },
      { key="r1",     label="Move cursor right" },
      { key="select", label="Cycle layout: abc / ABC / !@#" },
      { key="start",  label="Newline (multi-line mode)" },
    } },
  { title = "IMAGE VIEWER",
    rows = {
      { key="dpad",   label="Pan image" },
      { key="x",      label="Toggle fit / actual size" },
      { key="y",      label="Zoom in" },
      { key="l1",     label="Rotate left 90 degrees" },
      { key="r1",     label="Rotate right 90 degrees" },
      { key="l2",     label="Previous image in folder" },
      { key="r2",     label="Next image in folder" },
      { key="b",      label="Back" },
    } },
  { title = "SETTINGS",
    rows = {
      { key="up",     label="Move up" },
      { key="down",   label="Move down" },
      { key="left",   label="Decrease / previous value" },
      { key="right",  label="Increase / next value" },
      { key="a",      label="Toggle or cycle value" },
      { key="l1",     label="Jump to previous section" },
      { key="r1",     label="Jump to next section" },
      { key="b",      label="Back (asks to save if changed)" },
    } },
  { title = "ARCHIVE RT",
    rows = {
      { key="up",     label="Move through tree" },
      { key="down",   label="Move through tree" },
      { key="left",   label="Collapse folder / jump to parent" },
      { key="right",  label="Expand folder" },
      { key="a",      label="Mark / unmark file" },
      { key="x",      label="Extract marked files" },
      { key="tab",    label="Switch tree / actions panel" },
      { key="b",      label="Back" },
    } },
  { title = "GD-X LIBRARY",
    rows = {
      { key="l1",     label="Previous page" },
      { key="r1",     label="Next page" },
      { key="l2",     label="Zoom out" },
      { key="r2",     label="Zoom in" },
      { key="a",      label="Go to page (reader)" },
      { key="a",      label="Open item (browse mode)" },
      { key="up",     label="Scroll text (EPUB)" },
      { key="down",   label="Scroll text (EPUB)" },
      { key="b",      label="Back" },
    } },
  { title = "FGD-X PLUGINS",
    rows = {
      { key="up",     label="Move up" },
      { key="down",   label="Move down" },
      { key="a",      label="Download / install plugin" },
      { key="x",      label="Remove plugin / cancel download" },
      { key="y",      label="View install log" },
      { key="b",      label="Back" },
    } },
  { title = "MINORU'S STORE",
    rows = {
      { key="left",   label="Switch category" },
      { key="right",  label="Switch category" },
      { key="l1",     label="Switch category" },
      { key="r1",     label="Switch category" },
      { key="a",      label="Open selected category" },
      { key="b",      label="Back" },
    } },
  { title = "AUDIO / VIDEO PLAYER",
    rows = {
      { key="a",      label="Play with mpv (hardware decode)" },
      { key="b",      label="Stop and exit" },
    } },
  { title = "SYSTEM  (live cockpit)",
    rows = {
      { key="up",     label="Scroll up" },
      { key="down",   label="Scroll down" },
      { key="l1",     label="Fast scroll up" },
      { key="r1",     label="Fast scroll down" },
      { key="a",      label="Refresh slow sensors" },
      { key="x",      label="Save system snapshot" },
      { key="b",      label="Back" },
    } },
}

local function content_height()
  local n = 40
  for _, s in ipairs(SECTIONS) do
    n = n + 30 + #s.rows * 26 + 14
  end
  return n
end

-- ============================================================
--  Lifecycle
-- ============================================================
function S.enter()
  scroll = 0
end
function S.leave() end
function S.update(dt) end

function S.pad(b)
  if     b == Input.UP   then scroll = math.max(0, scroll - 24)
  elseif b == Input.DOWN then scroll = scroll + 24
  elseif b == Input.L1   then scroll = math.max(0, scroll - 140)
  elseif b == Input.R1   then scroll = scroll + 140
  elseif b == Input.B or b == Input.SELECT then State.back() end
end

function S.hat(dir)
  if     dir == "up"   then scroll = math.max(0, scroll - 24)
  elseif dir == "down" then scroll = scroll + 24 end
end

function S.key(k)
  if     k == "up"   then scroll = math.max(0, scroll - 24)
  elseif k == "down" then scroll = scroll + 24
  elseif k == "pageup"   then scroll = math.max(0, scroll - 140)
  elseif k == "pagedown" then scroll = scroll + 140
  elseif k == "escape" or k == "backspace" then State.back() end
end

-- ============================================================
--  Draw
-- ============================================================
function S.draw()
  local th = State.theme
  D.bg()

  col = function(c, a) love.graphics.setColor(c[1], c[2], c[3], a or 1) end
  col(th.grid_faint, 0.08)
  for gy = Frame.TOP_H, H - Frame.BOTTOM_H, 16 do
    for gx = 0, W, 16 do love.graphics.rectangle("fill", gx, gy, 1, 1) end
  end

  local vp_y = Frame.TOP_H + 4
  local vp_h = H - Frame.TOP_H - Frame.BOTTOM_H - 8

  local ch = content_height()
  max_scroll = math.max(0, ch - vp_h)
  if scroll > max_scroll then scroll = max_scroll end

  love.graphics.setScissor(0, vp_y, W, vp_h)

  local y = vp_y + 12 - scroll

  for _, sec in ipairs(SECTIONS) do
    -- Section header with accent bar
    col(th.amber_hi, 0.95)
    love.graphics.setFont(A.font(A.FONT_BODY_BOLD, 13))
    love.graphics.print(sec.title, 24, y)
    col(th.amber_lo, 0.55)
    love.graphics.rectangle("fill", 24, y + 20, W - 48, 1)
    y = y + 30

    -- Rows
    for _, r in ipairs(sec.rows) do
      -- Button icon
      BI.draw(50, y + 9, 11, r.key)

      -- Label
      col(th.text, 1)
      love.graphics.setFont(A.font(A.FONT_BODY, 12))
      local label_x = 76
      -- If the icon is a shoulder or a wide shape, give more room
      if r.key == "l1" or r.key == "r1" or r.key == "l2" or r.key == "r2" then
        label_x = 92
      elseif r.key == "start" or r.key == "select" then
        label_x = 86
      end
      love.graphics.print(r.label, label_x, y + 1)
      y = y + 26
    end
    y = y + 14
  end

  love.graphics.setScissor()

  -- Scrollbar
  if max_scroll > 0 then
    local track_h = vp_h - 8
    local thumb_h = math.max(24, track_h * (vp_h / ch))
    local thumb_y = vp_y + 4 + (track_h - thumb_h) * (scroll / max_scroll)
    col(th.amber_hi, 0.5)
    love.graphics.rectangle("fill", W - 6, thumb_y, 3, thumb_h, 1, 1)
  end

  Frame.draw_top("FGD", "help")
  Frame.draw_bottom({
    { key = "up",   label = "Scroll" },
    { key = "l1",   label = "Fast -" },
    { key = "r1",   label = "Fast +" },
    { key = "b",    label = "Back" },
  })
  D.scanlines(W, H, 0.06)
end

return S
