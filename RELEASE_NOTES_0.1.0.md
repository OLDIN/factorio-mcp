# Release 0.1.0

First release: a read-only MCP server for Factorio 2.1, so an AI assistant (Claude Code, Claude Desktop)
can answer questions about your running game from live data.

## What is in it

- **Mod** `factorio-mcp`: one whitelisted, read-only console command, answered as a single line of
  JSON. It never changes the world, writes files or sends anything over the network, and does no work
  while idle.
- **Service**: keeps one persistent RCON connection to the game and serves MCP tools over Streamable
  HTTP with a bearer token per person (revocable, only hashes stored, every call logged).
- **Tools**: `server_status`, `list_players`, eight `reference_*` tools (recipes, machines, items,
  fluids, modules, qualities, technologies, planets of *your* mod set, cached per mod set),
  `inspect_area` (machines and drills around a point, a player or yourself) and
  `base_machines_overview` (the whole base).
- **Large queries** (big areas, the whole base) run in small steps spread over game ticks, so players
  do not feel them; a save made mid-query resumes after loading.
- **Privacy**: vehicles, corpses and chat are never read; an inventory is only ever your own.

## Get it

- **Mod**: [Factorio mod portal](https://mods.factorio.com/mod/factorio-mcp), version 0.1.0
  (Factorio 2.1). Install it on the server like any mod; players receive it when they join.
- **Service image**: `ghcr.io/oldin/factorio-mcp:0.1.0` (linux/amd64 and linux/arm64).
- **Setup**: see the [README](README.md); Claude Desktop on Windows: [docs/windows-client.md](docs/windows-client.md);
  protocol: [docs/protocol.md](docs/protocol.md).

## Notes and limits

- The service speaks plain HTTP: expose it only on a private network (VPN) and set
  `FACTORIO_MCP_ALLOWED_HOSTS` when it is reachable by anything but localhost.
- The first release has been checked end to end on one server and one save. Tick-split queries
  with players online have been measured without a player in the game so far; reports are welcome.
- Not included yet: your own inventory, research, production statistics, surfaces, logistic
  networks, trains, space platforms, enemies, alerts, and belts/inserters/pipes/turrets/power in the
  area view. They are planned for later releases.

## Update instructions

1. Mod: update it on the server the way you install mods (the game restarts, players re-sync).
2. Service: `./update.sh` pulls the image named in `.env` (`FACTORIO_MCP_VERSION`) and restarts it.
