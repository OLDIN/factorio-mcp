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

Commands added in 0.4.0 take `caller`: the nick from the service's token. They read only that player's force, and answer `not_found` "no such player" for an unknown nick.

| Command | Parameters | `result` |
|---|---|---|
| `hello` | none | `{mod_version, protocol, commands, fingerprint, max_response_bytes}` |
| `server_info` | none | tick, paused, speed, players online, mods and versions, difficulty, map settings, non-secret mod settings, surfaces |
| `players` | none | `{players: [{name, index, online, admin, afk_ticks, online_ticks, color, position, surface}]}`; position and surface are `null` for offline players |
| `proto_recipes`, `proto_machines`, `proto_items`, `proto_fluids`, `proto_modules`, `proto_qualities`, `proto_technologies`, `proto_planets` | `{offset?, limit?}` | `{kind, total, offset, items, next}`; a page stops at the response budget, `next` is the offset of the following page or absent |
| `area` | `{player}` or `{surface, x, y}`; `radius?` (default 32, at most 64), `max_listed?` (default 20) | machines and drills around a point: `{center, radius, totals, groups, stopped, drills, truncated}` |
| `defenses` | `{player}` or `{surface, x, y}`; `radius?` (default 32, at most 64), `max_listed?` (default 20, at most 50) | defensive structures of the players' forces around a point (enemy and neutral entities are skipped): `{center, radius, summary: {total, turrets, walls, other, issues: {no_ammo, no_power, no_fluid, damaged}}, groups: [{name, type, count, ready, damaged, ammo?, fluids?}], problems: [{name, type, x, y, issue, health, max_health, ammo?, fluid?}], problems_total}`; `problems` lists unsupplied turrets first, then damaged turrets, walls and the rest |
| `production` | `{caller, window?, surface?, name?, limit?}`; `window` is `5s`, `1m` (default), `10m`, `1h` or `10h`; `limit` 1..50 (default 15) | per minute, averaged over the window, for the caller's force: `{window, surfaces, items: {top_produced, top_consumed, deficits}, fluids: {...}}`, each entry `{name, produced, consumed, net}`; with `name`: `{window, name, kind, total, by_surface: [{surface, produced, consumed, net}], by_quality?}` (items are summed over qualities) |
| `power` | `{caller, player}` or `{caller, surface, x, y}`; `radius?` (default 32, at most 64), `limit?` (1..30, default 10) | electric networks of the caller's force with a pole in the radius, flows of the last 5 s in kW (`output` statistics = production, J/tick × 0.06): `{center, radius, window, networks: [{id, poles, gps, produced_kw, consumed_kw, top_producers, top_consumers, accumulators: {count, charge?}, starved: {low_power, no_power}}] (10 at most, most starved first), networks_total, starved_examples: [{name, gps, status, network}]}` |
| `research` | `{caller, name?, offset?, limit?}` (`limit` 1..50, default 20) | the caller's force: `{current: {name, level, progress} or absent, queue: [name], researched, total, available: {total, offset, items: [name], next?}}` (available = enabled, not researched, all prerequisites researched); with `name`: `{name, level, researched, enabled, progress, unit_count, ingredients: [{name, amount}], missing_prerequisites: [name]}` |
| `threats` | `{caller, player}` or `{caller, surface, x, y}`; `radius?` (default 128, at most 256), `limit?` (1..30, default 10) | structures of every force the caller's force treats as an enemy: spawners (`unit-spawner`, includes Gleba egg rafts), worms (`turret`) and segmented units (demolishers, by their head): `{center, radius, total, counts: {name: n}, nearest: [{name, type, distance, direction, gps, pollution?}]}`; `pollution` (spawners only) is the pollution of the spawner's chunk |
| `pollution` | `{caller, player}` or `{caller, surface, x, y}`; `grid?` (odd, 1..15 chunks, default 9), `limit?` (1..30, default 10) | `{surface, pollutant, total, center, grid, top_cells: [{gps, amount}], sources: [{name, per_minute}] (top 10 emitters on the surface, game pollution statistics), fed_spawners: [{name, gps, amount}]}` (enemy spawners inside the grid in chunks with pollution) |
| `logistics` | `{caller, surface?, name?, limit?}` (`limit` 1..50, default 15) | the caller's force's logistic networks: `{networks: [{surface, id, gps?, roboports, charging, logistic_robots: {available, total}, construction_robots: {available, total}, top_contents: [{name, quality, count}]}] (20 at most, least available logistic robots first), total}`; with `name`: `{name, total, by_network: [{surface, id, count}]}` (qualities summed) |
| `trains` | `{caller, surface?, problems_only?, offset?, limit?}` (`limit` 1..50, default 15) | the caller's force's trains: `{by_state: {state: n}, total, problems_total, trains: [{id, group?, state, surface, gps, station?, target?, waiting_ticks, cargo: [{name, count}] (top 5, qualities summed), fluids: [{name, amount}], problem?}], next?}`; problems (`no_path`, `destination_full`, `no_schedule`, `manual_with_cargo`, `long_wait` = over 5 minutes at a station) first; only schedule getters are used, passengers are not read |
| `platforms` | `{caller, name?, limit?}` (`limit` 1..50 hub stocks, default 10) | the caller's force's space platforms: `{platforms: [{name, state, location?, last_location?, speed, distance, damaged_tiles, hub_contents: [{name, quality, count}]}], total}`; empty without Space Age; unknown `name` → `not_found` |
| `inventory` | `{caller}` only (no other player can be named) | the caller's own inventory: `{online, readable: true, main: [{name, quality, count}] (largest stacks first), armor: {name, equipment: [{name, count}]} or absent, guns: [name], ammo: [{name, quality, count}], crafting_queue_size}`; `{online: false, readable: false}` whenever the caller is offline (Factorio 2.1 keeps no readable inventory for an offline player; checked live) |
| `alerts` | `{caller, limit?}` (`limit` 1..20 examples per type, default 5) | the caller's own alerts (`player.get_alerts{}`): `{online, by_type: [{type, count, examples: [{name, gps}]}]}`, `type` from `defines.alert_type` |
| `resources` | `{caller, player}` or `{caller, surface, x, y}`; `radius?` (default 64, at most 128), `limit?` (1..30, default 10) | resource entities in the radius, grouped into patches (same resource in touching chunks, 8 neighbours): `{center, radius, patches: [{name, amount, tiles or wells, gps (centre), fluid}] (most tiles or wells first), patches_total, surface_totals: {name: n}}` (`get_resource_counts()` of the surface); fluid resources (crude oil, ...) give the raw entity amount summed and `wells` instead of `tiles` |
| `transport` | `{caller, player}` or `{caller, surface, x, y}`; `radius?` (default 16, at most 32), `limit?` (1..30, default 15) | the caller's force's belts, loaders, inserters, pipes, pumps and tanks (own allowlist: no vehicles, characters or wagons): `{center, radius, counts: {name: n}, inserters: {by_status: {status: n}, stuck: [{name, gps, status}] (no_power, low_power, waiting_for_space_in_destination, waiting_for_source_items, in that order), stuck_total}, belts: {items: [{name, count}]} (top 10, qualities summed), fluids: [{name, amount}] (each pipe's, pump's and tank's own share of its fluid segment, summed by fluid: nothing is counted twice)}` |
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

- `job_start` kind `threats` (`params: {caller, surface, x, y, radius (at most 1000), limit?}`, mod 0.4.0+): the `threats` answer for radii above 256.
- `job_start` kind `defenses_overview` (`params: {caller, surfaces?, max_listed? (1..200, default 50)}`, mod 0.4.0+): the `defenses` scan of the caller's force over whole surfaces; result `{summary, by_surface: {surface: {total, problems}}, groups, problems_total, problems: [{..., surface, gps}]}`, worst first.
- `job_start` kind `power_overview` (`params: {caller, surfaces?}`, mod 0.4.0+): every electric network of the caller's force; result `{summary: {networks, starved_networks, tiny}, networks: [{id, surface, poles, gps, produced_kw, consumed_kw, top_producers, top_consumers, starved, accumulators}]}`, most starved first; networks under 3 poles with nothing consuming are only counted in `tiny`.
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
