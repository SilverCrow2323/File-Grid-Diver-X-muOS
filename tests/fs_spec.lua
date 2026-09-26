-- tests/fs_spec.lua -- pure helpers from services/fs.lua.
local FS = require("services.fs")

describe("services.fs.ext_of", function()
  it("returns lowercased extension", function()
    assert.are.equal("txt",  FS.ext_of("file.txt"))
    assert.are.equal("lua",  FS.ext_of("script.lua"))
    assert.are.equal("jpg",  FS.ext_of("photo.JPG"))
  end)

  it("uses the last dot for multi-dot names", function()
    assert.are.equal("gz", FS.ext_of("archive.tar.gz"))
  end)

  it("returns empty for names without extension", function()
    assert.are.equal("", FS.ext_of("README"))
    assert.are.equal("", FS.ext_of("noext"))
  end)
end)

describe("services.fs.human_size", function()
  it("handles zero and negatives", function()
    assert.are.equal("0 B", FS.human_size(0))
    assert.are.equal("0 B", FS.human_size(-1))
    assert.are.equal("0 B", FS.human_size(nil))
  end)

  it("uses B for <1KB", function()
    assert.are.equal("100 B", FS.human_size(100))
  end)

  it("uses KB for 1KB..1MB", function()
    assert.are.equal("1.0 KB", FS.human_size(1024))
    assert.are.equal("1.5 KB", FS.human_size(1536))
  end)

  it("uses MB for 1MB..1GB", function()
    assert.are.equal("1.0 MB", FS.human_size(1024 * 1024))
  end)

  it("uses GB above that", function()
    assert.are.equal("2.00 GB", FS.human_size(2 * 1024 * 1024 * 1024))
  end)
end)

describe("services.fs.classify", function()
  it("recognises directories", function()
    assert.are.equal("dir", FS.classify({ is_dir = true, name = "x" }))
  end)

  it("recognises images", function()
    assert.are.equal("image", FS.classify({ name = "a.png" }))
    assert.are.equal("image", FS.classify({ name = "a.JPG" }))
    assert.are.equal("image", FS.classify({ name = "a.webp" }))
  end)

  it("recognises audio", function()
    assert.are.equal("audio", FS.classify({ name = "a.mp3" }))
    assert.are.equal("audio", FS.classify({ name = "a.ogg" }))
  end)

  it("recognises video", function()
    assert.are.equal("video", FS.classify({ name = "a.mp4" }))
  end)

  it("recognises text/code", function()
    assert.are.equal("text", FS.classify({ name = "a.txt" }))
    assert.are.equal("text", FS.classify({ name = "a.lua" }))
  end)

  it("recognises archives", function()
    assert.are.equal("archive", FS.classify({ name = "a.zip" }))
    assert.are.equal("archive", FS.classify({ name = "a.muxapp" }))
  end)

  it("recognises ROMs", function()
    assert.are.equal("rom", FS.classify({ name = "game.iso" }))
    assert.are.equal("rom", FS.classify({ name = "game.nes" }))
  end)

  it("falls back to unknown", function()
    assert.are.equal("unknown", FS.classify({ name = "something.xyz" }))
  end)
end)

describe("services.fs.sort", function()
  it("sorts by name alphabetically", function()
    local e = { {name="c"}, {name="a"}, {name="b"} }
    FS.sort(e, "name", false)
    assert.are.equal("a", e[1].name)
    assert.are.equal("b", e[2].name)
    assert.are.equal("c", e[3].name)
  end)

  it("sorts by size descending", function()
    local e = { {name="a", size=10}, {name="b", size=100}, {name="c", size=50} }
    FS.sort(e, "size", false)
    assert.are.equal(100, e[1].size)
    assert.are.equal(50,  e[2].size)
    assert.are.equal(10,  e[3].size)
  end)

  it("puts directories first when requested", function()
    local e = {
      { name = "file", size = 10 },
      { name = "dir",  is_dir = true, size = 0 },
    }
    FS.sort(e, "name", true)
    assert.is_true(e[1].is_dir)
    assert.are.equal("file", e[2].name)
  end)
end)

describe("services.fs.filter", function()
  local entries = {
    { name = "a.png",  is_dir = false },
    { name = "b.txt",  is_dir = false },
    { name = "folder", is_dir = true },
  }

  it("'all' returns everything", function()
    assert.are.equal(3, #FS.filter(entries, "all"))
  end)

  it("'dirs' returns only directories", function()
    local r = FS.filter(entries, "dirs")
    assert.are.equal(1, #r)
    assert.is_true(r[1].is_dir)
  end)

  it("'files' returns only files", function()
    local r = FS.filter(entries, "files")
    assert.are.equal(2, #r)
  end)

  it("'image' returns only images", function()
    local r = FS.filter(entries, "image")
    assert.are.equal(1, #r)
    assert.are.equal("a.png", r[1].name)
  end)
end)
