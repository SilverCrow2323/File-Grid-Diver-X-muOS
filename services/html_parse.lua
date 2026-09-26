-- services/html_parse.lua -- minimal HTML/XML to block list.
-- Produces a list of blocks:
--   { kind = "h1"|"h2"|"h3"|"p"|"li"|"pre"|"img"|"br",
--     runs = { {text=, bold=, italic=, link=}, ... },
--     src = (for img) }
-- Ignores CSS/JS. Decodes basic HTML entities.
local M = {}

local function decode(s)
  if not s then return "" end
  s = s:gsub("&amp;", "&")
  s = s:gsub("&lt;", "<")
  s = s:gsub("&gt;", ">")
  s = s:gsub("&quot;", '"')
  s = s:gsub("&apos;", "'")
  s = s:gsub("&nbsp;", " ")
  s = s:gsub("&#(%d+);", function(n) return string.char(tonumber(n) % 256) end)
  s = s:gsub("&#x(%x+);", function(n) return string.char(tonumber(n, 16) % 256) end)
  return s
end

-- Very simple tokenizer: find <...> boundaries
local function tokenize(html)
  local toks = {}
  local i = 1
  while i <= #html do
    local lt = html:find("<", i, true)
    if not lt then
      toks[#toks+1] = { type = "text", value = html:sub(i) }
      break
    end
    if lt > i then
      toks[#toks+1] = { type = "text", value = html:sub(i, lt - 1) }
    end
    local gt = html:find(">", lt + 1, true)
    if not gt then break end
    local raw = html:sub(lt + 1, gt - 1)
    toks[#toks+1] = { type = "tag", value = raw }
    i = gt + 1
  end
  return toks
end

local function parse_tag(raw)
  if raw:sub(1, 1) == "/" then
    return { close = true, name = raw:sub(2):match("^%s*([%w%-]+)") }
  end
  local self_close = raw:sub(-1) == "/"
  if self_close then raw = raw:sub(1, -2) end
  local name, attrs_str = raw:match("^%s*([%w%-]+)%s*(.*)$")
  local attrs = {}
  if attrs_str then
    for k, _, v in attrs_str:gmatch('([%w%-]+)%s*=%s*("([^"]*)"|\'([^\']*)\')') do
      -- gmatch non gestisce 3 catture così, faccio un loop manuale
    end
    -- manual attribute parse
    for k, v in attrs_str:gmatch('([%w%-]+)%s*=%s*"([^"]*)"') do
      attrs[k:lower()] = decode(v)
    end
    for k, v in attrs_str:gmatch("([%w%-]+)%s*=%s*'([^']*)'") do
      attrs[k:lower()] = decode(v)
    end
  end
  return { close = false, self_close = self_close, name = (name or ""):lower(), attrs = attrs }
end

local BLOCK_TAGS = {
  p=true, div=true, br=true, hr=true,
  h1=true, h2=true, h3=true, h4=true, h5=true, h6=true,
  li=true, ul=true, ol=true, pre=true, blockquote=true,
  section=true, article=true, header=true, footer=true, nav=true,
  table=true, tr=true, td=true, th=true,
  img=true, figure=true, figcaption=true,
  title=true, meta=true, link=true, script=true, style=true,
}

local INLINE_TAGS = {
  b=true, strong=true, i=true, em=true, u=true, s=true, strike=true,
  span=true, a=true, code=true, sub=true, sup=true, small=true, big=true,
  label=true, mark=true, cite=true, q=true, tt=true, kbd=true, samp=true,
  var=true, abbr=true,
}

local function push_block(blocks, kind)
  blocks[#blocks+1] = { kind = kind, runs = {} }
  return blocks[#blocks]
end

local function push_run(block, text, bold, italic, link, code)
  if not text or text == "" then return end
  block.runs[#block.runs+1] = {
    text = text, bold = bold, italic = italic, link = link, code = code,
  }
end

function M.parse(html)
  local toks = tokenize(html)
  local blocks = {}
  local cur = push_block(blocks, "p")
  local bold, italic, link, code = false, false, nil, false
  local pre = false
  local pending_space = false

  local function flush()
    if #cur.runs == 0 then
      -- Empty paragraph: remove it if it's not intentional
      if #blocks > 0 and blocks[#blocks] == cur and cur.kind == "p" then
        table.remove(blocks)
      end
    end
    cur = nil
  end

  local function ensure_block(kind)
    if not cur then cur = push_block(blocks, kind) end
    return cur
  end

  local skip_tag = nil
  for _, t in ipairs(toks) do
    if skip_tag then
      if t.type == "tag" then
        local ctag = parse_tag(t.value)
        if ctag.close and ctag.name == skip_tag then
          skip_tag = nil
        end
      end
    elseif t.type == "text" then
      local text = decode(t.value)
      if pre then
        push_run(ensure_block("pre"), text, false, false, nil, true)
      else
        -- Collapse whitespace
        text = text:gsub("%s+", " ")
        if text ~= "" and text ~= " " then
          -- If we have a block and previous ended in space, avoid double
          local blk = ensure_block("p")
          push_run(blk, text, bold, italic, link, code)
        end
      end
    else
      local tag = parse_tag(t.value)
      local name = tag.name
      if tag.close then
        if name == "p" or name == "div" or name == "li"
           or name == "h1" or name == "h2" or name == "h3"
           or name == "h4" or name == "h5" or name == "h6"
           or name == "blockquote" or name == "pre"
           or name == "tr" then
          if cur then flush() end
          cur = nil
        elseif name == "b" or name == "strong" then bold = false
        elseif name == "i" or name == "em" then italic = false
        elseif name == "a" then link = nil
        elseif name == "code" then code = false
        elseif name == "pre" then pre = false end
      else
        if name == "p" or name == "div" or name == "section" or name == "article"
           or name == "header" or name == "footer" or name == "nav"
           or name == "blockquote" then
          if cur and #cur.runs > 0 then flush() end
          cur = nil
        elseif name == "h1" or name == "h2" or name == "h3"
            or name == "h4" or name == "h5" or name == "h6" then
          if cur then flush() end
          cur = push_block(blocks, name)
        elseif name == "br" then
          local blk = ensure_block("p")
          push_run(blk, "\n", false, false, nil, false)
        elseif name == "hr" then
          if cur then flush() end
          push_block(blocks, "hr")
          cur = nil
        elseif name == "li" then
          if cur then flush() end
          cur = push_block(blocks, "li")
        elseif name == "ul" or name == "ol" then
          if cur then flush() end
          cur = nil
        elseif name == "pre" then
          if cur then flush() end
          cur = push_block(blocks, "pre")
          pre = true
        elseif name == "img" then
          local src = tag.attrs and (tag.attrs.src or tag.attrs["data-src"])
          if src and cur then flush() end
          blocks[#blocks+1] = {
            kind = "img", runs = {}, src = src,
            alt = tag.attrs and tag.attrs.alt or "",
          }
          cur = nil
        elseif name == "br" then
          -- handled above
        elseif name == "b" or name == "strong" then bold = true
        elseif name == "i" or name == "em" then italic = true
        elseif name == "a" then link = tag.attrs and tag.attrs.href
        elseif name == "code" then code = true
        elseif name == "script" or name == "style" or name == "head" then
          skip_tag = name
        end
      end
    end
  end
  if cur then flush() end
  return blocks
end

-- Extract plain text from blocks (for indexing / previews)
function M.to_text(blocks)
  local out = {}
  for _, b in ipairs(blocks) do
    if b.kind == "img" then
      out[#out+1] = "[image: " .. (b.alt or "") .. "]"
    else
      local line = {}
      for _, r in ipairs(b.runs) do line[#line+1] = r.text end
      out[#out+1] = table.concat(line)
    end
  end
  return table.concat(out, "\n")
end

return M
