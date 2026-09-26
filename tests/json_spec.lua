-- tests/json_spec.lua -- pure-Lua and cjson round-trips.
local json = require("core.json")

describe("core.json", function()
  it("encodes strings with quotes", function()
    assert.are.equal('"hello"', json.encode("hello"))
  end)

  it("encodes integers", function()
    assert.are.equal(42, tonumber(json.encode(42)))
  end)

  it("encodes floats approximately", function()
    assert.near(3.14, tonumber(json.encode(3.14)), 0.001)
  end)

  it("encodes booleans", function()
    assert.are.equal("true", json.encode(true))
    assert.are.equal("false", json.encode(false))
  end)

  it("encodes nil as null", function()
    assert.are.equal("null", json.encode(nil))
  end)

  it("round-trips a flat object", function()
    local t = { a = 1, b = "two", c = true }
    local r = json.decode(json.encode(t))
    assert.are.equal(1, r.a)
    assert.are.equal("two", r.b)
    assert.are.equal(true, r.c)
  end)

  it("round-trips nested tables", function()
    local t = { a = { b = { c = 1 } }, list = { 1, 2, 3 } }
    local r = json.decode(json.encode(t))
    assert.are.equal(1, r.a.b.c)
    assert.are.equal(3, #r.list)
    assert.are.equal(1, r.list[1])
    assert.are.equal(3, r.list[3])
  end)

  it("decodes an empty object", function()
    local r = json.decode("{}")
    assert.is_table(r)
    assert.are.equal(0, #r)
  end)

  it("decodes an empty array", function()
    local r = json.decode("[]")
    assert.is_table(r)
    assert.are.equal(0, #r)
  end)

  it("round-trips escaped characters", function()
    local orig = 'quote:" backslash:\\ newline:\n tab:\t'
    local r = json.decode(json.encode(orig))
    assert.are.equal(orig, r)
  end)

  it("decodes a nested structure from a literal", function()
    local r = json.decode('{"a":{"b":[10,20,30]},"c":"x"}')
    assert.are.equal(20, r.a.b[2])
    assert.are.equal("x", r.c)
  end)
end)
