# Game Data Tools (0.4.0) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task (the owner chose inline execution without subagents). Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add 15 read-only tools (production, power, research, threats/pollution/defenses overview, logistics/trains/platforms, own inventory/alerts, resources, transport) and ship them as mod and service release 0.4.0.

**Architecture:** Each tool is a mod subcommand (`scripts/commands/<sub>.lua` for parameters and wiring, `scripts/logic/<name>.lua` for pure aggregation that tests can drive with fakes) plus a service `ToolSpec` (`server/factorio_mcp/tools/<group>.py`). Whole-map work becomes new kinds in the existing tick-split job engine. Every new subcommand takes `caller` (the token's nick) and reads only that player's force.

**Tech Stack:** Lua 5.2 (Factorio 2.1.24 runtime API), Python 3.13 service (`mcp` MCPServer, pytest, ruff), headless Factorio for live tests.

**Spec:** `docs/superpowers/specs/2026-11-19-game-data-tools-design.md`

## Global Constraints

- Read-only by construction; `server/tests/test_readonly_static.py` must pass.
- Every new subcommand takes `caller` and reads only `game.get_player(caller).force`; inventory and alerts read only the caller, and their tools have no player argument.
- Not reported: train passengers, characters, corpses, vehicle inventories, other players' inventory or crafting.
- Answers: summary first, worst problems first, lists capped; typical answer about 12 KB or less, hard budget `limits.RESPONSE_BUDGET_BYTES` (48,000).
- Tool descriptions: two or three lines each (the tool count goes from 13 to 28).
- Synchronous caps: `inspect_power` radius default 32 / max 64; `inspect_threats` default 128 / sync max 256 / job max 1000; `inspect_resources` default 64 / max 128; `inspect_transport` default 16 / max 32.
- `production_stats` windows: `5s`, `1m` (default), `10m`, `1h`, `10h`; `limit` default 15.
- Whole-map work only through the job engine (`power_overview`, `defenses_overview`, `threats`).
- Repo rules: one branch + PR per group into `main`, English code/docs, no assistant attribution lines in commits or PRs, `scripts/check-hygiene.sh`, `ruff check .`, `pytest -q`, `scripts/test-mod.sh` green before each commit; live tests (`nice -n 15 scripts/live.sh -k <name>`) before claiming a mod change works; luacheck runs in CI (Docker is not always up locally).
- Release PR `Bump version to 0.4.0` only after the owner says yes; the owner deploys to the server.

## Review Focus

- **Unknown or mistyped caller nick in a token** (a new player's token with a typo): every new command answers `not_found` "no such player", never `internal`. Test: `caller_test.lua` (Task 1) plus one service test per group asserting the ToolError text.
- **Empty or missing data on a surface** (a fresh space platform surface with no statistics, a game without Space Age, a force with no logistic networks): answers are empty lists/maps after normalization, not errors. Tests: `test_production_empty_surface` (Task 2), `test_platforms_none` (Task 11), `test_logistics_none` (Task 9).
- **Very large counts** (500 trains, 300 items in a network, 2,000 technologies in a modpack): lists are capped with a `total` and `next`, the answer stays under the budget. Tests: `trains_logic_test.lua` with 500 fake trains (Task 10), `research_logic_test.lua` with 2,000 technologies (Task 5).
- **Division by zero** (an accumulator with zero buffer, a network or window with no flow, a logistic network with no robots): no NaN/inf in answers (`envelope.sanitize` drops them; logic returns `nil` or `0` explicitly). Tests: `power_logic_test.lua` zero-flow and zero-buffer cases (Task 3), `logistics_logic_test.lua` zero robots (Task 9).
- **Caller offline** (the brother asks while not in the game): point-free commands (production, research, logistics, trains, platforms, alerts, inventory) still answer for the caller's force; position-based ones without `gps`/`player` answer "offline: give a [gps] tag". Tests: `test_power_offline_caller_needs_gps` (Task 3), live check of offline inventory/alerts (Task 12).

---

## How every command task is built (shared shape)

Each "command task" below follows these steps; the task lists only what differs (params, answer fields, test assertions).

1. Write the pure-Lua test `mod/tests/<logic>_test.lua` (fakes as in `mod/tests/defenses_scan_test.lua`; `support.env.fresh()` first).
2. `scripts/test-mod.sh` → FAIL (module missing).
3. Implement `mod/factorio-mcp/scripts/logic/<logic>.lua` (pure: takes Lua objects/fakes, returns plain tables) and `mod/factorio-mcp/scripts/commands/<sub>.lua` (validation via `scripts/logic/params.lua`, `caller.force`, calls the logic module, `dispatcher.register("<sub>", …)`); add `require("scripts.commands.<sub>")` to `control.lua`.
4. `scripts/test-mod.sh` → PASS.
5. Write the service test `server/tests/test_tools_<tool>.py` (pattern of `server/tests/test_tools_defenses.py`: `hello_reply` with the sub in `commands`, fake response keyed by the exact `build_command(...)`, assert on the parsed answer and on the exact command sent).
6. `cd server && .venv/bin/python -m pytest tests/test_tools_<tool>.py -q` → FAIL.
7. Add the sub to `ALLOWED_SUBS` in `server/factorio_mcp/commands.py`, implement the `ToolSpec` in `server/factorio_mcp/tools/<group>.py` (`specs(bridge) -> list[ToolSpec]`), add `*<group>.specs(bridge)` to `all_specs` in `server/factorio_mcp/app.py` (once per group module).
8. pytest → PASS; `ruff check .` → clean.
9. Write the live test in `server/tests/live/test_<group>_live.py` (pattern of `test_defenses_live.py`; `/sc` setup only on the dev server; `SPACE_AGE=true` when the task says so; the caller is read at runtime with `/sc rcon.print(game.players[1].name)`, never a real nick in the repo; surfaces the dev save lacks, such as Gleba or Vulcanus, are created in setup with `game.planets.<name>.create_surface()`) and run `nice -n 15 scripts/live.sh -k <name>` → PASS.
10. Add the command row to `docs/protocol.md` (Commands table) and the tool row to `README.md` (What it can do).
11. `scripts/check-hygiene.sh` → `hygiene: ok`; commit `feat(<group>): <tool>`.

Each group ends with: push the branch, open the PR (body: what, tests run, compatibility note "tool hidden until the mod has the command"), wait for green CI, merge only with the owner's yes for that PR (or a standing yes for all group PRs of this plan, if the owner gives one), then update the plan note in the owner's vault ("Стан виконання") with one line.

---

## Group 1 — production (branch `feature/game-data-tools`, which also carries this plan and the design)

### Task 1: Shared foundations

**Files:**
- Create: `mod/factorio-mcp/scripts/logic/caller.lua`, `mod/factorio-mcp/scripts/logic/params.lua`, `mod/factorio-mcp/scripts/logic/geo.lua`, `server/factorio_mcp/tools/common.py`
- Modify: `mod/factorio-mcp/scripts/commands/area.lua`, `mod/factorio-mcp/scripts/commands/defenses.lua` (use the shared helpers, behaviour unchanged), `server/factorio_mcp/tools/area.py`, `server/factorio_mcp/tools/defenses.py` (use `point_args`), `server/tests/test_readonly_static.py`
- Test: `mod/tests/caller_test.lua`, `mod/tests/geo_test.lua`, `server/tests/test_tools_common.py`, `server/tests/test_readonly_static.py`

**Interfaces:**
- Produces (Lua):
  - `params.number(p, key, default) -> number` (finite or `bad_params`), `params.int(p, key, default, min, max) -> integer`, `params.string(p, key, default?) -> string|nil`, `params.one_of(p, key, default, allowed_list) -> string`.
  - `caller.player(p) -> LuaPlayer` (from `p.caller`; `bad_params` "caller must be a string" if missing, `not_found` "no such player" if unknown); `caller.force(p) -> LuaForce`.
  - `caller.center(p) -> LuaSurface, {x, y}` (moved from `area.lua`/`defenses.lua`: `{player}` → physical position, offline → `not_found` "player is offline: position unknown"; `{surface, x, y}` otherwise).
  - `geo.distance(a, b) -> number`, `geo.direction(from, to) -> "N"|"NE"|"E"|"SE"|"S"|"SW"|"W"|"NW"` (Factorio y grows southwards), `geo.gps(surface_name, x, y) -> "[gps=x,y,surface]"` (x, y rounded to integers).
- Produces (Python, `tools/common.py`):
  - `point_args(gps: str | None, player: str | None) -> dict[str, Any]` (gps → `{surface, x, y}`; player → `{player}`; neither → `{player: current_identity().nick}`; bad gps → `ToolError` with the existing message).
  - `caller_args() -> dict[str, str]` → `{"caller": current_identity().nick}`.
  - `call_mod(bridge, sub, args) -> dict` (calls `bridge.call`, turns `ModError` with code `not_found`/`bad_params` into `ToolError(err.message)`).

- [ ] **Step 0: A player record in the dev save (needs the owner).** The dev save has no players (`players=0`, checked 2026-11-19), and every new command needs `caller`. Start `nice -n 15 scripts/dev-server.sh`, the owner connects once from their Factorio client to `localhost`, then disconnects; run `/server-save` over RCON and copy the newest save from `dev/write/saves/` to `dev/saves/dev.zip`. Check: `players=1`. The `dev/` folder is not in the repo, so no nick is committed.
- [ ] **Step 1: Write failing tests.** `caller_test.lua`: missing caller → `bad_params`; unknown nick → `not_found` with message "no such player"; known offline player → `caller.force` returns its force; `caller.center` with offline `player` → `not_found` "player is offline: position unknown". `geo_test.lua`: `direction({0,0},{0,-10}) == "N"`, `({0,0},{10,10}) == "SE"`, `({0,0},{-10,0}) == "W"`; `gps("nauvis", 12.6, -3.2) == "[gps=13,-3,nauvis]"`. `test_tools_common.py`: `point_args("[gps=1,2,gleba]", None) == {"surface": "gleba", "x": 1.0, "y": 2.0}`; `call_mod` maps `ModError("not_found", "no such player")` to `ToolError("no such player")`. `test_readonly_static.py`: new tokens are caught in a synthetic snippet (`set_records`, `add_record`, `remove_record`, `go_to_station`, `set_stopped`, `add_interrupt`, `set_interrupts`, `clear_records`, `.manual_mode =`, `.research_queue =`, `add_research`, `cancel_current_research`, `.remove_item(`, `.clear(`, `.energy =`, `on_flow(`, `set_flow_count`, `.schedule =`, `.paused =`, `current_research =`, `research_progress =`, `.insert(` except `table.insert(`, `.set_<word>(`), and `table.insert(x, y)` is not flagged.
- [ ] **Step 2:** `scripts/test-mod.sh` and pytest → FAIL.
- [ ] **Step 3:** Implement the helpers; switch `area.lua`, `defenses.lua`, `area.py`, `defenses.py` to them; extend `FORBIDDEN_LUA` with the plain tokens and add regexes `(?<!table)\.insert\(` and `\.set_\w+\(`.
- [ ] **Step 4:** All tests PASS, including the existing area/defenses tests unchanged; `nice -n 15 scripts/live.sh -k "area or defenses"` PASS.
- [ ] **Step 5:** Commit `refactor: shared caller, params and point helpers; stricter read-only scan`.

### Task 2: `production_stats` (sub `production`)

**Files:** Create `scripts/commands/production.lua`, `scripts/logic/production_logic.lua`, `server/factorio_mcp/tools/production.py`; tests `mod/tests/production_logic_test.lua`, `server/tests/test_tools_production.py`, `server/tests/live/test_production_live.py`.

**Interfaces:**
- Consumes: `caller.force`, `params.*` (Task 1).
- Mod params: `{caller, window?, surface?, name?, limit?}`; `window` ∈ `5s|1m|10m|1h|10h` → `defines.flow_precision_index.five_seconds|one_minute|ten_minutes|one_hour|ten_hours`; `limit` 1..50, default 15.
- Produces: `production_logic.rates(stats_by_surface, kind, window_index, per_minute_factor) -> {name -> {produced, consumed}}`, `production_logic.summarize(rates, limit) -> {top_produced, top_consumed, deficits}` (each `[{name, kind, produced, consumed, net}]`, per minute, rounded to 2 decimals; deficits = consumed > produced, largest gap first).
- Answer without `name`: `{window, surfaces: [names], items: {top_produced, top_consumed, deficits}, fluids: {same}}`. With `name`: `{window, name, kind, total: {produced, consumed, net}, by_surface: [{surface, produced, consumed, net}]}`.

- [ ] **Step 0: Calibrate the unit on the dev server.** In a scratch live test, `/sc` `game.forces.player.get_item_production_statistics("nauvis").on_flow("iron-plate", 600)`, then read `get_flow_count{name="iron-plate", category="input", precision_index=<each>, count=false}` and `count=true`. Record which call gives "per minute" for each window in a comment at the top of `production_logic.lua` and set `per_minute_factor` per window from it. Also record: (a) whether `input_counts` keys and `get_flow_count{name=…}` are split by quality (the owner's game runs quality; if split, sum qualities per item and add a `by_quality` field only with `name`); (b) for an electric network, which of `input`/`output` is production in `electric_network_statistics` (needed by Task 3). Keep these checks as `test_production_flow_unit` and `test_electric_flow_direction` in the live tests.
- [ ] **Steps 1–11 (shared shape).** Lua test: two surfaces, iron plates produced 120/min on nauvis and 60/min on vulcanus, consumed 200/min on nauvis → `deficits[1].name == "iron-plate"` with `net == -20`; `limit = 1` keeps one entry per list; empty statistics → empty lists. Service tests: `test_production_default_window_and_caller` (command `{"caller":"aliceNick","window":"1m","limit":15}`), `test_production_by_name`, `test_production_bad_window` (ToolError lists the allowed windows), `test_production_empty_surface` (empty lists normalize to `[]`), `test_production_unknown_caller` (ToolError "no such player"). Live: after `on_flow`, `production_stats` reports iron-plate produced > 0 for `5s`.
- [ ] **Group 1 PR**: `feat: production statistics tool` (Tasks 1–2).

## Group 2 — power (branch `feature/power`)

### Task 3: `inspect_power` (sub `power`)

**Files:** Create `scripts/commands/power.lua`, `scripts/logic/power_logic.lua`, `server/factorio_mcp/tools/power.py`; tests `mod/tests/power_logic_test.lua`, `server/tests/test_tools_power.py`, `server/tests/live/test_power_live.py`.

**Interfaces:**
- Mod params: `{caller, player?} | {caller, surface, x, y}`, `radius?` (default 32, max 64), `window?` (as Task 2, default `1m`), `limit?` (default 10, max 30).
- Produces: `power_logic.network_summary(stats, window_index, limit) -> {produced_kw, consumed_kw, top_producers: [{name, kw}], top_consumers: [{name, kw}]}` (direction from the Task 2 calibration), `power_logic.accumulators(entities) -> {count, charge}` (`charge = sum(energy)/sum(electric_buffer_size)`, `nil` if buffer 0). No capacity ratio: the statistics hold flows, not generator capacity; trouble is shown by starved machines per network and accumulator charge.
- Mod reads poles (`type = "electric-pole"`, caller's force) in the radius, groups by `electric_network_id`, one representative pole per network, its `electric_network_statistics`; accumulators in the radius; machines in the radius with status `low_power`/`no_power` (reuse `area_scan.AREA_TYPES`, entity status names from `scripts/statuses.lua`).
- Answer: `{center, radius, networks: [{id, poles, gps, produced_kw, consumed_kw, top_producers, top_consumers, accumulators, starved: {low_power, no_power}}], starved_examples: [{name, gps, status, network}]}`; a machine's network is its `electric_network_id`; networks sorted by starved machines (most first), then by accumulator charge ascending.

- [ ] **Steps (shared shape).** Lua test: two networks, the one with starved machines sorts first; a network with zero flow gives `produced_kw == 0` (not NaN); accumulator buffer 0 → `charge == nil`. Service tests: `test_power_defaults` (`{"caller":"aliceNick","player":"aliceNick","radius":32.0,"window":"1m","limit":10}`), `test_power_gps`, `test_power_offline_caller_needs_gps` (mod `not_found` "player is offline: position unknown" → ToolError suggests a `[gps]` tag). Live: place a steam engine + boiler + offshore pump + pole + lamp via `/sc`, assert one network with `produced_kw >= 0`, and an unpowered assembler near a pole of an empty network listed in `starved`.

### Task 4: Job engine filters + `base_power_overview` (job kind `power_overview`)

**Files:** Modify `scripts/logic/job_kinds.lua`; create `scripts/logic/power_overview.lua`; modify `server/factorio_mcp/tools/power.py`; tests `mod/tests/job_kinds_test.lua` (extend), `mod/tests/power_overview_test.lua`, `server/tests/test_tools_power.py` (extend), live test extended.

**Interfaces:**
- `scan_area(job, si, x0, y0, size, take, filter)` in `job_kinds.lua`: `filter` is a table merged into both `count_entities_filtered` and `find_entities_filtered` (`{type = …, force = …}`); existing kinds pass `{type = area_scan.AREA_TYPES}`. Planner helper `plan_surfaces(params) -> {surfaces, work}` extracted from `plan_overview` (same validation, same `MAX_JOB_CHUNKS`).
- Kind `power_overview`, params `{caller, surfaces?}`: the planner calls `caller.force(params)` and stores `force = <name>` in the job's `params`, so the filter uses the caller's force. The same rule applies to kinds `threats` and `defenses_overview` below (their params say `force` for brevity; the service always sends `caller`). `take` keeps the first pole per `electric_network_id`; `finish` reads each kept pole's statistics with `power_logic.network_summary` and returns `{fields = {summary = {networks, starved_networks, tiny}}, list_name = "networks", list = [...] }` (`take` also counts machines of `area_scan.AREA_TYPES` with `low_power`/`no_power` per network, so the job filter is `{type = {"electric-pole", <AREA_TYPES>}, force}`); networks with fewer than 3 poles and no consumption are counted in `tiny` and not listed.
- Tool `base_power_overview(window="1m", limit=15, offset=0, job_id=None)` uses `JobRunner.run("power_overview", …)` exactly like `base_machines_overview`.

- [ ] **Steps (shared shape).** Lua: existing `job_kinds_test.lua` still passes with the filter argument; `power_overview_test.lua`: three poles of network 7 and one of network 9 → two networks, pole counts 3 and 1. Service: `test_base_power_overview_running_then_done` (first call returns `status: running` + `job_id`, second with `job_id` returns networks). Live: overview finds the network from Task 3 with `poles >= 1`.
- [ ] **Group 2 PR**: `feat: power tools` (Tasks 3–4).

## Group 3 — research (branch `feature/research`)

### Task 5: `research_status` (sub `research`)

**Files:** Create `scripts/commands/research.lua`, `scripts/logic/research_logic.lua`, `server/factorio_mcp/tools/research.py`; tests `mod/tests/research_logic_test.lua`, `server/tests/test_tools_research.py`, `server/tests/live/test_research_live.py`.

**Interfaces:**
- Mod params: `{caller, name?, offset?, limit?}` (`limit` default 20, max 50).
- Produces: `research_logic.available(technologies) -> [name]` (enabled, not researched, all prerequisites researched; sorted by name), `research_logic.state(tech) -> {name, level, researched, enabled, progress, unit_count, ingredients: [{name, amount}], missing_prerequisites: [name]}`.
- Answer without `name`: `{current: {name, level, progress} | null, queue: [name], researched, total, available: {total, offset, items: [name], next}}`. With `name`: `research_logic.state` of that technology (`not_found` if unknown).

- [ ] **Steps (shared shape).** Lua: 2,000 fake technologies → `available` page of 20 with `next == 20`, answer under budget; a tech with one unresearched prerequisite lists it in `missing_prerequisites`. Service: `test_research_overview`, `test_research_by_name`, `test_research_unknown_name`. Live: `/sc` `game.forces.player.add_research("automation")` in setup (dev server only), then `current.name == "automation"`.
- [ ] **Group 3 PR**: `feat: research status tool`.

## Group 4 — threats, pollution, base defenses (branch `feature/threats`)

### Task 6: `inspect_threats` (sub `threats`, job kind `threats`)

**Files:** Create `scripts/commands/threats.lua`, `scripts/logic/threats_logic.lua`, `server/factorio_mcp/tools/threats.py`; modify `job_kinds.lua`; tests `mod/tests/threats_logic_test.lua`, `server/tests/test_tools_threats.py`, `server/tests/live/test_threats_live.py`.

**Interfaces:**
- `threats_logic.ENEMY_TYPES = {"unit-spawner", "turret", "segmented-unit"}`; enemy = force for which `caller_force.is_enemy(entity.force)` is true (falls back to force name `enemy`).
- `threats_logic.collect(acc, entity, center, surface)` / `threats_logic.finish(acc, limit) -> {counts: {name -> n}, nearest: [{name, type, distance, direction, gps, pollution}]}` (nearest first; `pollution = surface.get_pollution(position)` for spawners only).
- Demolishers: `surface.get_segmented_units()` filtered by enemy force and radius, added as type `segmented-unit`.
- Mod params: `{caller, player?} | {caller, surface, x, y}`, `radius?` (default 128, max 256 synchronously), `limit?` (default 10, max 30). Job kind `threats` takes `{force, surface, x, y, radius (≤ 1000), limit}` and reuses the same logic via `scan_area` with filter `{type = ENEMY_TYPES, force = <enemy force names>}`.
- Tool: `inspect_threats(gps=None, player=None, radius=128, limit=10, job_id=None)`; radius > 256 → job path (like `inspect_area`).

- [ ] **Steps (shared shape).** Lua: a nest 100 tiles north → `direction == "N"`, `distance` 100; a player-force turret is never counted. Service: sync path command, job path above 256, `test_threats_offline_caller_needs_gps`. Live: `/sc` create `biter-spawner` and `medium-worm-turret` on force `enemy` 150 tiles away, assert both in `nearest`; on `SPACE_AGE=true`, Vulcanus demolisher check is skipped if the surface has none (documented skip).

### Task 7: `inspect_pollution` (sub `pollution`)

**Files:** Create `scripts/commands/pollution.lua`, `scripts/logic/pollution_logic.lua`, tool in `server/factorio_mcp/tools/threats.py`; tests `mod/tests/pollution_logic_test.lua`, service test, live test in `test_threats_live.py`.

**Interfaces:**
- Mod params: `{caller, player?} | {caller, surface, x, y}`, `grid?` (odd, default 9, max 15 chunks per side), `limit?` (default 10).
- Produces: `pollution_logic.grid(sample(x, y) -> number, center, grid) -> [{x, y, amount}]` (chunk centres), `pollution_logic.top(cells, limit)`.
- Answer: `{surface, pollutant, total, center, grid, top_cells: [{gps, amount}], sources: [{name, per_minute}] (game.get_pollution_statistics(surface), top 10), fed_spawners: [{name, gps, amount}]}` (enemy spawners inside the grid in chunks with pollution > 0).

- [ ] **Steps (shared shape).** Lua: a fake sampler with one hot chunk → it is `top_cells[1]`; grid 4 → `bad_params` (must be odd). Service: defaults and gps. Live: on `SPACE_AGE=true`, `pollutant` on Gleba is `spores` (skip if the dev save has no Gleba surface); on nauvis `pollutant == "pollution"`.

### Task 8: `base_defenses_overview` (job kind `defenses_overview`)

**Files:** Modify `job_kinds.lua`, `scripts/logic/defenses_scan.lua` (split per-entity record from scan: `defenses_scan.record(entity) -> record|nil`, `defenses_scan.new_acc(max_listed)`, `defenses_scan.add(acc, record)`, `defenses_scan.finish(acc)`; `M.scan` keeps its answer); tool in `server/factorio_mcp/tools/defenses.py`; tests `mod/tests/defenses_scan_test.lua` (still passes), `mod/tests/defenses_overview_test.lua`, service test, live test in `test_defenses_live.py`.

**Interfaces:**
- Kind `defenses_overview`, params `{force, surfaces?, max_listed?}`, filter `{type = defenses_scan.DEFENSE_TYPES, force = force}`; finish returns `{fields = {summary = {total, turrets, walls, other, issues}, by_surface = {surface -> {total, problems}}}, list_name = "problems", list = problems (worst first, each with gps)}`.
- Tool `base_defenses_overview(limit=25, offset=0, job_id=None)`.

- [ ] **Steps (shared shape).** Lua: two surfaces with one dry turret each → `issues.no_ammo == 2`, `by_surface` has both. Service: running then done. Live: the turrets from `test_defenses_real_shapes` appear in the overview problems.
- [ ] **Group 4 PR**: `feat: threats, pollution and base defenses overview` (Tasks 6–8).

## Group 5 — logistics, trains, platforms (branch `feature/logistics`)

### Task 9: `logistic_networks` (sub `logistics`)

**Interfaces:** mod params `{caller, surface?, name?, limit?}` (default 15, max 50). `logistics_logic.network(net) -> {surface, id, gps (first cell owner), roboports, logistic_robots: {available, total}, construction_robots: {available, total}, charging: (sum of to_charge_robot_count), top_contents: [{name, quality, count}]}`; with `name`: `{name, total, by_network: [{surface, id, count}]}`. Answer `{networks: [...], total}`, networks sorted by `available logistic robots / total` ascending.

- [ ] **Steps (shared shape).** Lua: a network with 0 robots does not divide by zero; contents capped at `limit`. Service: `test_logistics_default`, `test_logistics_by_name`, `test_logistics_none` (no networks → `networks == []`). Live: roboport + storage chest with iron plates + 10 logistic robots via `/sc`; `top_contents` has iron-plate.

### Task 10: `list_trains` (sub `trains`)

**Interfaces:** mod params `{caller, surface?, problems_only?, offset?, limit?}` (default 15, max 50). `trains_logic.record(train) -> {id, group, state, surface, gps (front stock), station | target, waiting_ticks, cargo: [{name, count}] (top 5), fluids: [{name, amount}], problem: string|nil}`; problem states `no_path`, `no_schedule`, `destination_full`, `manual_control` with cargo, waiting at a station longer than 5 minutes (`get_schedule().ticks_in_station > 18000`). Answer `{by_state: {state -> n}, total, problems_total, trains: page (problems first), next}`. Only `get_schedule()` getters (`current`, `ticks_in_station`, `get_records`) are used; passengers are never read.

- [ ] **Steps (shared shape).** Lua: 500 fake trains → page of 15, `next == 15`, answer under budget; `no_path` sorts before `on_the_path`. Service: `test_trains_default`, `test_trains_problems_only`. Live: locomotive + wagon on a rail with no schedule → state `no_schedule` (or `manual_control`, whichever the game reports) listed as a problem.

### Task 11: `list_platforms` (sub `platforms`)

**Interfaces:** mod params `{caller, name?, limit?}`. `platforms_logic.record(platform) -> {name, state, location | null, last_location, speed, distance, damaged_tiles, hub_contents: [{name, count}] (top 10)}`. Answer `{platforms: [...], total}`; no Space Age or no platforms → `platforms == []`.

- [ ] **Steps (shared shape).** Lua: state names come from the reverse table of `defines.space_platform_state`. Service: `test_platforms_none`, `test_platforms_by_name`. Live (`SPACE_AGE=true`): create a platform via `/sc` `game.forces.player.create_space_platform{name="test", planet="nauvis", starter_pack="space-platform-starter-pack"}`, assert it is listed.
- [ ] **Group 5 PR**: `feat: logistic networks, trains and platforms` (Tasks 9–11).

## Group 6 — personal and local details (branch `feature/local-details`)

### Task 12: `my_inventory` (sub `inventory`) and `my_alerts` (sub `alerts`)

**Interfaces:**
- `inventory`: params `{caller}` only. Answer `{online, main: [{name, quality, count}] (sorted by count), armor: {name, equipment: [{name, count}]} | null, guns: [name], ammo: [{name, count}], crafting_queue_size}`; when unreadable `{online: false, readable: false}`.
- `alerts`: params `{caller, limit?}` (default 5 per type). Answer `{online, by_type: [{type, count, examples: [{name, gps}]}]}` from `player.get_alerts{}` (type names from `defines.alert_type` reverse table).
- Tools `my_inventory()` and `my_alerts(limit=5)` take **no player argument**; the service sends `caller_args()` only.

- [ ] **Steps (shared shape).** Service tests: `test_my_inventory_uses_token_nick_only` (the command is exactly `{"caller":"aliceNick"}` and the tool schema has no `player` property), same for alerts with Bob's token. Live: the dev server has no connected player, so the live test checks the offline answer: an unknown caller gives `not_found`, and an existing offline player gives the documented offline shape (whichever of `readable: false` or the inventory the game allows, found in Step 9 and then asserted); document it in `docs/protocol.md`.

### Task 13: `inspect_resources` (sub `resources`)

**Interfaces:** mod params `{caller, player?} | {caller, surface, x, y}`, `radius?` (default 64, max 128), `limit?` (default 10). `resources_logic.patches(entities) -> [{name, amount, tiles, gps (centre), fluid (bool)}]` (connected chunks of the same resource merged; for fluid resources such as crude oil, `fluid = true` and `amount` is the raw entity amount summed, plus `wells` = entity count; no yield conversion). Answer `{center, radius, patches (largest first), surface_totals: get_resource_counts()}`.

- [ ] **Steps (shared shape).** Lua: two iron fields in chunks 3 apart → two patches; adjacent chunks → one. Service: defaults and gps. Live: vanilla nauvis around spawn has iron-ore within 128 tiles (generate chunks first) → a patch with `amount > 0`.

### Task 14: `inspect_transport` (sub `transport`)

**Interfaces:** `transport_logic.TYPES = {"transport-belt", "underground-belt", "splitter", "loader", "loader-1x1", "inserter", "pipe", "pipe-to-ground", "pump", "storage-tank"}` (separate allowlist; `area_scan.AREA_TYPES` unchanged). Mod params `{caller, player?} | {caller, surface, x, y}`, `radius?` (default 16, max 32), `limit?` (default 15). Answer `{center, radius, counts: {name -> n}, inserters: {by_status, stuck: [{name, gps, status}]}, belts: {items: [{name, count}]} (from transport lines, top 10), fluids: [{name, amount}] (pipes and tanks, summed by fluid)}`. Stuck statuses: `waiting_for_source_items`, `waiting_for_space_in_destination`, `no_power`, `low_power`.

- [ ] **Steps (shared shape).** Lua: allowlist excludes `car`, `character`, `spider-vehicle`, `cargo-wagon` (privacy test as in `area_scan_test.lua`); a stuck inserter is listed first. Service: defaults. Live: a belt with iron plates and an inserter feeding a full chest → inserter in `stuck`, belt items include iron-plate.
- [ ] **Group 6 PR**: `feat: own inventory and alerts, resources, transport` (Tasks 12–14).

## Release

### Task 15: Measurements on the real save and docs

**Files:** Modify `docs/measurements.md`, `README.md` (check all 15 rows), `docs/protocol.md` (check all rows).

- [ ] **Step 1:** Ask the owner whether they are playing; only then run `nice -n 15 scripts/profile-save.sh` on a copy of the real save.
- [ ] **Step 2:** Measure each synchronous command at its max radius/limit (ms per call, answer bytes) and each new job kind (wall time, UPS during the run) with the method already in `docs/measurements.md`. Expected: every synchronous call under 5 ms, every answer under 48,000 bytes (typical under 12 KB), whole-base jobs in seconds at 60 UPS. If `inspect_threats` at 256 exceeds 5 ms, lower its sync cap to 128 (constant in `threats.lua` and the tool) and note it.
- [ ] **Step 3:** Write the numbers to `docs/measurements.md`; branch `docs/measurements-0.4.0`, PR, merge.

### Task 16: Release PR 0.4.0

- [ ] **Step 1:** On `main`: `python3 scripts/bump_version.py minor -c` → branch `release/v0.4.0`.
- [ ] **Step 2:** Rewrite `mod/factorio-mcp/changelog.txt` 0.4.0 entry and `RELEASE_NOTES_0.4.0.md` by hand (one line per tool, update steps as in 0.3.0); hygiene; amend; push; open PR `Bump version to 0.4.0`.
- [ ] **Step 3:** Ask the owner for a yes; merge; verify tag `v0.4.0`, GHCR tag `0.4.0`, mod portal `0.4.0`; give the owner the deploy commands; update the vault note and memory.
