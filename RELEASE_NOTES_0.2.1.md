# Release 0.2.1

A service-only release: answers are much smaller, so an assistant reads far less per call. **The mod is
byte-identical to 0.2.0**: update the service image only; the game does not restart and players do not
re-sync anything.

## What changed (service)

- **`base_machines_overview`** answers with totals, machines by status and by surface, and one page of
  the most stuck groups (25 by default, sorted by how many machines in a group are not working).
  `offset`, `limit` and `only_stopped` page through the rest. A 16-surface base used to return 621
  groups (about 160 KB, roughly 40,000 tokens), which did not fit a tool result.
- **`reference_*` lists** return short rows (for example `"in": ["2 iron-plate"], "out": ["1 iron-gear-wheel"]`,
  technologies as cost, prerequisites and unlocks); the full record comes with `name=` or `details=true`.
  The default page is 25 rows.
- **`server_status`** leaves out the map, map-generation and mod settings (about 25 KB) unless
  `details=true`.
- **`inspect_area`** lists the 15 most stuck groups of a big area and reports how many were left out
  (`groups_omitted`); `max_groups` changes it.

## Update

Set `FACTORIO_MCP_VERSION=0.2.1` (or leave `latest`) and run `docker compose pull` and `up -d` for the
service. Nothing to do for the mod.
