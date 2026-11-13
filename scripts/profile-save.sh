#!/usr/bin/env bash
# Run the local Factorio dev server with the real save and synced user mods.
# All planetary mods and mod settings from ~/Library/Application Support/factorio/mods are loaded.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
DEV="$ROOT/dev"
SAVE=${SAVE:-$DEV/profile/fha-save-2026-11-13.zip}
MODS_FROM=${MODS_FROM:-"$HOME/Library/Application Support/factorio/mods"}
SPACE_AGE=${SPACE_AGE:-true}

SPACE_AGE="$SPACE_AGE" SAVE="$SAVE" MODS_FROM="$MODS_FROM" "$ROOT/scripts/dev-server.sh" "$@"
