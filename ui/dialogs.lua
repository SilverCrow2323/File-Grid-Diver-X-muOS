-- ui/dialogs.lua -- semantic wrappers around ui/modal.lua.
-- Provides: confirm, info, input, choice.
-- Same visual language (cyberpunk, glow, corner ticks).
local M = {}

function M.confirm(title, message, opts)
  opts = opts or {}
  local Modal = require("ui.modal")
  Modal.show(title, message, {
    accept_label = opts.accept_label or "SAVE",
    cancel_label = opts.cancel_label or "DISCARD",
    on_accept    = opts.on_accept,
    on_cancel    = opts.on_cancel,
    color        = opts.color,
    accept_color = opts.accept_color,
    cancel_color = opts.cancel_color,
  })
end

function M.info(title, message, opts)
  opts = opts or {}
  local Modal = require("ui.modal")
  Modal.show(title, message, {
    accept_label = opts.accept_label or "OK",
    hide_cancel  = true,
    color        = opts.color,
    on_accept    = opts.on_accept,
  })
end

-- Input dialog: uses the on-screen keyboard via a callback.
-- opts: { title, initial, on_accept, on_cancel, color }
function M.input(title, initial, opts)
  opts = opts or {}
  local KB = require("ui.keyboard")
  KB.open({
    title    = title,
    initial  = initial or "",
    multiline = opts.multiline or false,
    on_accept = opts.on_accept,
    on_cancel = opts.on_cancel,
  })
end

-- Choice dialog: a real selectable list.
-- opts: { title, options = { { label=, act=, colour= }, ... },
--         on_cancel, color }
function M.choice(title, options, opts)
  opts = opts or {}
  local CM = require("ui.context_menu")
  local items = {}
  for _, o in ipairs(options) do
    items[#items + 1] = {
      label = o.label or "?",
      act   = o.act,
    }
  end
  CM.open({
    title = title,
    items = items,
  })
end

return M
