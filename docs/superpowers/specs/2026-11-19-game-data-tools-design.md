# Game data tools (release 0.4.0): design

## Intent

Claude answers questions about a live, modded Factorio 2.1 game for the people who play it.
Today it can only see players, the game's reference data, machines and drills, and defenses near
a point. The common questions it cannot answer yet are: *how much of X do we make per minute*,
*is there enough power*, *what are we researching*, *where are the nests and how polluted are
we*, *what are the robots, trains and platforms doing*, *what do I carry*, *what are my alerts*,
*where is ore*, *what is wrong with belts, inserters and pipes here*.

This release adds all of these at once, as **one mod release (0.4.0)**: every mod release
restarts the game and makes every player re-sync mods, so the owner chose one big release over
several small ones.

## Goals

- Six groups of new read-only tools (below), each usable by the owner and by other players with
  their own token.
- Answers stay small: summary first, worst problems first, lists capped, details by name.
- No noticeable load on the game: cheap reads answer at once; anything that walks the whole map
  runs as a tick-split job, like `base_machines_overview`.

## Non-goals

- Changing the game in any way (still read-only by construction).
- Notifications pushed from the game (the service only answers questions).
- Splitting mod and service versions (separate task, plan note item 7).
- Localised names; internal names stay.

## Anti-goals (a failure even if it works)

- Another player's inventory, alerts or private items becoming visible.
- A scan that drops UPS or makes a client stutter while people play.
- Answers so large the client refuses them (keep under about 12 KB typical, 48 KB hard budget).
- Tools whose descriptions bloat Claude's context: the release takes the tool count from 13 to
  28, so each description stays to two or three lines.

## Constraints (from the existing project)

- Mod: one RCON command `/factorio-mcp <sub> <json>`, `dispatcher.register`, errors as
  `{code, message}`, response budget `limits.RESPONSE_BUDGET_BYTES` (48,000), `table_to_json`
  turns empty tables into `[]` (service normalizes with `normalize_lists`/`normalize_maps`).
- Service: `ToolSpec(name, requires, description, handler)`; a tool is listed only when the mod's
  `hello.commands` contains `requires`, so the 0.4.0 service keeps working with older mods.
  The caller comes from the token (`current_identity()`), never from tool arguments.
- Allowlist of subcommands in `server/factorio_mcp/commands.py`.
- Static read-only test `server/tests/test_readonly_static.py` scans the mod text.
- Long scans: job engine (`job_engine.lua`, `job_kinds.lua`): 512-tile blocks, counted first,
  empty ones skipped, crowded ones split, per-tick budget `factorio-mcp-work-per-tick`;
  the service returns `status: running` + `job_id` after 30 s.
- Lua API 2.1.24 members used below were checked in the game's own `runtime-api.json`.
- Repo rules: PR-only, English code and docs, hygiene gate, no private details in files.

## Approaches

1. **Extend the existing pattern (chosen).** Each group is mod subcommands plus service tools in
   the same shape as `area`/`defenses`; whole-map work becomes new job kinds in the existing
   engine. Reuses tests, paging, normalization, visibility and the measured cost model.
2. **One generic "query" subcommand** taking a description of what to read. Fewer files, but it
   is hard to keep read-only and private by construction, and hard to bound in size and cost.
   Rejected.
3. **Read save files offline** instead of the live game. No load on the game, but stale data and
   heavy parsing of a closed format. Rejected.

The owner picked **one release** (over two releases or one per group); the build approach is my
call, as the project already fixes it.

## The tools

Force: every new command takes the caller's nick (`player`) and reads **that player's force**
(`player.force`), so a player on another force sees only their own data. Surfaces: optional
`surface`; without it, all surfaces of the force (summed or grouped as noted).

### 1. Production statistics: `production_stats` (sub `production`)

- Source: `force.get_item_production_statistics(surface)` and
  `get_fluid_production_statistics(surface)`; per-window rates from
  `LuaFlowStatistics.get_flow_count{name, category = "input"|"output", precision_index}`
  (`defines.flow_precision_index`: `five_seconds`, `one_minute`, `ten_minutes`, `one_hour`, …);
  names come from `input_counts`/`output_counts`.
- Params: `window` (`5s`, `1m` default, `10m`, `1h`, `10h`), `surface?`, `name?`, `limit` (default 15).
- Answer: per item/fluid produced and consumed per minute and the net; without `name`, the top
  produced, the top consumed and the largest deficits (consumed > produced); with `name`, that
  item per surface.
- Cheap: one call. The exact unit `get_flow_count` returns per window is verified in a live test
  before the format is fixed.

### 2. Power: `inspect_power` (sub `power`) and `base_power_overview` (job kind `power_overview`)

- `inspect_power`: electric networks of poles within a radius (default 32, max 64) of a point,
  player or yourself. For each network (`electric_network_id`, one pole's
  `electric_network_statistics`): production and consumption per window by entity name (top N),
  accumulators (count, charge from `energy` / `electric_buffer_size`), and machines in the radius
  with status `low_power`/`no_power` per network. (No capacity ratio: the statistics hold flows,
  not generator capacity.)
- `base_power_overview`: job over all surfaces counting `electric-pole` entities per block, keeping
  one pole per distinct network id, then reading each network's statistics once at the end.
  Answer: networks sorted by trouble (most starved machines first), with surface, size (poles) and a `[gps]`
  of one pole; tiny networks (e.g. a lone pole) are summarized, not listed.

### 3. Research: `research_status` (sub `research`)

- Source: `force.current_research`, `research_progress`, `research_queue`, `technologies`
  (`researched`, `level`, `enabled`, `prerequisites`, `research_unit_count`,
  `research_unit_ingredients`, `saved_progress`).
- Answer: current research with progress, the queue, counts of researched/available
  technologies, and the technologies available now (enabled, not researched, all prerequisites
  researched), capped and pageable; `name?` gives one technology's state and what blocks it.

### 4. Threats, pollution, base defenses

- `inspect_threats` (sub `threats`): enemy-force structures around a point/player/yourself,
  radius default 128, synchronous up to 256 (larger radii, up to 1000, as job kind `threats`):
  spawners (`unit-spawner`, includes Gleba egg rafts), worms (`turret` on the enemy force),
  demolishers (`surface.get_segmented_units()` / territories on Vulcanus-like surfaces).
  Answer: counts by name, the nearest N with distance, compass direction and `[gps]`, and
  pollution at each listed spawner's chunk (is it being fed / will it attack).
- `inspect_pollution` (sub `pollution`): `surface.pollutant_type` (smoke, spores, …),
  `get_total_pollution()`, a coarse grid of `get_pollution` around a point (chunk resolution,
  e.g. 9×9 chunks, top cells listed with `[gps]`), the surface's pollution statistics per source
  (`game.get_pollution_statistics(surface)`), and enemy spawners inside polluted chunks.
- `base_defenses_overview` (job kind `defenses_overview`): the `defenses` scan over all surfaces
  through the engine, reusing `defenses_scan` aggregation per block. Answer: totals per surface
  and type, issue counts, the worst problems first (dry, unpowered, damaged) with `[gps]`.

### 5. Logistics, trains, platforms

- `logistic_networks` (sub `logistics`): `force.logistic_networks` per surface: robots (available
  / total, logistic and construction), roboports (`cells`), charging queues
  (`to_charge_robot_count`), and the top contents (`get_contents()`), with `name?` to count one
  item across networks. Networks are identified by surface + `network_id` + one roboport `[gps]`.
- `list_trains` (sub `trains`): `game.train_manager.get_trains{force = …}`: counts by
  `defines.train_state`, then problem trains first (`no_path`, `no_schedule`, `destination_full`,
  `manual_control` with cargo, long waits from `get_schedule().ticks_in_station`), each with id,
  group, current or target station, cargo summary (`get_contents`, `get_fluid_contents`), `[gps]`
  of the front stock. Passengers are not reported. Only schedule getters are used.
- `list_platforms` (sub `platforms`): `force.platforms`: name, `state`
  (`defines.space_platform_state`), location or route, speed, `damaged_tiles` count, hub top
  contents (hub inventory), with `name?` for one platform. Hidden if the game has no Space Age.

### 6. Personal and local details

- `my_inventory` (sub `inventory`): **only the caller's own** main inventory, armor and
  equipment summary, ammo and guns, and the crafting queue size; the service always sends the
  token's nick, the tool has no player argument. What an offline player's inventory returns
  is checked in a live test; if it is not readable, the answer says so.
- `my_alerts` (sub `alerts`): **only the caller's own** alerts (`player.get_alerts{}`), grouped
  by `defines.alert_type` with counts and the first N targets as `[gps]`. Offline behaviour is
  checked in a live test.
- `inspect_resources` (sub `resources`): ore patches around a point/player/yourself (radius
  default 64, max 128 synchronous): resource entities grouped by name and connected patch
  (chunk-level clustering), with total amount, tile count, a centre `[gps]`, and for fluids
  (crude oil, etc.) the yield; plus `get_resource_counts()` totals for the whole surface.
- `inspect_transport` (sub `transport`): belts, splitters, undergrounds, inserters and pipes
  around a point (radius default 16, max 32): counts by name, inserters by status with the stuck
  ones (`waiting_for_source_items`, `waiting_for_space_in_destination`, `no_power`) listed first
  with `[gps]`, and pipe fluid contents by fluid; belt item counts per belt name. These entity
  types join a **separate** allowlist (the private-entity exclusion of `area` stays as it is).

## Privacy

- Own-only by construction: inventory and alerts read the player named by the token; the tools
  take no player argument.
- Force-scoped: everything else reads only the caller's force.
- Not reported: train passengers, character entities, corpses, vehicles' inventories (cars,
  spidertrons), other players' crafting or inventory.
- Logistic network contents, train cargo and platform hubs are shared base storage and are
  reported.

## Read-only enforcement

`test_readonly_static.py` gains the mutating names this release could touch:
`LuaSchedule` setters (`set_records`, `add_record`, `remove_record`, `go_to_station`,
`set_stopped`, `add_interrupt`, `set_interrupts`, `clear_records`, …), `.manual_mode =`,
`.research_queue =`, `add_research`, `cancel_current_research`, `.insert(` (except
`table.insert(`, matched with a regex), `.remove_item(`, `.clear(`, `.energy =`, and a regex for
`.set_<word>(` calls (none exist in the mod today). Each new token gets a test that it is caught.

## Load and size

- Cheap synchronous commands (production, research, logistics, trains, platforms, inventory,
  alerts) are bounded by the number of items/trains/networks; each answer is capped and pageable
  (`offset`/`limit`) and measured on the real save.
- Radius-bounded commands (power, threats, pollution, resources, transport) have hard radius
  caps; their costs are measured on a profile copy of the real save (`scripts/profile-save.sh`,
  run with `nice` and only when nobody is playing on the Mac).
- New job kinds (`power_overview`, `defenses_overview`, `threats`) reuse the engine's cost model;
  the target is the same as today: whole base in seconds at 60 UPS.

## Testing

- Pure-Lua tests for every new logic module (aggregation, sorting, clustering, capping).
- Service tests for every tool (arguments, normalization, identity enforcement for
  `my_inventory`/`my_alerts`).
- Live tests on the dev server (vanilla, and `SPACE_AGE=true` for platforms, spores and
  demolishers) that check real return shapes.
- A measurement pass on a copy of the real save before the release; numbers go to
  `docs/measurements.md`.

## Delivery

- One branch and PR per group (6 PRs) into `main`; merging feature PRs publishes nothing.
- Then one release PR `Bump version to 0.4.0` (mod portal, image, GitHub Release), merged after
  the owner says yes; the owner deploys to the server.
- `docs/protocol.md` and the README tool table grow with each group.

## Left to the builder

- Exact field names inside each answer, default `limit`s, and grid sizes, within the caps above.
- Whether `inspect_threats` over 256 tiles needs the job path in practice (decided by the
  measurement).
- Chunk clustering details for resource patches.
