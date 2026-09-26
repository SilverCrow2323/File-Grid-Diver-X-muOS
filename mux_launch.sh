#!/bin/sh
# HELP: File-GD X
# ICON: file_grid_diver
# GRID: File-GD X
DIR="$(cd "$(dirname "$0")" && pwd)"
GAME_DIR="$DIR"
LOG_DIR="$GAME_DIR/data/logs"
mkdir -p "$LOG_DIR"
TS="$(date +%Y%m%d_%H%M%S)"
LOG_FILE="$LOG_DIR/fgd_${TS}.log"
LOVE_BIN="$DIR/lib/love"
[ -x "$LOVE_BIN" ] || LOVE_BIN="$(command -v love 2>/dev/null)"

ls -1t "$LOG_DIR"/fgd_*.log 2>/dev/null | tail -n +21 | while read -r f; do rm -f "$f"; done

if [ -z "$LOVE_BIN" ] || [ ! -x "$LOVE_BIN" ]; then
  echo "[FATAL] No LOVE binary found." | tee -a "$LOG_FILE"; exit 1
fi

# Silence gptokeyb2 (would otherwise remap gamepad to keys)
pkill -STOP -x gptokeyb2 2>/dev/null || true
pkill -STOP -x gptokeyb 2>/dev/null || true

OSD="muos_osd mux_osd muos_hotkey muos_hotkeys muos_volume muos-vol muos_osd.py"
for P in $OSD; do pkill -STOP -x "$P" 2>/dev/null || true; done
trap 'for P in $OSD; do pkill -CONT -x "$P" 2>/dev/null || true; done; pkill -CONT -x gptokeyb2 2>/dev/null || true; pkill -CONT -x gptokeyb 2>/dev/null || true' EXIT INT TERM

export SDL_GAMECONTROLLERCONFIG_FILE="/usr/lib/gamecontrollerdb.txt"
export XDG_DATA_HOME="$GAME_DIR/data"
export HOME="$GAME_DIR/data"
export LD_LIBRARY_PATH="$DIR/lib/aarch64:$DIR/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

# PyMuPDF (wheel estratto)
export PYTHONPATH="$DIR/data/pdf_pack/lib${PYTHONPATH:+:$PYTHONPATH}"

export PATH="tools:$PATH"
cd "$GAME_DIR" || exit 1
"$LOVE_BIN" . >> "$LOG_FILE" 2>&1
RC=$?
ln -sf "$(basename "$LOG_FILE")" "$LOG_DIR/latest.log" 2>/dev/null

for P in $OSD; do pkill -CONT -x "$P" 2>/dev/null || true; done
exit $RC
