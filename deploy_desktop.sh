#!/usr/bin/env bash
# deploy_desktop.sh -- avvia File-GD X su desktop con log per sessione.
# Ogni lancio produce .desktopbase/logs/YYYYMMDD_HHMMSS_session.log
# Rotazione automatica: mantiene le ultime 30 sessioni.
set -u

DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

LOG_DIR="$DIR/.desktopbase/logs"
mkdir -p "$LOG_DIR"

TS="$(date +%Y%m%d_%H%M%S)"
T_START="$(date +%s)"
LOG="$LOG_DIR/${TS}_session.log"
LATEST="$LOG_DIR/latest.log"

# --- Rotation ---
ls -1t "$LOG_DIR"/*_session.log 2>/dev/null \
  | tail -n +31 \
  | while read -r f; do rm -f "$f"; done

# --- LOVE binary ---
if command -v love >/dev/null 2>&1; then
  LOVE_BIN="love"
elif [ -x "$DIR/lib/love" ]; then
  LOVE_BIN="$DIR/lib/love"
else
  echo "ERRORE: LÖVE non trovato.  Installa: sudo apt install love" | tee -a "$LOG"
  exit 1
fi

# --- Header ---
{
  echo "============================================================"
  echo " File-GD X -- desktop session"
  echo "============================================================"
  echo "Started : $(date)"
  echo "Root    : $DIR"
  echo "Host    : $(hostname 2>/dev/null || echo '?')"
  echo "User    : $(whoami 2>/dev/null || echo '?')"
  echo "Kernel  : $(uname -srm 2>/dev/null || echo '?')"
  echo "LOVE    : $LOVE_BIN  ($("$LOVE_BIN" --version 2>&1 | head -1))"
  echo "Log     : $LOG"
  echo "------------------------------------------------------------"
  echo
} >> "$LOG"

# --- Symlink latest ---
ln -sf "$(basename "$LOG")" "$LATEST" 2>/dev/null || true

# --- Launch ---
set +e
"$LOVE_BIN" . 2>&1 | tee -a "$LOG"
RC=${PIPESTATUS[0]}
set -e

# --- Footer ---
{
  echo
  echo "------------------------------------------------------------"
  echo "Ended   : $(date)"
  echo "Exit    : $RC"
  echo "Duration: $(($(date +%s) - ${T_START:-$(date +%s)}))s"
  echo "============================================================"
} >> "$LOG" 2>/dev/null || {
  echo
  echo "------------------------------------------------------------"
  echo "Ended   : $(date)"
  echo "Exit    : $RC"
  echo "============================================================"
} >> "$LOG"

echo
echo "Log: $LOG"

exit $RC
