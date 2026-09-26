-- services/operations.lua -- undo stack for destructive actions.
-- Every mutating operation on the filesystem pushes an entry onto a
-- bounded stack (LIFO). "Undo" pops and inverts.
--
-- Stack entries look like:
--   { kind = "rename", label = "rename foo.txt",
--     undo = function() ... end }
--
-- Operations that touch multiple files (batch rename, paste) still
-- count as ONE entry, so one Undo reverses the whole thing.

local sh = require("core.sh")

local M = {}
local STACK = {}
local MAX = 50

local function log(msg)
  local f = io.open("data/fgd_runtime.log", "a")
  if f then
    f:write(os.date("%Y-%m-%d %H:%M:%S ") .. "[ops] " .. msg .. "\n")
    f:close()
  end
end

function M.push(op)
  if not op or type(op.undo) ~= "function" then return end
  STACK[#STACK + 1] = op
  if #STACK > MAX then table.remove(STACK, 1) end
  log("push " .. (op.label or op.kind or "?"))
end

function M.undo_last()
  local op = table.remove(STACK)
  if not op then return false, "nothing to undo" end
  local ok, err = pcall(op.undo)
  if not ok then
    log("undo FAILED: " .. tostring(err))
    return false, tostring(err)
  end
  log("undo " .. (op.label or op.kind or "?"))
  return true, op.label or op.kind or "?"
end

function M.peek()   return STACK[#STACK] end
function M.size()   return #STACK end
function M.clear()  STACK = {} end

-- ============================================================
--  Factories
-- ============================================================
function M.rename(from, to)
  M.push({
    kind = "rename",
    label = "rename " .. ((from or "?"):match("([^/]+)$") or "?"),
    undo = function()
      sh.exec("mv " .. sh.shq(to) .. " " .. sh.shq(from))
    end,
  })
end

function M.move_batch(pairs)
  if #pairs == 0 then return end
  M.push({
    kind = "move_batch",
    label = "move " .. #pairs .. " file(s)",
    undo = function()
      -- Reverse order in case paths nest
      for i = #pairs, 1, -1 do
        local p = pairs[i]
        sh.exec("mv " .. sh.shq(p.to) .. " " .. sh.shq(p.from))
      end
    end,
  })
end

function M.copy_batch(dsts)
  if #dsts == 0 then return end
  M.push({
    kind = "copy_batch",
    label = "copy " .. #dsts .. " file(s)",
    undo = function()
      for _, d in ipairs(dsts) do
        sh.exec("rm -rf " .. sh.shq(d))
      end
    end,
  })
end

function M.trash(orig, stored)
  M.push({
    kind = "trash",
    label = "trash " .. ((orig or "?"):match("([^/]+)$") or "?"),
    undo = function()
      local Trash = require("services.trash")
      return Trash.restore_by_stored(stored)
    end,
  })
end

function M.mkdir(path)
  M.push({
    kind = "mkdir",
    label = "mkdir " .. ((path or "?"):match("([^/]+)$") or "?"),
    undo = function()
      sh.exec("rm -rf " .. sh.shq(path))
    end,
  })
end

function M.touch(path)
  M.push({
    kind = "touch",
    label = "create " .. ((path or "?"):match("([^/]+)$") or "?"),
    undo = function()
      sh.exec("rm -f " .. sh.shq(path))
    end,
  })
end

function M.batch_rename(renames)
  if #renames == 0 then return end
  M.push({
    kind = "batch_rename",
    label = "batch rename " .. #renames .. " file(s)",
    undo = function()
      for i = #renames, 1, -1 do
        local r = renames[i]
        sh.exec("mv " .. sh.shq(r.to) .. " " .. sh.shq(r.from))
      end
    end,
  })
end

return M
