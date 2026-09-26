#!/usr/bin/env bash
# tools/run_tests.sh -- run tests and lint locally.
#
# Install once:
#   luarocks install busted
#   luarocks install luacheck
#
# Then:
#   ./tools/run_tests.sh

set -eu
cd "$(dirname "$0")/.."

exit_code=0

if command -v busted >/dev/null 2>&1; then
    echo "== busted =="
    busted tests/ || exit_code=1
else
    echo "busted not found. Install with:"
    echo "  luarocks install busted"
    exit_code=1
fi

echo
if command -v luacheck >/dev/null 2>&1; then
    echo "== luacheck =="
    luacheck . --no-color || exit_code=1
else
    echo "luacheck not found. Install with:"
    echo "  luarocks install luacheck"
fi

exit $exit_code
