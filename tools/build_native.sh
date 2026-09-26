#!/usr/bin/env bash
# tools/build_native.sh -- compile lfs.so and cjson.so for the target.
#
# Usage:
#   ./tools/build_native.sh aarch64     # muOS H700 / RG35XX H
#   ./tools/build_native.sh host        # current machine (MX Linux)
#
# Output:
#   lib/aarch64/lfs.so  lib/aarch64/cjson.so
#   lib/host/lfs.so     lib/host/cjson.so
#
# Requirements for aarch64:
#   sudo apt install gcc-aarch64-linux-gnu libc6-dev-arm64-cross \
#                    libluajit-5.1-dev
#
# Requirements for host:
#   sudo apt install build-essential libluajit-5.1-dev

set -eu

TARGET="${1:-host}"
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$SCRIPT_DIR"

case "$TARGET" in
  aarch64)
    CC=aarch64-linux-gnu-gcc
    OUT=lib/aarch64
    ;;
  host)
    CC=cc
    OUT=lib/host
    ;;
  *)
    echo "Usage: $0 [host|aarch64]" >&2
    exit 1
    ;;
esac

mkdir -p "$OUT"
BUILD="$(mktemp -d /tmp/fgdx_native_XXXXXX)"
trap 'rm -rf "$BUILD"' EXIT

echo "== Target: $TARGET  (CC=$CC, out=$OUT) =="

# ---------- Locate LuaJIT headers ----------
LUAJIT_INC=""
for d in /usr/include/luajit-2.1 /usr/include/luajit-2.0 /usr/local/include/luajit-2.1; do
    if [ -f "$d/lua.h" ]; then LUAJIT_INC="$d"; break; fi
done
if [ -z "$LUAJIT_INC" ]; then
    echo "ERROR: LuaJIT headers not found."
    echo "  sudo apt install libluajit-5.1-dev"
    exit 1
fi
echo "== LuaJIT headers: $LUAJIT_INC =="

# ---------- lfs ----------
if [ ! -f "$OUT/lfs.so" ]; then
    echo
    echo "== lfs =="
    ( cd "$BUILD"
      if [ ! -d luafilesystem ]; then
          echo "  cloning luafilesystem..."
          git clone --depth 1 https://github.com/lunarmodules/luafilesystem
      fi
      cd luafilesystem
      # Use the vendored src/ directory directly.
      "$CC" -O2 -fPIC -shared \
          -I"$LUAJIT_INC" \
          src/lfs.c -o "$SCRIPT_DIR/$OUT/lfs.so"
    )
    echo "  -> $OUT/lfs.so"
else
    echo "== lfs: already built, skipping =="
fi

# ---------- cjson ----------
if [ ! -f "$OUT/cjson.so" ]; then
    echo
    echo "== cjson =="
    ( cd "$BUILD"
      if [ ! -d lua-cjson ]; then
          echo "  cloning lua-cjson..."
          git clone --depth 1 https://github.com/openresty/lua-cjson
      fi
      cd lua-cjson
      "$CC" -O2 -fPIC -shared \
          -I"$LUAJIT_INC" \
          -DUSE_INTERNAL_FPCONV \
          lua_cjson.c strbuf.c fpconv.c -o "$SCRIPT_DIR/$OUT/cjson.so"
    )
    echo "  -> $OUT/cjson.so"
else
    echo "== cjson: already built, skipping =="
fi

echo
echo "== Done. Sizes: =="
ls -lh "$OUT"/*.so 2>/dev/null | sed 's/^/  /'

echo
echo "Next: copy lib/$TARGET/*.so into the app's lib/ on your SD."
echo "The app detects them at boot:"
echo "  grep '\[native\]' .desktopbase/logs/latest.log"
