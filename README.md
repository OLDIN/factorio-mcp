# factorio-mcp

A **read-only** [MCP](https://modelcontextprotocol.io) server for Factorio 2.1. It lets an AI
assistant (Claude Code, Claude Desktop) answer questions about a running game from live data:
"why is my plant not working", "what makes this recipe", "which drills are about to run dry".

It has two parts:

- `mod/factorio-mcp/` - a Lua mod that exposes one whitelisted, read-only console command
  (`/factorio-mcp <command> <json>`) and answers with a single line of JSON.
- `server/` - a Python service that keeps one persistent RCON connection to the game and serves
  MCP tools over Streamable HTTP, with a bearer token per person.

## What it can do

| Tool | Answers |
|---|---|
| `server_status` | Mods and versions, tick, pause, difficulty and map settings |
| `list_players` | Who is online or offline, positions of online players, play time |
| `reference_recipes`, `reference_machines`, `reference_items`, `reference_fluids`, `reference_modules`, `reference_qualities`, `reference_technologies`, `reference_planets` | The game's own data for *your* mod set (modded planets included), cached per mod set |
| `inspect_area` | Machines and drills around a `[gps]` point, a player, or yourself: what works, what stands and why, what is stuck in inputs and outputs, drills running dry |
| `base_machines_overview` | The same picture for the whole base, per surface and recipe |
| `inspect_defenses` | Turrets, walls, gates, mines and radars around a `[gps]` point, a player, or yourself: ammo and flamethrower fluid, power, damage, and the worst problems first (needs mod 0.3.0+) |

Large queries (big areas, the whole base) are split over many game ticks, so players do not feel them.

## Safety model

- **Read-only by construction.** There is no tool for arbitrary commands, Lua, files, shell, pause,
  speed or saving. A leaked token can only read.
- **Nothing is written** on the server or on players' computers, and the mod does nothing in the
  background while idle.
- **One token per person**, revocable on its own (the token file holds only SHA-256 hashes and is
  re-read on change). Every call is logged: who, which tool, how long; never the arguments.
- **Privacy.** Positions of all players are visible; an inventory only for the person asking (the
  name comes from the token, never from an argument). Vehicles, corpses and chat are never read.
- **No TLS inside the service.** Expose it only on a private network (for example a VPN). Tokens are accepted only in the `Authorization` header, never in a URL.

## Install

Requirements: Factorio 2.1, the server reachable over RCON from the machine that runs the service,
Docker.

1. **The mod.** Install `factorio-mcp` on the game server like any other mod (mod portal, or the zip
   from `scripts/package-mod.sh`). Players receive it automatically when they join. Restart the game.
2. **RCON on the same machine.** The service connects to the game's RCON port. Bind RCON to
   localhost (`--rcon-bind 127.0.0.1:27015`) so nothing else can reach it.
3. **The service.** A ready-made image is published at `ghcr.io/oldin/factorio-mcp`; the server needs
   only three small files, not the repository and not a build:
   ```sh
   mkdir factorio-mcp && cd factorio-mcp
   base=https://raw.githubusercontent.com/OLDIN/factorio-mcp/main
   for f in deploy/docker-compose.mcp.yml deploy/.env.example deploy/tokens.example.toml deploy/update.sh; do
     curl -fsSLO "$base/$f"
   done
   chmod +x update.sh && cp .env.example .env && cp tokens.example.toml tokens.toml   # edit both
   ```
   Make a token (any machine with Python; the script has no dependencies):
   ```sh
   curl -fsSLO "$base/scripts/new-token.py"
   python3 new-token.py --name alice --nick AliceInGame   # prints the token once and a tokens.toml block
   ```
   Put the block into `tokens.toml`, give the token to that person, then
   `docker compose -f docker-compose.mcp.yml up -d`. Read the downloaded files before running them.
   Set `FACTORIO_MCP_VERSION` in `.env` to a release number to pin the image. The container runs as
   a non-root user with a read-only filesystem, all capabilities dropped and 96 MB of memory.
4. **Update later:** `./update.sh` pulls the image and restarts the service. Updating the mod
   restarts the game and players re-sync mods when they next join.

Settings are environment variables (`deploy/.env.example`): `FACTORIO_MCP_HOST`, `FACTORIO_MCP_PORT`,
`FACTORIO_MCP_ALLOWED_HOSTS` (set it whenever the service is reachable by anything but localhost),
`FACTORIO_MCP_RCON_*`, `FACTORIO_MCP_TOKENS_FILE`.

## Connect a client

**Claude Code:**

```sh
claude mcp add --transport http factorio http://<service-address>:8787/mcp \
  --header "Authorization: Bearer <your-token>"
```

**Claude Desktop** cannot use plain connectors for a private address: see
[docs/windows-client.md](docs/windows-client.md) (works the same on macOS).

Then ask, for example: "Which of my assemblers near me are stuck and why?" or
"What recipes make plastic bar here, and in which machines?"

## Protocol and measurements

[docs/protocol.md](docs/protocol.md) describes the mod/service protocol; [docs/measurements.md](docs/measurements.md)
holds the measurements behind the limits (RCON reply size, API quirks, job costs).

## Development

```sh
scripts/test-mod.sh            # pure-Lua mod tests (LUA=lua5.2 to match Factorio)
luacheck mod/factorio-mcp      # lint the mod (.luacheckrc)
cd server && uv venv && uv pip install -e ".[test]" && .venv/bin/pytest -q
ruff check .                   # lint Python (.ruff.toml)
scripts/live.sh                # live tests against a local headless Factorio (needs Factorio installed)
scripts/check-hygiene.sh       # public-repo hygiene gate, also run in CI
```

`scripts/dev-server.sh` starts a local headless server for the mod (RCON on localhost only).
`scripts/check-hygiene.sh` fails if tracked files or git history contain private network details,
assistant attribution lines, or committed `*.zip` / `*.dat` files; extra local patterns can be listed in
the untracked `dev/hygiene-patterns.txt`.

Releases: `python scripts/bump_version.py patch --pr` opens a version-bump pull request; after the
merge a workflow tags the release and another uploads the mod to the Factorio mod portal.

## License

MIT
