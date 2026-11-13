#!/usr/bin/env bash
# Start the local dev Factorio server in the background, wait for RCON, run the live tests
# (`pytest -m live`), then stop the server. Extra arguments go to pytest.
#
#   scripts/live.sh                 # all live tests
#   scripts/live.sh -k hello -x     # selected ones
# Environment for the server is passed through (AUTO_PAUSE, SAVE, MODS_FROM, SPACE_AGE).
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
LOG="$ROOT/dev/live-server.log"
mkdir -p "$ROOT/dev"

if (exec 3<>/dev/tcp/127.0.0.1/27015) 2>/dev/null; then
  echo "something already listens on 127.0.0.1:27015; stop it first" >&2
  exit 1
fi

"$ROOT/scripts/dev-server.sh" > "$LOG" 2>&1 &
SERVER_PID=$!
cleanup() {
  kill "$SERVER_PID" 2>/dev/null || true
  wait "$SERVER_PID" 2>/dev/null || true
}
trap cleanup EXIT

for _ in $(seq 1 240); do
  if ! kill -0 "$SERVER_PID" 2>/dev/null; then
    echo "dev server exited early; see $LOG" >&2
    tail -20 "$LOG" >&2
    exit 1
  fi
  if (exec 3<>/dev/tcp/127.0.0.1/27015) 2>/dev/null; then
    break
  fi
  sleep 0.5
done

cd "$ROOT/server"
FACTORIO_MCP_LIVE=1 .venv/bin/pytest -m live -q "$@"
