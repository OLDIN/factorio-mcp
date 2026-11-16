#!/usr/bin/env bash
# Update the factorio-mcp service on the server (run from a clone of the repository):
#   deploy/update.sh        pull, rebuild and restart the container if the code changed
#
# The mod is updated separately, the way you install mods on your Factorio server (the game
# restarts and players re-sync). Set ADD_MODS_SCRIPT to a script that takes the mod name to run
# it here: `ADD_MODS_SCRIPT=/path/to/script deploy/update.sh mod`.
set -euo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)
COMPOSE=("$REPO/deploy/docker-compose.mcp.yml")
WHAT=${1:-service}

case $WHAT in
  service)
    git -C "$REPO" pull --ff-only --quiet
    echo "code: $(git -C "$REPO" log -1 --format='%h %s (%cr)')"
    (cd "$REPO/deploy" && docker compose -f "${COMPOSE[0]}" up -d --build)
    sleep 3
    docker logs factorio-mcp --tail 5
    ;;
  mod)
    : "${ADD_MODS_SCRIPT:?set ADD_MODS_SCRIPT to a script that installs a mod by name}"
    "$ADD_MODS_SCRIPT" factorio-mcp
    ;;
  *)
    echo "usage: $0 [service|mod]" >&2
    exit 2
    ;;
esac
