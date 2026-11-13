#!/usr/bin/env bash
# Local headless Factorio server for developing the factorio-mcp mod.
# Vanilla (base only) + factorio-mcp, with a separate write-data dir under dev/ so it never touches
# your normal game. RCON only on 127.0.0.1:27015 (password "dev"). No UDP: the mod never sends.
#
#   scripts/dev-server.sh                  # auto_pause off (game keeps running)
#   AUTO_PAUSE=true scripts/dev-server.sh
#   FACTORIO_BIN=/path/to/factorio scripts/dev-server.sh
#   SPACE_AGE=true scripts/dev-server.sh   # enable space-age, quality, elevated-rails
#   SAVE=/path/to/save.zip scripts/dev-server.sh   # run a copy of this save instead of dev/saves/dev.zip
#   MODS_FROM=<dir> scripts/dev-server.sh  # also symlink and enable the .zip mods in <dir>
#                                          # (skipping those disabled in <dir>/mod-list.json)
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
DEV="$ROOT/dev"
AUTO_PAUSE=${AUTO_PAUSE:-false}
SPACE_AGE=${SPACE_AGE:-false}
MODS_FROM=${MODS_FROM:-}
SAVE=${SAVE:-$DEV/saves/dev.zip}
if [ -z "${FACTORIO_BIN:-}" ]; then
  for c in "$HOME/Library/Application Support/Steam/steamapps/common/Factorio/factorio.app/Contents/MacOS/factorio" \
           "/Applications/factorio.app/Contents/MacOS/factorio"; do
    [ -x "$c" ] && FACTORIO_BIN=$c && break
  done
fi
[ -x "${FACTORIO_BIN:-}" ] || { echo "Factorio binary not found; set FACTORIO_BIN"; exit 1; }

mkdir -p "$DEV/write" "$DEV/mods" "$DEV/saves"
cat > "$DEV/config.ini" <<INI
[path]
read-data=__PATH__system-read-data__
write-data=$DEV/write
INI
# Rebuild the mods dir from scratch so toggling the env vars is idempotent.
find "$DEV/mods" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
ln -sfn "$ROOT/mod/factorio-mcp" "$DEV/mods/factorio-mcp"
if [ -d "$DEV/probe-mod" ]; then
  ln -sfn "$DEV/probe-mod" "$DEV/mods/probe-mod"
fi
MODS_JSON=$(python3 - "$SPACE_AGE" "$MODS_FROM" "$DEV/mods" <<'PY'
import json, os, sys, zipfile
space_age, src, dst = sys.argv[1] == "true", sys.argv[2], sys.argv[3]
extra = []
disabled = set()
if os.path.exists(os.path.join(dst, "probe-mod")):
    extra.append("probe-mod")
if src and os.path.exists(os.path.join(src, "mod-list.json")):
    # honour the user's own enabled/disabled choices (some mods fail on a newer Factorio)
    listed = json.load(open(os.path.join(src, "mod-list.json")))["mods"]
    disabled = {m["name"] for m in listed if not m["enabled"]}
if src:
    for f in sorted(os.listdir(src)):
        if not f.endswith(".zip") or f.startswith("factorio-mcp") or f.startswith("factorio-ha"):
            continue
        z = zipfile.ZipFile(os.path.join(src, f))
        info = min((n for n in z.namelist() if n.endswith("info.json")), key=len)
        name = json.loads(z.read(info))["name"]
        if name in disabled:
            continue
        os.symlink(os.path.join(src, f), os.path.join(dst, f))
        extra.append(name)
mods = [{"name": "base", "enabled": True}]
mods += [{"name": n, "enabled": space_age} for n in ("elevated-rails", "quality", "space-age")]
mods += [{"name": n, "enabled": True} for n in extra + ["factorio-mcp"]]
print(json.dumps({"mods": mods}))
PY
)
printf '%s\n' "$MODS_JSON" > "$DEV/mods/mod-list.json"
if [ -n "$MODS_FROM" ] && [ -f "$MODS_FROM/mod-settings.dat" ]; then
  cp "$MODS_FROM/mod-settings.dat" "$DEV/mods/mod-settings.dat"
fi
cat > "$DEV/server-settings.json" <<JSON
{"name":"factorio-mcp dev","description":"local dev server","tags":[],
 "visibility":{"public":false,"lan":false},"require_user_verification":false,
 "max_players":0,"game_password":"","allow_commands":"admins-only",
 "autosave_interval":10,"autosave_slots":2,"auto_pause":$AUTO_PAUSE,
 "only_admins_can_pause_the_game":true}
JSON

COMMON=(-c "$DEV/config.ini" --mod-directory "$DEV/mods")
if [ ! -f "$SAVE" ]; then
  "$FACTORIO_BIN" "${COMMON[@]}" --create "$SAVE"
fi
exec "$FACTORIO_BIN" "${COMMON[@]}" --start-server "$SAVE" \
  --server-settings "$DEV/server-settings.json" \
  --bind 127.0.0.1 \
  --rcon-bind 127.0.0.1:27015 --rcon-password dev "$@"
