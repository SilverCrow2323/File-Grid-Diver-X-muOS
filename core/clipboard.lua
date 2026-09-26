-- core/clipboard.lua -- file clipboard for copy / cut / paste.
local M = {}
M.items = {}
M.mode  = nil   -- "copy" | "cut" | nil

function M.set(paths, mode)
  M.items = {}
  if paths then
    for i, p in ipairs(paths) do M.items[i] = p end
  end
  M.mode = (#M.items > 0) and mode or nil
end

function M.get()
  return M.items, M.mode
end

function M.has()
  return #M.items > 0
end

function M.clear()
  M.items = {}
  M.mode  = nil
end

return M
