#!/bin/sh
# Runs the game for captures (off screen) and never hangs: stops Godot at the
# first script or shader error, or after MAX_S seconds (default 240), and
# prints the capture lines and errors.
# Usage: tools/capture.sh [godot user args...]   e.g. seed=2 shots=entry out=...
GODOT=${GODOT:-"C:/Users/kenny/Documents/Codex/2026-10-09/files-mentioned-by-the-user-les/work/tools/godot-4.6/Godot_v4.6-stable_win64_console.exe"}
MAX_S=${MAX_S:-240}
RES=${RES:-720x540}
LOG=$(mktemp)
if [ -n "$GODOT_SCRIPT" ]; then
  "$GODOT" --path . --position -4000,-4000 --resolution "$RES" --script "$GODOT_SCRIPT" -- "$@" > "$LOG" 2>&1 &
else
  "$GODOT" --path . --position -4000,-4000 --resolution "$RES" -- "$@" > "$LOG" 2>&1 &
fi
PID=$!
START=$(date +%s)
STATUS=0
while kill -0 $PID 2>/dev/null; do
  if grep -q -E "SCRIPT ERROR|Parse Error|SHADER ERROR|shader compilation failed|FAIL:" "$LOG"; then
    echo "ERREUR détectée, Godot arrêté :"; STATUS=1; break
  fi
  if [ $(( $(date +%s) - START )) -ge "$MAX_S" ]; then
    echo "DÉLAI de ${MAX_S} s dépassé, Godot arrêté"; STATUS=2; break
  fi
  sleep 1
done
if [ "$STATUS" -eq 0 ]; then
  wait "$PID" || STATUS=$?
fi
kill $PID 2>/dev/null
taskkill //F //FI "IMAGENAME eq Godot_v4.6-stable_win64.exe" //FI "WINDOWTITLE eq Hors Plan*" > /dev/null 2>&1
grep -E "capture |switch off|PASS:|FAIL:|probe |SCRIPT ERROR|Parse Error|SHADER ERROR|ERROR: .*shader|at: " "$LOG" | sort -u | cut -c1-220 | head -30
rm -f "$LOG"
exit $STATUS
