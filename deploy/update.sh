#!/usr/bin/env bash
# Update the factorio-mcp service next to the Factorio server (run from the folder that holds
# docker-compose.mcp.yml and .env):
#   ./update.sh        pull the image named in .env (FACTORIO_MCP_VERSION) and restart if it changed
#
# The mod is updated separately, the way you install mods on your Factorio server (the game
# restarts and players re-sync). Set ADD_MODS_SCRIPT to a script that takes a mod name to run it
# from here: `ADD_MODS_SCRIPT=/path/to/script ./update.sh mod`.
set -euo pipefail

cd "$(dirname "$0")"
COMPOSE=(docker compose -f docker-compose.mcp.yml)
WHAT=${1:-service}

case $WHAT in
  service)
    "${COMPOSE[@]}" pull
    "${COMPOSE[@]}" up -d
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
