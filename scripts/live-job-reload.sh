#!/usr/bin/env bash
# Review Focus 2: save the game in the middle of a tick-split job, stop, start from that save:
# the job must continue to the end (tick handler re-registered by on_load) with no errors in the log.
# Works on a copy of the real save under dev/reload/ (never touches the original).
#
#   scripts/live-job-reload.sh              # real save with the synced mods
#   SAVE_SRC=/path/save.zip scripts/live-job-reload.sh
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SAVE_SRC=${SAVE_SRC:-$ROOT/dev/profile/fha-save-2026-11-13.zip}
MODS_FROM=${MODS_FROM:-"$HOME/Library/Application Support/factorio/mods"}
RELOAD="$ROOT/dev/reload"
PY="$ROOT/server/.venv/bin/python"
LOG="$ROOT/dev/write/factorio-current.log"

rm -rf "$RELOAD"; mkdir -p "$RELOAD"
cp "$SAVE_SRC" "$RELOAD/reload.zip"

start_server() {
  AUTO_PAUSE=false SPACE_AGE=true SAVE="$RELOAD/reload.zip" MODS_FROM="$MODS_FROM" \
    "$ROOT/scripts/dev-server.sh" > "$ROOT/dev/live-reload-server.log" 2>&1 &
  SERVER_PID=$!
  for _ in $(seq 1 240); do
    kill -0 "$SERVER_PID" 2>/dev/null || { echo "server exited early"; exit 1; }
    (exec 3<>/dev/tcp/127.0.0.1/27015) 2>/dev/null && return 0
    sleep 0.5
  done
  echo "server did not open RCON"; exit 1
}
stop_server() { kill -INT "$SERVER_PID" 2>/dev/null || true; wait "$SERVER_PID" 2>/dev/null || true; }
trap stop_server EXIT

echo "== first run: start a job and save while it runs"
start_server
"$PY" "$ROOT/scripts/job-reload-check.py" start-and-save
stop_server

echo "== second run: load that save; the job must continue"
start_server
"$PY" "$ROOT/scripts/job-reload-check.py" finish
stop_server
trap - EXIT

# "Got EOF on stdin" is the headless server noticing it has no terminal; not a mod problem.
if grep -E "desync|Error|Script Error|stack traceback" "$LOG" | grep -v "Got EOF on stdin"; then
  echo "FAIL: errors in the game log"; exit 1
fi
echo "OK: job survived save/load, log is clean"
