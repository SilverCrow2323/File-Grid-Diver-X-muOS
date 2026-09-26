-- services/downloader.lua -- background download manager.
-- Uses curl (or wget) via /bin/sh, polls progress files.
local M = {}

local TMP = "/tmp"
local JOBS = {}
local next_id = 0

local function has(tool)
  local h = io.popen("command -v " .. tool .. " 2>/dev/null")
  if not h then return false end
  local out = h:read("*a") or ""
  h:close()
  return out ~= ""
end

local function pick_tool()
  if has("curl") then return "curl" end
  if has("wget") then return "wget" end
  return nil
end

function M.tool() return pick_tool() end

-- Start a download. Returns job_id or nil, error.
function M.start(url, filename, label)
  if not url or url == "" then return nil, "no url" end
  local tool = pick_tool()
  if not tool then return nil, "no curl or wget installed" end

  next_id = next_id + 1
  local id = string.format("dl_%d_%d", os.time(), next_id)

  -- Decide output path: save into data/downloads/
  os.execute("mkdir -p data/downloads")
  local out_name = filename
  if not out_name or out_name == "" then
    out_name = url:match("([^/]+)$") or ("download_" .. id)
  end
  local out = "data/downloads/" .. out_name

  local prog = TMP .. "/fgd_" .. id .. ".progress"
  local done = TMP .. "/fgd_" .. id .. ".done"
  local script = TMP .. "/fgd_" .. id .. ".sh"

  -- Probe total size (best effort)
  local total = 0
  if tool == "curl" then
    local h = io.popen("curl -sIL " .. require("core.sh").shq(url) .. " 2>/dev/null | " ..
      "grep -i content-length | tail -1 | tr -dc '0-9'")
    if h then
      total = tonumber(h:read("*a") or "0") or 0
      h:close()
    end
  end

  -- Write shell script
  local body = table.concat({
    "#!/bin/sh",
    "OUT='" .. out .. "'",
    "PROG='" .. prog .. "'",
    "DONE='" .. done .. "'",
    "TOTAL=" .. tostring(total),
    "rm -f \"$PROG\" \"$DONE\"",
    'if [ ! -f "$OUT" ]; then : > "$OUT"; fi',
    "",
    'if [ "' .. tool .. '" = "curl" ]; then',
    '  curl -L --fail --silent --show-error \\',
    '       -o "$OUT" "' .. url .. '" &',
    "  PID=$!",
    "else",
    '  wget -q -O "$OUT" "' .. url .. '" &',
    "  PID=$!",
    "fi",
    'while kill -0 $PID 2>/dev/null; do',
    '  SZ=$(wc -c < "$OUT" 2>/dev/null || echo 0)',
    '  echo "$SZ|$TOTAL" > "$PROG"',
    "  sleep 0.4",
    "done",
    "wait $PID",
    'RC=$?',
    'SZ=$(wc -c < "$OUT" 2>/dev/null || echo 0)',
    'echo "$RC|$SZ|$TOTAL" > "$DONE"',
    "",
  }, "\n")

  local f = io.open(script, "w")
  if not f then return nil, "cannot write script" end
  f:write(body); f:close()
  os.execute("chmod +x '" .. script .. "'")
  os.execute("setsid sh '" .. script .. "' </dev/null >/dev/null 2>&1 &")

  local job = {
    id = id, url = url, out = out, script = script,
    prog = prog, done = done, total = total,
    started = os.time(),
    label = label or out_name,
  }
  JOBS[id] = job
  return id, nil
end

-- Poll status. Returns a status table or nil.
-- status = { id, label, out, bytes, total, pct, done, rc, elapsed, speed }
function M.status(id)
  local j = JOBS[id]
  if not j then return nil end

  local bytes, total = 0, j.total or 0
  local pf = io.open(j.prog, "r")
  if pf then
    local line = pf:read("*l") or ""
    pf:close()
    local b, t = line:match("(%d+)|(%d+)")
    if b then bytes = tonumber(b) or 0 end
    if t and tonumber(t) and tonumber(t) > 0 then total = tonumber(t) end
  end

  local df = io.open(j.done, "r")
  if df then
    local line = df:read("*l") or ""
    df:close()
    local rc, sz = line:match("(%d+)|(%d+)")
    j.done_flag = true
    j.rc = tonumber(rc) or 0
    if sz then bytes = tonumber(sz) or bytes end
  end

  local elapsed = os.time() - j.started
  if elapsed < 1 then elapsed = 1 end
  local speed = bytes / elapsed

  return {
    id      = j.id,
    label   = j.label,
    out     = j.out,
    url     = j.url,
    bytes   = bytes,
    total   = total,
    pct     = (total > 0) and (bytes / total) or 0,
    done    = j.done_flag or false,
    rc      = j.rc,
    elapsed = elapsed,
    speed   = speed,
  }
end

function M.all()
  local out = {}
  for _, j in pairs(JOBS) do
    local s = M.status(j.id)
    if s then out[#out + 1] = s end
  end
  return out
end

function M.active_count()
  local n = 0
  for _, j in pairs(JOBS) do
    if not j.done_flag then n = n + 1 end
  end
  return n
end

function M.cancel(id)
  local j = JOBS[id]
  if not j then return false end
  os.execute("pkill -f 'fgd_" .. id .. "' 2>/dev/null")
  os.remove(j.script); os.remove(j.prog); os.remove(j.done)
  j.done_flag = true
  j.rc = -1
  return true
end

function M.dismiss(id)
  JOBS[id] = nil
end

function M.human(n)
  if not n or n <= 0 then return "0 B" end
  local u = {"B", "KB", "MB", "GB", "TB"}
  local i = 1
  while n >= 1024 and i < #u do n = n / 1024; i = i + 1 end
  if i == 1 then return string.format("%d %s", n, u[i]) end
  return string.format("%.1f %s", n, u[i])
end

return M
