#!/usr/bin/env bash
# tools/check_syntax.sh - compile every Lua file with luac (or luajit).
#
# Usage:
#   ./tools/check_syntax.sh
#
# Exit code 0 = all files compile. Otherwise, list of failing files
# is printed and exit code is 1.

set -u
cd "$(dirname "$0")/.."

if command -v luac >/dev/null 2>&1; then
  CHECK="luac -p"
elif command -v luajit >/dev/null 2>&1; then
  CHECK="luajit -bl"
else
  echo "ERROR: neither luac nor luajit is installed."
  echo "  Debian/Ubuntu: sudo apt install lua5.1"
  echo "  Arch:          sudo pacman -S lua"
  exit 2
fi

FAIL=0
TOTAL=0
SKIP_DIRS=(.local_bak releases pdf_lib vendor lib .git)

should_skip() {
  local path="$1"
  for d in "${SKIP_DIRS[@]}"; do
    [[ "$path" == *"/$d/"* ]] && return 0
    [[ "$path" == *"/$d/"* ]] && return 0
  done
  return 1
}

while IFS= read -r -d '' f; do
  should_skip "$f" && continue
  TOTAL=$((TOTAL+1))
  if ! $CHECK "$f" >/dev/null 2>&1; then
    echo "FAIL: $f"
    $CHECK "$f" 2>&1 | head -3 | sed 's/^/      /'
    FAIL=$((FAIL+1))
  fi
done < <(find . -type f -name '*.lua' -print0)

echo
if [ "$FAIL" -eq 0 ]; then
  echo "OK: $TOTAL Lua files compiled cleanly."
  exit 0
else
  echo "FAIL: $FAIL / $TOTAL files failed."
  exit 1
fi
