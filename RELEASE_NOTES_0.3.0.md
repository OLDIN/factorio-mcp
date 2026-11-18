# Release 0.3.0

Released: 2026-11-18

A new tool for the base's defenses.

## What changed

- **`inspect_defenses` (mod and service).** Around a `[gps]` point, a player, or yourself: turrets
  (gun, laser, flamethrower, rocket, tesla, artillery), walls, gates, land mines and radars, grouped
  by name, with ammo per group, fluid in flamethrower turrets, power state, damage, and a list of the
  worst problems first (turrets without ammo, power or fluid, then damaged turrets, walls and the
  rest). Enemy and neutral entities are skipped, so worms near the base do not count as turrets.
  The scan runs in one tick: radius up to 64 tiles (default 32), up to 50 listed problems.

The service lists the tool only when the mod in the game supports it, so a 0.3.0 service still works
with a 0.2.x mod (without `inspect_defenses`).

## Update

1. **Mod:** update it on the server the way you install mods. The game restarts and players re-sync
   the mod when they next join.
2. **Service:** set `FACTORIO_MCP_VERSION=0.3.0` (or leave `latest`), then `docker compose pull` and
   `up -d` for the service (or `./update.sh` from the deploy folder).

Protocol: new command `defenses`; see [docs/protocol.md](docs/protocol.md).
