-- tests/settings_store_spec.lua -- defaults shape and set/get.
-- These tests intentionally do not call Store.save(), so the user's
-- data/fgd.json is never overwritten when tests are run locally.
local Store = require("core.settings_store")

describe("core.settings_store", function()
  it("defaults table has the expected sections", function()
    assert.is_table(Store.defaults)
    assert.is_table(Store.defaults.general)
    assert.is_table(Store.defaults.ui)
    assert.is_table(Store.defaults.sort)
    assert.is_table(Store.defaults.sound)
  end)

  it("set then get round-trips a value", function()
    Store.set("__test__", "k", 42)
    assert.are.equal(42, Store.get("__test__", "k"))
  end)

  it("set then get round-trips a string", function()
    Store.set("__test__", "s", "hello")
    assert.are.equal("hello", Store.get("__test__", "s"))
  end)

  it("get(section) returns the whole section", function()
    Store.set("__test__", "a", 1)
    Store.set("__test__", "b", 2)
    local s = Store.get("__test__")
    assert.is_table(s)
    assert.are.equal(1, s.a)
    assert.are.equal(2, s.b)
  end)

  it("get on an unknown section returns nil", function()
    assert.is_nil(Store.get("__does_not_exist__", "k"))
    assert.is_nil(Store.get("__does_not_exist__"))
  end)

  it("defaults include the current theme name", function()
    assert.is_string(Store.defaults.general.theme)
  end)

  it("ui defaults include font_scale as a number", function()
    assert.is_number(Store.defaults.ui.font_scale)
  end)
end)
