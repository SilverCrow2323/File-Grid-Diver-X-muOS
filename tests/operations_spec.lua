-- tests/operations_spec.lua -- undo stack behavior.
local Ops = require("services.operations")

describe("services.operations", function()
  before_each(function()
    Ops.clear()
  end)

  it("starts empty after clear", function()
    assert.are.equal(0, Ops.size())
    assert.is_nil(Ops.peek())
  end)

  it("undo_last on empty returns false and an error message", function()
    local ok, err = Ops.undo_last()
    assert.is_false(ok)
    assert.is_string(err)
  end)

  it("push + undo is LIFO", function()
    local order = {}
    Ops.push({ kind = "a", undo = function() order[#order+1] = "a" end })
    Ops.push({ kind = "b", undo = function() order[#order+1] = "b" end })
    Ops.push({ kind = "c", undo = function() order[#order+1] = "c" end })
    Ops.undo_last()
    Ops.undo_last()
    Ops.undo_last()
    assert.are.same({ "c", "b", "a" }, order)
  end)

  it("stack is bounded at 50 entries", function()
    for _ = 1, 60 do
      Ops.push({ kind = "x", undo = function() end })
    end
    assert.are.equal(50, Ops.size())
  end)

  it("peek returns the top of the stack", function()
    Ops.push({ kind = "top", undo = function() end })
    local p = Ops.peek()
    assert.is_table(p)
    assert.are.equal("top", p.kind)
  end)

  it("errors inside undo are caught and reported", function()
    Ops.push({ kind = "bad", undo = function() error("boom") end })
    local ok, err = Ops.undo_last()
    assert.is_false(ok)
    assert.is_string(err)
    assert.matches("boom", err)
  end)

  it("rejects pushes without an undo function", function()
    Ops.push({ kind = "noop" })
    assert.are.equal(0, Ops.size())
  end)
end)
