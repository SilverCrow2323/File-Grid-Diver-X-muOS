-- screens/save_backup.lua -- Save Backup plugin.
-- Scans emulator save folders, backs them up to SD2/USB.
local A     = require("core.assets")
local State = require("core.state")
local Input = require("core.input_map")
local Frame = require("ui.frame")
local D     = require("ui.draw")
local Notify= require("ui.notify")
local Modal = require("ui.modal")
local PathSel = require("ui.path_selector")
local sh    = require("core.sh")

local S = {}
local W, H = 640, 480
local acc = {0.35, 0.90, 0.50}

local mode = "scan"    -- "scan" | "list" | "restore"
local sel = 1
local scroll = 0
local items = {}       -- { name, path, size, saves = N }
local dest = nil       -- { label, path }
local t_enter = 0

local custom_paths = {}

local SAVE_DIRS = {
  { label = "RetroArch saves",   path = "/run/muos/storage/save" },
  { label = "RetroArch states",  path = "/run/muos/storage/savefile" },
  { label = "RetroArch (alt)",   path = "/mnt/mmc/retroarch/saves" },
  { label = "RetroArch states",  path = "/mnt/mmc/retroarch/states" },
  { label = "Dolphin",           path = "/mnt/mmc/dolphin-emu/GC" },
  { label = "PPSSPP",            path = "/mnt/mmc/PPSSPP/PSP/SAVEDATA" },
  { label = "DraStic",           path = "/mnt/mmc/drastic/backup" },
  { label = "Pico-8",            path = "/mnt/mmc/pico-8/carts" },
  { label = "ScummVM",           path = "/mnt/mmc/scummvm/saves" },
  { label = "Flycast",           path = "/mnt/mmc/flycast" },
}

local DEST_DIRS = {
  { label = "SD2 (External)",   path = "/mnt/sdcard/Backups" },
  { label = "USB drive",        path = "/mnt/usb/Backups" },
  { label = "TMP (temporary)",  path = "/tmp/fgd_backup" },
}

local function col(c, a) love.graphics.setColor(c[1], c[2], c[3], a or 1) end

local function du_kb(path)
  local r = sh.read("du -sk " .. sh.shq(path) .. " 2>/dev/null | cut -f1")
  return (tonumber(r or "0") or 0) * 1024
end

local function count_files(path)
  local h = io.popen("find " .. sh.shq(path) .. " -type f 2>/dev/null | wc -l")
  if not h then return 0 end
  local n = tonumber(h:read("*a") or "0") or 0
  h:close()
  return n
end

local function scan_saves()
  items = {}
  local all = {}
  for _, d in ipairs(SAVE_DIRS) do all[#all+1] = d end
  for _, p in ipairs(custom_paths) do
    all[#all+1] = { label = "Custom: " .. p:match("([^/]+)$"), path = p }
  end
  for _, d in ipairs(all) do
    if sh.is_dir(d.path) then
      local files = count_files(d.path)
      if files > 0 then
        items[#items + 1] = {
          name = d.label,
          path = d.path,
          size = du_kb(d.path),
          files = files,
        }
      end
    end
  end
  table.sort(items, function(a, b) return a.name < b.name end)
end

local function pick_dest()
  for _, d in ipairs(DEST_DIRS) do
    if sh.is_dir(d.path) or sh.exec("mkdir -p " .. sh.shq(d.path)) == 0 then
      return d
    end
  end
  return DEST_DIRS[3]
end

local function do_backup()
  if #items == 0 then
    Notify.show("warning", "nothing to backup")
    return
  end
  local dst = pick_dest()
  local ts = os.date("%Y%m%d_%H%M%S")
  local target = dst.path .. "/" .. ts
  sh.exec("mkdir -p " .. sh.shq(target))
  local ok_n = 0
  local manifest = io.open(target .. "/manifest.txt", "w")
  for _, it in ipairs(items) do
    local sanitized = it.name:gsub("[^%w]", "_")
    local sub = target .. "/" .. sanitized
    if sh.exec("cp -a " .. sh.shq(it.path) .. " " .. sh.shq(sub)) == 0 then
      ok_n = ok_n + 1
      if manifest then
        manifest:write(sanitized .. "|" .. it.path .. "\n")
      end
    end
  end
  if manifest then manifest:close() end
  Notify.show("success", ok_n .. " folders backed up to " .. dst.label)
end

local function do_restore(snapshot_path)
  local manifest_path = snapshot_path .. "/manifest.txt"
  local f = io.open(manifest_path, "r")
  if not f then
    Notify.show("error", "manifest not found in snapshot")
    return
  end
  local n = 0
  for line in f:lines() do
    local sanitized, original = line:match("^([^|]+)|(.+)$")
    if sanitized and original then
      local sub = snapshot_path .. "/" .. sanitized
      if sh.is_dir(sub) then
        sh.exec("mkdir -p " .. sh.shq(original))
        local cmd = "cp -a " .. sh.shq(sub) .. "/. " .. sh.shq(original) .. "/"
        if sh.exec(cmd) == 0 then n = n + 1 end
      end
    end
  end
  f:close()
  Notify.show("success", n .. " folders restored")
end

local function do_restore_list()
  local dst = pick_dest()
  items = {}
  local h = io.popen("ls -1d " .. sh.shq(dst.path) .. "/*/ 2>/dev/null | sort -r | head -20")
  if h then
    for line in h:lines() do
      local name = line:match("([^/]+)/$")
      if name then
        items[#items + 1] = {
          name = name,
          path = line:gsub("/$", ""),
          size = du_kb(line:gsub("/$", "")),
          files = count_files(line:gsub("/$", "")),
          is_snapshot = true,
        }
      end
    end
    h:close()
  end
  mode = "restore"
  sel = 1
  scroll = 0
end

function S.enter()
  t_enter = 0
  mode = "scan"
  sel = 1
  scroll = 0
  scan_saves()
end
function S.leave() end
function S.update(dt) t_enter = t_enter + dt end

function S.pad(b)
  if Modal.is_open() then
    if b == Input.A then Modal.accept()
    elseif b == Input.B then Modal.cancel() end
    return
  end
  if #items == 0 then
    PathSel.pad(b, {
      paths = (function()
        local ps = {}
        for _, d in ipairs(SAVE_DIRS) do ps[#ps+1] = d.path end
        for _, p in ipairs(custom_paths) do ps[#ps+1] = p end
        return ps
      end)(),
      on_rescan = function() scan_saves() end,
      on_pick = function(p)
        table.insert(custom_paths, 1, p)
        scan_saves()
        Notify.show("info", "custom path added")
      end,
      on_back = function() State.back() end,
    })
    return
  end
  if mode == "scan" then
    if b == Input.A then
      Modal.show("Backup saves",
        #items .. " folders found.\nBack them up to SD2 or USB?",
        { accept_label = "BACKUP", cancel_label = "CANCEL",
          accept_color = acc, on_accept = do_backup })
    elseif b == Input.X then
      do_restore_list()
    elseif b == Input.Y then scan_saves(); Notify.show("info", "rescan done")
    elseif b == Input.B or b == Input.SELECT then State.back() end
  elseif mode == "restore" then
    if     b == Input.UP   then sel = math.max(1, sel - 1)
    elseif b == Input.DOWN then sel = math.min(#items, sel + 1)
    elseif b == Input.A then
      local it = items[sel]
      if it then
        Modal.show("Restore " .. it.name,
          "Copy this backup back to all save folders?",
          { accept_label = "RESTORE", cancel_label = "CANCEL",
            accept_color = acc,
            on_accept = function()
              do_restore(it.path)
            end })
      end
    elseif b == Input.B or b == Input.SELECT then mode = "scan"; scan_saves() end
  end
end

function S.hat(dir)
  if mode == "restore" then
    if     dir == "up"   then sel = math.max(1, sel - 1)
    elseif dir == "down" then sel = math.min(#items, sel + 1) end
  end
end

function S.key(k)
  if     k == "escape" or k == "backspace" then S.pad(Input.B)
  elseif k == "up"    then S.pad(Input.UP)
  elseif k == "down"  then S.pad(Input.DOWN)
  elseif k == "x"     then S.pad(Input.X)
  elseif k == "y"     then S.pad(Input.Y)
  elseif k == "return" or k == "space" then S.pad(Input.A) end
end

function S.draw()
  local th = State.theme
  D.bg()
  col(acc, 0.06)
  for gy = Frame.TOP_H, H - Frame.BOTTOM_H, 18 do
    for gx = 0, W, 18 do love.graphics.rectangle("fill", gx, gy, 1, 1) end
  end

  love.graphics.setFont(A.font(A.FONT_TITLE, 20))
  col(acc, 1)
  love.graphics.printf("SAVE BACKUP", 0, Frame.TOP_H + 8, W, "center")

  love.graphics.setFont(A.font(A.FONT_MONO, 10))
  col(acc, 0.75)
  local sub
  if mode == "scan" then sub = #items .. " save folders detected"
  else sub = "restore from snapshot" end
  love.graphics.printf(sub, 0, Frame.TOP_H + 34, W, "center")

  local vp_y = Frame.TOP_H + 54
  local vp_h = H - Frame.BOTTOM_H - vp_y - 4
  local row_h = 48

  if #items == 0 then
    local paths = {}
    for _, d in ipairs(SAVE_DIRS) do paths[#paths+1] = d.path end
    for _, p in ipairs(custom_paths) do paths[#paths+1] = p end
    PathSel.draw({
      title = "SAVE BACKUP",
      message = "No save folders found.\n\nBackup scans the save directories of emulators " ..
                "installed on your device: RetroArch, Dolphin, PPSSPP, DraStic and more.\n\n" ..
                "Press X to rescan.\nPress Y to add a custom path.\nPress B to go back.",
      paths = paths,
      accent = acc,
      on_rescan = function() scan_saves() end,
      on_pick = function(p)
        table.insert(custom_paths, 1, p)
        scan_saves()
        Notify.show("info", "custom path added")
      end,
      on_back = function() State.back() end,
    })
    return
  end

  local total_h = #items * row_h
  local max_scroll = math.max(0, total_h - vp_h)
  local st_top = (sel - 1) * row_h
  if st_top < scroll then scroll = st_top end
  if st_top + row_h > scroll + vp_h then scroll = st_top + row_h - vp_h end
  scroll = math.max(0, math.min(max_scroll, scroll))

  love.graphics.setScissor(0, vp_y, W, vp_h)
  for i, it in ipairs(items) do
    local ry = vp_y + (i - 1) * row_h - scroll
    if ry + row_h > vp_y and ry < vp_y + vp_h then
      local focused = (i == sel)
      if focused then
        col(acc, 0.18)
        love.graphics.rectangle("fill", 20, ry + 2, W - 40, row_h - 6, 4, 4)
        col(acc, 0.9)
        love.graphics.setLineWidth(1.5)
        love.graphics.rectangle("line", 20.5, ry + 2.5, W - 41, row_h - 7, 4, 4)
        love.graphics.setLineWidth(1)
      end
      love.graphics.setFont(A.font(A.FONT_BODY_BOLD, 12))
      col(focused and {1,1,1} or th.text, 1)
      love.graphics.print(it.name, 34, ry + 8)
      love.graphics.setFont(A.font(A.FONT_MONO, 9))
      col(th.text_dim, 0.85)
      love.graphics.print(it.path, 34, ry + 24)
      col(acc, 0.85)
      love.graphics.printf(it.files .. " files  ·  " ..
        string.format("%.1f MB", (it.size or 0) / 1048576),
        0, ry + 16, W - 34, "right")
    end
  end
  love.graphics.setScissor()

  Frame.draw_top("FGD", "plugins")
  if mode == "scan" then
    Frame.draw_bottom({
      { key = "a", label = "Backup" },
      { key = "x", label = "Restore" },
      { key = "y", label = "Rescan" },
      { key = "b", label = "Back" },
    })
  else
    Frame.draw_bottom({
      { key = "up", label = "Move" },
      { key = "a", label = "Restore" },
      { key = "b", label = "Back" },
    })
  end
  Modal.draw()
  D.scanlines(W, H, 0.06)
end

return S
