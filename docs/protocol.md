# Protocol v1 (mod <-> service)

The service sends one console command over RCON and reads one line back.

```
/factorio-mcp <command> <json-object>        (no arguments: {})
```

The reply is a single line of JSON printed with `rcon.print`:

```json
{"v":1,"ok":true,"result":{...}}
{"v":1,"ok":false,"error":{"code":"bad_params","message":"..."}}
```

- The command works only from the server console or RCON. A player typing it in game gets
  `factorio-mcp: server only` and nothing is sent to RCON.
- The parameter string is at most 1000 bytes. Parameters are JSON only; nothing is evaluated.
- Non-finite numbers (`NaN`, `inf`) never appear in a reply (they are dropped).
- Factorio encodes an empty Lua table as `{}`, even where the field is a list. The service
  normalizes known list and map fields.
- The mod never changes the world, never writes files and does nothing in the background except
  an `on_tick` handler while a tick-split job is running.

## Error codes

`server_only`, `unknown_command`, `bad_params`, `not_found`, `job_not_found`, `too_many_jobs`,
`internal` (no stack trace in the reply; details go to the game log).

## Commands

| Command | Parameters | `result` |
|---|---|---|
| `hello` | none | `{mod_version, protocol, commands, fingerprint, max_response_bytes}` |
| `server_info` | none | tick, paused, speed, players online, mods and versions, difficulty, map settings, non-secret mod settings, surfaces |
| `players` | none | `{players: [{name, index, online, admin, afk_ticks, online_ticks, color, position, surface}]}`; position and surface are `null` for offline players |
| `proto_recipes`, `proto_machines`, `proto_items`, `proto_fluids`, `proto_modules`, `proto_qualities`, `proto_technologies`, `proto_planets` | `{offset?, limit?}` | `{kind, total, offset, items, next}`; a page stops at the response budget, `next` is the offset of the following page or absent |
| `area` | `{player}` or `{surface, x, y}`; `radius?` (default 32, at most 64), `max_listed?` (default 20) | machines and drills around a point: `{center, radius, totals, groups, stopped, drills, truncated}` |
| `job_start` | `{kind, params?, mode?}` | `{job_id, mode, work_items}` |
| `job_result` | `{job_id, offset?, limit?}` | `{state: "running", mode, progress}`, `{state: "cancelled"}`, or `{state: "done", ...result fields, next?}` |
| `job_cancel` | `{job_id}` | `{cancelled}` |
| `job_status` | none | `{jobs: [{id, kind, state, mode, progress}], tick_handler_registered}` |

`hello.fingerprint` is a canonical string of all active mods with versions and the startup
settings (they change prototypes). The service hashes it and refetches reference data when it
changes. `max_response_bytes` is the page budget the mod respects (48,000 bytes).

### Entity statuses

`area` and the jobs report `defines.entity_status` names (`working`, `no_ingredients`,
`full_output`, `no_power`, ...). Only production machines are read: `assembling-machine`,
`furnace`, `lab`, `mining-drill`, `rocket-silo`, `agricultural-tower`. Characters, corpses,
vehicles (also modded ones) and containers are never queried, so their contents cannot leak.

### Tick-split jobs

Large queries run as jobs spread over game ticks so players do not feel them.

- `job_start` kinds: `machines_overview` (`params: {surfaces?: [name]}`, the whole map) and `area`
  (`params: {surface, x, y, radius, max_listed?}`, radius up to 1000).
- **Method.** The map is cut into 512-tile blocks. A block's allowlisted entities are counted (cheap);
  an empty block is skipped, a crowded one (more than 40 entities) is split into four quarters, and
  entities are read only from small areas. An entity belongs to the area its position lies in, so it
  is read once. Empty map costs almost nothing: a whole base takes seconds, not minutes.
- **Budget.** Work is measured in units of about 10 microseconds (counting an area costs about as
  much as the chunks in it, reading an entity costs a few units). `mode: ticks` spends
  `factorio-mcp-work-per-tick` units per tick (default 50, about a third of a millisecond);
  `mode: idle` spends `factorio-mcp-idle-work-per-poll` per `job_result` poll. The default mode is
  `idle` when nobody is online, which also works when the game is paused. A caller may force either.
- Poll `job_result` until `state` is `done`; `progress` is the share of the map area finished.
  Results are paged with `offset` and `next`; the job is removed after its last page. Unfetched
  results expire after 36,000 ticks; at most 8 are kept, at most 4 jobs run at once, and a surface
  whose generated chunks span more than 250,000 chunks is refused.
- Job state lives in `storage` as plain data, so a save made mid-job resumes after loading. Jobs
  saved by an older mod version are migrated (a running one is cancelled).
