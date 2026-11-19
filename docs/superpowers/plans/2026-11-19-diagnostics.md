# Diagnostics Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (inline, no subagents, TDD) to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add seven read-only capabilities to 0.4.0: mining-drill depletion, unmet logistic requests, server UPS, research bonuses, train-station limits, kill/build statistics, and MCP prompts. Event history (`recent_events`) is postponed by the owner (2026-11-19): no background handler for now.

**Architecture:** Same shape as 0.4.0: one mod subcommand per capability (`mod/factorio-mcp/scripts/commands/*.lua` over pure `logic/*.lua`), a service tool or tool parameter (`server/factorio_mcp/tools/*.py`), heavy work as tick-split jobs. There is no new background code: the mod stays idle apart from job ticks and the chunk-block bookkeeping.

**Tech Stack:** Lua 5.2 (Factorio 2.1.24), Python 3.13 + `mcp` 2.3.0, pytest, luacheck/ruff in CI.

**Spec:** the owner's note `projects/homelab/factorio-mcp.md` ("Наступне: що додаємо"), the owner's rules in the task message of 2026-11-19, and "Live API findings" below.

## Global Constraints

- Game never lags: a synchronous command stays at about 2 ms in game; heavy work is a job whose single tick stays at about 2.5 ms; every new command is measured at its worst spot and written into `docs/measurements.md`.
- The mod only reads (static test `server/tests/test_readonly_static.py`, which also forbids `.set_*(`). Storage is written only for job state (and the existing chunk-block map).
- Other players' inventories and characters' requests are never shown.
- `tools/list` stays at or under 12,000 bytes (`server/tests/test_tools_registry.py`). New capabilities are parameters of existing tools where possible; trim descriptions before asking to raise the limit.
- Commits and PR texts carry no assistant attribution; one PR per group; merge on green CI is a standing yes; release and deploy only with the owner's separate yes. No version bump in these PRs.
- Test command: `bash -c 'scripts/test-mod.sh >/dev/null && cd server && .venv/bin/python -m pytest -q'`; lint: `cd server && .venv/bin/ruff check .`, `scripts/check-hygiene.sh`.
- Live runs: `nice -n 15 scripts/profile-save.sh` on the copy of the save; back up `dev/profile/fha-save-2026-11-13.zip` first (sha1 `ec91886a3b78854988eb389400051183cd21a5de`) and restore it after.

## Live API findings (2.1.24, checked 2026-11-19 on the save copy)

- **Died events (not used now; kept for a later `recent_events`).** `script.on_event(defines.events.on_entity_died, f, filters)` accepts `{filter="force", force="enemy", invert=true}`, `{… "neutral" …, mode="and"}`, `{filter="ghost", invert=true, mode="and"}`, `{filter="type", type="character", invert=true, mode="and"}`. Result: fired for a wall, gun turret and car of force `player`; not for a biter, a tree or a ghost. The filter's `force` is the dead entity's force; `event.force` is the killer's force. `event.cause` is an entity or nil; `damage_type` is nil for script kills. Cost about 1 µs per death over the death itself (300 deaths: 10.3 ms with the handler, 9.3 ms without).
- **Statistics.** `force.get_kill_count_statistics(surface)`: `input_counts` = enemies the force killed (medium-biter 42,418), `output_counts` = the force's own entities lost (stone-wall 7,616); both rise by one per death (checked: +2 and +2). `get_entity_build_count_statistics(surface)`: `input` = built, `output` = removed (mined or deconstructed). Script-created entities do not count as built. Flow queries use the production code's `get_flow_count{name, category, precision_index, count=false}` (per minute) with a quality per name.
- **Force modifiers** (read, all plain numbers): `laboratory_speed_modifier`, `laboratory_productivity_bonus`, `mining_drill_productivity_bonus`, `worker_robots_speed_modifier`, `worker_robots_storage_bonus`, `worker_robots_battery_modifier`, `inserter_stack_size_bonus`, `bulk_inserter_capacity_bonus` (2.1 name), `belt_stack_size_bonus`, `train_braking_force_bonus`, `maximum_following_robot_count`, `following_robots_lifetime_modifier`, `artillery_range_modifier`, `beacon_distribution_modifier`, `manual_mining_speed_modifier`, `manual_crafting_speed_modifier`, `character_*` bonuses; `get_ammo_damage_modifier(cat)` and `get_gun_speed_modifier(cat)` for each key of `prototypes.ammo_category`; `get_turret_attack_modifier(turret_name)`.
- **Train stops.** `game.train_manager.get_train_stops{force, surface?, is_full?, is_disabled?, station_name?}` works; the filter calls cost 0.01 ms for 72 stops; `trains_limit` is `4294967295` when unlimited; `trains_count` includes the stopped train; `get_stopped_train()` returns the train or nil. In this save 6 of 72 stops are full, none disabled.
- **Logistic requests.** `network.requester_points[i]`: `.owner` (entity), `.mode` (3 = requester), `.enabled`, `.exact`, `.filters` (array of `{index, name, quality, comparator, count, max_count?}`), `.sections`. Owner types seen: `logistic-container`, `rocket-silo`, `car`, `spider-vehicle`. `owner.get_item_count{name, quality}` gives what a requester holds; `net.get_contents()` gives the network's stock (0.2 ms). Reading 417 points / 662 filters took **4.5 ms in one tick** (6.8 µs per filter): too slow for a synchronous answer, so it is a job.

## Decisions that change behaviour or API (for the owner's review)

0. **Postponed:** event history and its `on_entity_died` / `on_player_died` handler. Nothing new runs in the background.
1. **One new tool:** `base_mining_overview(surfaces=None, job_id=None, limit=25, resource=None)`.
2. **New parameters on existing tools (4):** `server_status(performance=false)` (service samples a new tiny mod command `clock` twice, 1 s apart, so the call takes about 1 s), `research_status(bonuses=false)`, `list_trains(stations=false)`, `production_stats(kind="items"|"kills"|"builds")`.
3. **Logistic requests are a mode of `logistic_networks`:** `requests=true` (+ `job_id`) runs job kind `logistic_requests`. Requester points owned by characters and by vehicles (`car`, `spider-vehicle`, any `character`) are counted but never listed.
4. **Wording in answers:** kills use `killed` (enemies you killed) and `lost` (your entities lost); builds use `built` and `removed`.
5. **MCP prompts (3):** `base_checkup`, `why_stopped` (argument `gps`), `whats_missing` (optional argument `item`). Static texts naming the tools to call; they cost no tool-list context.
6. **Mod command names (internal):** `clock` is the only new command; new job kinds `mining_overview`, `logistic_requests`; extended subcommands `research`, `trains`, `production`.

## Review Focus

- Mining drill with no `mining_target` (already depleted) and a pumpjack on a fluid resource must give sensible rows, not errors (Task 1).
- A requester that holds more than it asks for must not count as missing; an unlimited train stop must not show a huge number (Tasks 2, 4).
- Offline caller / unknown caller on every new caller-based command answers the same `not_found` as the existing ones (Tasks 2, 4).
- `server_status(performance=true)` on a paused game (auto-pause, no players) must say "paused", not "0 UPS" as if broken (Task 3).

## File Structure

- Create `mod/factorio-mcp/scripts/logic/mining_logic.lua`, `logic/requests_logic.lua`, `logic/bonuses_logic.lua`, `commands/clock.lua`; tests in `mod/tests/*_test.lua` with the same names.
- Modify `logic/job_kinds.lua` (two kinds), `commands/{research,trains,production}.lua`, `logic/{trains_logic,production_logic}.lua`.
- Create `server/factorio_mcp/tools/prompts.py`; modify `tools/{overview,logistics,research,production,server}.py`, `app.py`, `instructions.py`; tests `server/tests/test_tools_*.py`, `server/tests/test_prompts.py`, live tests `server/tests/live/test_diagnostics_live.py`.
- Docs: `README.md`, `docs/protocol.md`, `docs/measurements.md`.

---

## Group 7: Mining depletion (PR "feat: base_mining_overview")

### Task 1: `mining_overview` job and tool

**Files:** Create `logic/mining_logic.lua`, `mod/tests/mining_logic_test.lua`; Modify `logic/job_kinds.lua` (planner `plan_mining_overview`, stepper `mining_overview`), `tools/overview.py`; Test `server/tests/test_tools_mining.py`, `server/tests/live/test_diagnostics_live.py` (mining case); Modify `docs/measurements.md`, `docs/protocol.md`, `README.md`.

**Interfaces:**
- Produces: `mining_logic.new_acc(keep)`, `mining_logic.record(entity, surface) -> {name, resource, remaining, depleted, x, y, fluid}` (remaining = sum of `amount` of resources of `mining_target.name` within `entity.prototype.mining_drill_radius`; `depleted = true` and `remaining = 0` when `mining_target` is nil or `status` is `no_minable_resources`; for fluid resources `remaining` is the yield percent), `mining_logic.add(acc, record, surface_name)`, `mining_logic.finish(acc) -> {summary, groups, worst}` (groups per surface + resource: drills, depleted, low, total_remaining; `worst` = depleted first then least remaining, capped at `keep`, each with `gps`).
- Job kind `mining_overview`, params `{caller, surfaces?, limit? (1..100, default 25)}`; scans type `mining-drill` filtered by the caller's force with `entity_cost` set from the measurement. "Low" = remaining under 5,000 ore (constant `LOW_REMAINING`).
- Tool `base_mining_overview(surfaces, job_id, limit, resource)` requires `job_start`; `resource=` limits the list to one resource name.

- [ ] **Step 1: Failing Lua tests** with fake drills: normal drill sums only same-name resources inside the radius; nil `mining_target` → depleted; fluid resource → percent; ordering of `worst`; groups sorted by `depleted` then `total_remaining`.
- [ ] **Step 2: Run, implement** logic, planner, stepper (`scan_area` with `{type = {"mining-drill"}, force = force.name}`; `entity_cost` measured in Step 5), tests green.
- [ ] **Step 3: Failing Python tests** (fake RCON) for the tool: visibility, paging/limit, `resource=` filter, `running` + `job_id` passthrough, normalization.
- [ ] **Step 4: Implement** the tool in `tools/overview.py`; tests green; context ≤ 12,000 bytes.
- [ ] **Step 5: Live + measure:** run the job in `ticks` mode on the save copy (`.superpowers/.../jobsteps.py`-style per-tick timing); cost model: choose `entity_cost` so the worst tick stays at about 2.5 ms; also build the worst case on the copy (a 30×30 block of big drills on a solid ore field). Record in `docs/measurements.md`: `job_start`, ticks, median/max tick, wall time, accuracy against a direct sum for 3 drills.
- [ ] **Step 6: Docs + commit** `feat: base_mining_overview`; open the PR for Group 7.

---

## Group 8: Unmet logistic requests (PR "feat: logistic requests")

### Task 2: `logistic_requests` job and `logistic_networks(requests=true)`

**Files:** Create `logic/requests_logic.lua`, `mod/tests/requests_logic_test.lua`; Modify `logic/job_kinds.lua`, `tools/logistics.py`; Test `server/tests/test_tools_logistics.py`, `server/tests/live/test_diagnostics_live.py`; Modify `docs/measurements.md`, `docs/protocol.md`.

**Interfaces:**
- Produces: job kind `logistic_requests`, params `{caller, surfaces?, limit? (1..30, default 10)}`; plan: for each network of the caller's force, work items `(surface_index, network_id, offset, 32)` of at most `REQUESTS_PER_ITEM` requester points (about 100 points; fixed after measuring) so one item stays near 1 ms; the stepper re-reads `net.requester_points` per item.
- `requests_logic.new_acc()`, `requests_logic.add_point(acc, network_key, point_view)` where `point_view = {owner_type, enabled, filters = {{name, quality, count}}, held = function(name, quality) -> n}`; points whose `owner_type` is `character`, `car` or `spider-vehicle` are only counted (`skipped_personal`), disabled points counted (`disabled`); `requests_logic.finish(acc, stock_by_network)` → per network `{surface, id, requesters, skipped_personal, disabled, unmet = top {name, quality, requested, held, missing, requesters_short, requesters, stock, state}}` where `state` = `no_stock` (stock 0), `short` (stock < missing), `deliverable`; `missing = sum(max(0, count - held))`; ordered `no_stock` first, then by `missing`.
- Tool: `logistic_networks(surface=None, name=None, limit=15, requests=False, job_id=None)`; with `requests=true` the answer is the job's result with the same normalization as other job tools.

- [ ] **Step 1: Failing Lua tests:** holder with more than asked → missing 0; two requesters of one item sum; `no_stock` vs `short` vs `deliverable`; character/vehicle points counted but never listed (no names from them in the output); disabled point ignored for missing; ordering and `limit`.
- [ ] **Step 2: Implement** logic + planner + stepper; tests green.
- [ ] **Step 3: Failing Python tests** for the tool (visibility of the parameter path, passthrough, normalization, that the sync path without `requests` is unchanged).
- [ ] **Step 4: Implement** the tool; all tests green; context check.
- [ ] **Step 5: Live + measure** on the save copy (network 2: 417 points, 662 filters): per-tick times in `ticks` mode, `job_start`, wall time; a unit check that for 3 items `held` equals a direct `owner.get_item_count` sum; confirm no character points are listed. Fix `REQUESTS_PER_ITEM` so max tick ≤ 2.5 ms. Record numbers.
- [ ] **Step 6: Docs + commit** `feat: unmet logistic requests`; open the PR for Group 8.

---

## Group 9: Parameters of existing tools (PR "feat: server performance, bonuses, stations, kill and build stats")

### Task 3: `server_status(performance)`, `research_status(bonuses)`

**Files:** Create `commands/clock.lua`, `logic/bonuses_logic.lua`, `mod/tests/bonuses_logic_test.lua`; Modify `commands/research.lua`, `tools/server.py`, `tools/research.py`, `bridge.py` only if a new command name needs registration; Test `server/tests/test_tools_server_players.py`, `server/tests/test_tools_research.py`.

**Interfaces:**
- Produces: mod command `clock` → `{tick, speed, paused, players_online}` (no params); `bonuses_logic.collect(force, ammo_categories, turret_names) -> {force = {name -> value}, ammo = {category -> {damage, speed}}, turrets = {name -> bonus}}` keeping only non-zero values; `research` takes `bonuses = true` and then returns the `bonuses` block instead of the available list.
- Service: `server_status(details=False, performance=False)`; with `performance` it calls `clock` twice, waiting 1.0 s (asyncio) between the replies, and adds `performance = {ups, speed, target_ups = 60 * speed, state = "running"|"paused"|"slow"}`; `ups = Δtick / Δwall seconds` rounded to 0.1, `state = "paused"` when the tick did not move and `players_online == 0`.

- [ ] **Step 1: Failing tests:** Lua — zeros dropped, `bulk_inserter_capacity_bonus` read, ammo categories reported only when non-zero, a nil-valued field (mod without it) skipped; Python — fake clock replies give `ups`, a stuck tick with no players gives `paused`, a stuck tick with players gives `state = "stalled"`, the second call is awaited after ≥ 1 s (use an injectable sleep).
- [ ] **Step 2–4:** implement, run, green.
- [ ] **Step 5: Commit** `feat: server UPS and research bonuses`.

### Task 4: `list_trains(stations)`, `production_stats(kind)`

**Files:** Modify `commands/trains.lua`, `logic/trains_logic.lua`, `commands/production.lua`, `logic/production_logic.lua`, `tools/logistics.py`, `tools/production.py`; Tests `mod/tests/trains_logic_test.lua`, `mod/tests/production_logic_test.lua`, `server/tests/test_tools_logistics.py`, `server/tests/test_tools_production.py`.

**Interfaces:**
- `trains` takes `stations = true`: returns `{stations = {total, full_total, disabled_total, list = {…}}}` and no train list; `trains_logic.stations(stops_full, stops_disabled, all_count, limit)` builds rows `{name, surface, gps, stops, trains_count, trains_limit (nil when ≥ 4294967295), disabled, state}` grouped by station name from the filtered stop lists only (`get_train_stops{force, is_full=true}`, `{is_disabled=true}`), order: limit 0, disabled, then most `trains_count`; `limit` default 15.
- `production` takes `kind = "items" | "kills" | "builds"` (default `items`, answer unchanged); `kills` → `{kind, window, surfaces, killed = [{name, per_minute, total}], lost = [...]}` from `get_kill_count_statistics` (`input` = killed, `output` = lost); `builds` → `built` / `removed` from `get_entity_build_count_statistics`; qualities summed as in `production_logic.rates`; `name=` works for one entity name; top `limit`.

- [ ] **Step 1: Failing tests:** stations — unlimited stop shows `trains_limit = nil`, limit-0 stop first, two stops with one name are one row with `stops = 2`, a disabled stop marked; production — `kills` maps input/output to `killed`/`lost`, `builds` to `built`/`removed`, unknown `kind` → `bad_params`; Python — parameter passthrough and normalization, default calls unchanged (existing tests stay green).
- [ ] **Step 2–4:** implement, run, green; context ≤ 12,000 bytes after Group 9.
- [ ] **Step 5: Live + measure** on the save copy: `trains stations=true` (72 stops), `research bonuses=true`, `clock`, `production kills/builds` at 10h and limit 50 — each ≤ 2 ms; calibrate in a live test that one script-killed biter changes `killed` and one killed own wall changes `lost` (as measured today). Record numbers.
- [ ] **Step 6: Commit** `feat: train station limits and kill/build statistics`; open the PR for Group 9.

---

## Group 10: Prompts and wrap-up (PR "feat: MCP prompts")

### Task 5: Three prompts, instructions, final checks

**Files:** Create `server/factorio_mcp/tools/prompts.py`, `server/tests/test_prompts.py`; Modify `app.py`, `instructions.py`, `README.md`, `docs/measurements.md`; Test `server/tests/test_tools_registry.py`.

**Interfaces:**
- `prompts.register(mcp)` adds `base_checkup()`, `why_stopped(gps: str)`, `whats_missing(item: str = "")`, each returning one user message that tells Claude which tools to call in which order and how to report (short, with `[gps]`). `base_checkup`: `base_machines_overview`, `base_power_overview`, `base_defenses_overview`, `base_mining_overview`, `list_trains(problems_only)`, `logistic_networks`; `why_stopped`: `inspect_area` at the gps then `inspect_power`, `inspect_transport`, `inspect_resources`; `whats_missing`: `production_stats` deficits, `logistic_networks(requests=true)`, `research_status`, `game_reference` for the item's recipe.

- [ ] **Step 1: Failing tests:** `prompts/list` returns the three names; `prompts/get` for each returns text that mentions only tools that exist (checked against the registry's full spec list); `why_stopped` without `gps` is rejected by the SDK; the token gate still protects `prompts/list`.
- [ ] **Step 2–4:** implement, run, green.
- [ ] **Step 5: Final pass:** `tools/list` byte count recorded in the ledger; README tool table updated for 22 tools and 3 prompts; `docs/measurements.md` has a section "History and diagnostics (0.4.0)" with every number; full test command, ruff, hygiene.
- [ ] **Step 6: Live regression:** full `scripts/live.sh` on the save copy (back up first, restore after); confirm job UPS 59.7–60.0.
- [ ] **Step 7: Commit** `feat: MCP prompts and docs`; open the PR for Group 10. Do not release.
