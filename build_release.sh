#!/usr/bin/env bash
# ============================================================
#  build_release.sh -- File Grid-Diver X
#
#  Rileva l'ultima release in ./releases/ , propone la successiva
#  (ultima + 0.0.1) e chiede conferma. Poi impacchetta:
#    BASE  -> senza plugins/pdf_lib (PyMuPDF)
#    FULL  -> con plugins/pdf_lib (PyMuPDF, ~70 MB in più)
#
#  Uso:
#    ./build_release.sh
#    ./build_release.sh --clean
# ============================================================
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

APP_NAME="File Grid-Diver X"
RELEASES_DIR="$SCRIPT_DIR/releases"

# ------------------------------------------------------------
#  --clean
# ------------------------------------------------------------
if [ "${1:-}" = "--clean" ]; then
  read -rp "Eliminare TUTTO il contenuto di releases/ ? [y/N] " yn
  case "$yn" in
    [yY]*) rm -rf "$RELEASES_DIR"; mkdir -p "$RELEASES_DIR"; echo "releases/ pulito";;
    *) echo "Annullato";;
  esac
  exit 0
fi

# ------------------------------------------------------------
#  1. Trova l'ultima release (vX.Y.Z)
# ------------------------------------------------------------
mkdir -p "$RELEASES_DIR"

LATEST=$(ls -1 "$RELEASES_DIR" 2>/dev/null \
  | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' \
  | sort -V \
  | tail -1 || true)

if [ -z "$LATEST" ]; then
  LATEST="v0.0.0"
  echo "Nessuna release precedente trovata. Partiamo da zero."
fi
echo "Ultima release trovata : $LATEST"

# ------------------------------------------------------------
#  2. Calcola la prossima versione minima (ultima + 0.0.1)
# ------------------------------------------------------------
NEXT_MIN=$(python3 - "$LATEST" <<'PY'
import sys
v = sys.argv[1].lstrip("v")
p = list(map(int, v.split(".")))
p[2] += 1
print("v%d.%d.%d" % tuple(p))
PY
)
echo "Prossima consentita    : $NEXT_MIN"

# ------------------------------------------------------------
#  3. Chiedi la nuova versione
# ------------------------------------------------------------
read -rp "Nuova versione release [${NEXT_MIN}]: " NEWVER
NEWVER="${NEWVER:-$NEXT_MIN}"

case "$NEWVER" in
  v*) ;;
  *)  NEWVER="v$NEWVER" ;;
esac

if ! [[ "$NEWVER" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "ERRORE: formato non valido. Usa vX.Y.Z (es. v1.5.1)"
  exit 1
fi

if ! python3 - "$NEWVER" "$NEXT_MIN" <<'PY'
import sys
def parse(s): return list(map(int, s.lstrip("v").split(".")))
sys.exit(0 if parse(sys.argv[1]) >= parse(sys.argv[2]) else 1)
PY
then
  echo "ERRORE: la versione deve essere >= $NEXT_MIN"
  exit 1
fi

echo
echo "============================================================"
echo "  Build release : $NEWVER"
echo "============================================================"

RELEASE_DIR="$RELEASES_DIR/$NEWVER"
mkdir -p "$RELEASE_DIR"

# ------------------------------------------------------------
#  4. Funzione di packaging
# ------------------------------------------------------------
package() {
  local MODE="$1"   # base | full
  local SUFFIX OUT
  if [ "$MODE" = "full" ]; then SUFFIX="-full"; else SUFFIX=""; fi
  OUT="$RELEASE_DIR/File-GD-X-${NEWVER}${SUFFIX}.muxapp"

  local STAGE_ROOT STAGE
  STAGE_ROOT="$(mktemp -d /tmp/fgdx_rel_XXXXXX)"
  STAGE="$STAGE_ROOT/$APP_NAME"
  mkdir -p "$STAGE"

  echo
  echo "==> Packaging $MODE -> $(basename "$OUT")"

  # ---- Root files ----
  for f in main.lua conf.lua mux_launch.sh README.md LICENSE CHANGELOG.md; do
    [ -f "$f" ] && cp -a "$f" "$STAGE/"
  done

  # ---- Cartelle applicative (plugins escluso, gestito sotto) ----
  for d in core ui screens services themes assets glyph tools; do
    [ -d "$d" ] && cp -a "$d" "$STAGE/"
  done

  # ---- plugins/ (escludendo sempre pdf_lib dal giro generale) ----
  mkdir -p "$STAGE/plugins"
  for f in plugins/*; do
    [ -e "$f" ] || continue
    base=$(basename "$f")
    [ "$base" = "pdf_lib" ] && continue
    cp -a "$f" "$STAGE/plugins/"
  done

  # ---- plugins/pdf_lib solo in FULL ----
  if [ "$MODE" = "full" ] && [ -d "plugins/pdf_lib" ]; then
    cp -a "plugins/pdf_lib" "$STAGE/plugins/"
    echo "    + plugins/pdf_lib/ (PyMuPDF)"
  fi

  # ---- lib/ root ----
  mkdir -p "$STAGE/lib"
  for f in lib/*; do
    [ -e "$f" ] || continue
    base=$(basename "$f")
    case "$base" in
      aarch64|host|x86_64) continue ;;
    esac
    [ -L "$f" ] && continue
    [ -f "$f" ] && cp -a "$f" "$STAGE/lib/"
  done

  # ---- lib/aarch64 (in BASE escludi le lib PDF) ----
  if [ -d lib/aarch64 ]; then
    mkdir -p "$STAGE/lib/aarch64"
    for f in lib/aarch64/*; do
      [ -e "$f" ] || continue
      base=$(basename "$f")
      [ -L "$f" ] && continue
      if [ "$MODE" = "base" ]; then
        case "$base" in
          libmupdf.so.*|libmupdfcpp.so.*|libmujs.so.*|libcrypto.so.*|libssl.so.*)
            continue ;;
        esac
      fi
      cp -a "$f" "$STAGE/lib/aarch64/" 2>/dev/null || true
    done
  fi

  # ---- data/ (solo scheletro) ----
  mkdir -p "$STAGE/data/logs" "$STAGE/data/trash" \
           "$STAGE/data/downloads" "$STAGE/data/snapshots"
  : > "$STAGE/data/.gitkeep"
  : > "$STAGE/data/logs/.gitkeep"
  : > "$STAGE/data/trash/.gitkeep"

  # ---- cleanup ----
  find "$STAGE" -type f \( \
       -name '*.tmp' -o -name '*.bak' -o -name '*.fgd.bak' \
    -o -name '*.broken' -o -name '*.old' -o -name '*.orig' \
    -o -name '.DS_Store' -o -name 'Thumbs.db' -o -name '*.pyc' \
    \) -delete 2>/dev/null || true

  find "$STAGE" -type d -name '__pycache__'  -prune -exec rm -rf {} + 2>/dev/null || true
  find "$STAGE" -type d -name '.desktopbase' -prune -exec rm -rf {} + 2>/dev/null || true
  find "$STAGE" -type d -name '_backup_*'    -prune -exec rm -rf {} + 2>/dev/null || true
  find "$STAGE" -type d -name '_FGDX_*'      -prune -exec rm -rf {} + 2>/dev/null || true
  find "$STAGE" -type d -name '.git'         -prune -exec rm -rf {} + 2>/dev/null || true
  find "$STAGE/lib" -type l -delete 2>/dev/null || true

  for x in _NOT_FOR_GITHUB releases tests vendor .github .gitignore \
           .luacheckrc .busted .editorconfig; do
    rm -rf "$STAGE/$x" 2>/dev/null || true
  done

  # ---- summary ----
  local NFILES SIZE
  NFILES=$(find "$STAGE" -type f | wc -l)
  SIZE=$(du -sh "$STAGE" | cut -f1)
  printf "    files: %s   size: %s\n" "$NFILES" "$SIZE"

  # ---- zip ----
  local TMPZIP="/tmp/fgdx_${NEWVER}_${MODE}_$(date +%s).zip"
  rm -f "$TMPZIP"
  ( cd "$STAGE_ROOT" && zip -r -q "$TMPZIP" "$APP_NAME" \
      -x '*.DS_Store' -x '__MACOSX/*' -x '*.tmp' )
  mv -f "$TMPZIP" "$OUT"
  echo "    creato: $(basename "$OUT")"

  # ---- checksum ----
  ( cd "$RELEASE_DIR" && md5sum    "$(basename "$OUT")" > "$(basename "$OUT").md5"    )
  ( cd "$RELEASE_DIR" && sha256sum "$(basename "$OUT")" > "$(basename "$OUT").sha256" )
  echo "    md5 + sha256 generati"

  # ---- integrity ----
  if unzip -t "$OUT" >/dev/null 2>&1; then
    echo "    archive integrity: OK"
  else
    echo "    ERRORE: archive integrity FAILED"
    exit 1
  fi

  rm -rf "$STAGE_ROOT"
}

# ------------------------------------------------------------
#  5. Build entrambi i pacchetti
# ------------------------------------------------------------
package base
package full

echo
echo "============================================================"
echo "  RELEASE $NEWVER PRONTA"
echo "============================================================"
ls -lh "$RELEASE_DIR" | tail -n +2 | sed 's/^/  /'
echo
echo "Deploy:"
echo "  cp '$RELEASE_DIR/File-GD-X-${NEWVER}.muxapp'        /path/to/SD/"
echo "  cp '$RELEASE_DIR/File-GD-X-${NEWVER}-full.muxapp'   /path/to/SD/"
echo