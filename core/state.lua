local S = {}

S.theme_name = "gc"
S.theme      = nil
S.t_ui       = 0
S.cwd        = "/mnt/mmc"
S.entries    = {}
S.focus      = { x = 1, y = 1 }
S.page       = 1
S.raw_input  = false
S.capture_mode = false
S.dev_unlocked = false  -- session-only, re-locks on every launch
S.opts       = { core = "local", sort = "name" }

function S.root()
  return love.filesystem.getSource() or "."
end

function S.path(rel)
  return S.root() .. "/" .. rel
end

function S.frontend_path(rel)
  return S.root() .. "/" .. rel
end

function S.go(_) end
function S.back() end

return S
