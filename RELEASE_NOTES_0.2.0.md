# Release 0.2.0

Large queries (the whole base, big areas) now take seconds instead of minutes, and a call can no longer
run into a client's reply timeout.

## What changed

- **Faster whole-base scans (mod).** The map is cut into 512-tile blocks: a block's machines are
  counted (cheap), empty blocks are skipped, crowded ones are split into quarters, and entities are
  read only from small areas. On a real 26,000-chunk map a base overview takes about 3 seconds (was
  about 55 s) with players online, at the same load per tick; with nobody online it takes under 0.1 s.
  The result is exact (checked against a direct count of the whole surface).
- **No more client timeouts (service).** A tool call that is still scanning after 30 seconds answers
  `status: "running"` with a `job_id`; calling the tool again with that `job_id` returns the result.
  `base_machines_overview` and `inspect_area` (radius above 64) support this.
- **Safer job handles (service).** `job_id` is a random handle bound to the person who started the scan
  and the kind of scan; it expires after 10 minutes (the scan is cancelled in the game), and one
  person can have at most 2 scans open.
- **Audit log (service).** A call the client gave up on is logged as `outcome=cancelled`.
- **Saves from 0.1.0 load fine (mod).** Jobs saved in the old layout are migrated (a running one is
  cancelled, a finished result is kept).

## Settings renamed (mod, map settings)

`factorio-mcp-chunks-per-tick` is now `factorio-mcp-work-per-tick` (default 50 work units, about a
third of a millisecond per tick) and `factorio-mcp-idle-chunks-per-poll` is now
`factorio-mcp-idle-work-per-poll`. If you changed the old values, set the new ones; the old settings
no longer exist.

## Update

1. **Mod:** update it on the server the way you install mods. The game restarts and players re-sync
   the mod when they next join.
2. **Service:** set `FACTORIO_MCP_VERSION=0.2.0` (or leave `latest`), then `docker compose pull` and
   `up -d` for the service (or `./update.sh` from the deploy folder).

Protocol: `job_start` now answers `{job_id, mode, work_items}` (was `total_chunks`); see
[docs/protocol.md](docs/protocol.md). Measurements: [docs/measurements.md](docs/measurements.md).
