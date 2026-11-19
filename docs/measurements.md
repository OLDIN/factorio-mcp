# Measurements

## Environment

Tool versions on the development machine (macOS).

| Tool | Version | Notes |
|---|---|---|
| Factorio (game and API docs) | 2.1.24 | runtime API reference: `runtime-api.json` shipped with the game |
| Lua | 5.5.1 | local interpreter; Factorio embeds Lua 5.2, so tests stay 5.2-compatible and CI runs `lua5.2` |
| luacheck | not installed locally | runs in CI (`lua-check` package) |
| uv | 0.10.0 | `/opt/homebrew/bin/uv` |
| Python | 3.13.5 | service requires >= 3.13 (local venv runs 3.15) |
| ruff | 0.14.13 | same version as CI |
| Docker | 27.5.1 | |

---

## 1. RCON Response Sizing & Packet Fragmentation

Measurements taken over a live TCP connection to Factorio 2.1.24 RCON (port 27015):

| Requested Size | Packets Received | Total Bytes Received | Payload Matches | Notes |
|---|---|---|---|---|
| 1,024 B (1 KB) | 1 | 1,025 B | Yes | Single packet; trailing `\n` appended by `rcon.print` |
| 4,096 B (4 KB) | 1 | 4,097 B | Yes | Single packet; no fragmentation at standard 4 KB boundary |
| 65,536 B (64 KB) | 1 | 65,537 B | Yes | Single packet |
| 1,048,576 B (1 MB) | 1 | 1,048,577 B | Yes | Single packet; length prefix = 1,048,587 |
| 2,097,152 B (2 MB) | 1 | 2,097,153 B | Yes | Single packet; length prefix = 2,097,163 |
| 4,194,304 B (4 MB) | 1 | 4,194,305 B | Yes | Single packet; length prefix = 4,194,315 |

### Findings & Architecture Decision
- **No multi-packet splitting:** Unlike Valve's original Source RCON implementation (which chunks output into ~4 KB slices terminated by an empty packet), Factorio sends the entire response in a single RCON packet with an exact 32-bit length prefix.
- `RconLink.exec` successfully reads and parses responses up to multi-megabyte sizes in one call without requiring multi-packet assembly logic.
- `rcon.print(...)` automatically appends a trailing newline (`\n`), which `RconLink` or JSON decoders handle transparently.
- **Budget Decision:** `RESPONSE_BUDGET_BYTES` in `limits.lua` is set to **48,000 bytes** (~47 KB). This allows hundreds of entity records or prototypes per page while remaining well within single-packet limits and maintaining fast serialization with low frame impact.

---

## 2. Lua API: `helpers.json_to_table` Behavior

Tested with various valid, malformed, and adversarial inputs in Factorio 2.1.24:

| Input | `pcall` Status | Return Value | Type | Behavior |
|---|---|---|---|---|
| ` "{" ` | `true` | `nil` | `nil` | Syntax error safely returns `nil` without raising Lua error |
| ` "{\"a\":" ` | `true` | `nil` | `nil` | Unclosed object returns `nil` |
| ` "\"x\"" ` | `true` | `"x"` | `string` | Top-level string parsed correctly |
| ` "null" ` | `true` | `nil` | `nil` | JSON null maps to Lua `nil` |
| ` "[1," ` | `true` | `nil` | `nil` | Unclosed array returns `nil` |
| 100 KB random garbage | `true` | `nil` | `nil` | Arbitrary garbage returns `nil` with no crash or hang |
| 500-level nested arrays | `true` | `{...}` | `table` | Deep nesting parsed without stack overflow |

### Finding
`helpers.json_to_table` does not throw Lua exceptions on malformed syntax or garbage; it safely evaluates and returns `nil`. Wrapping with `pcall` in `dispatcher.lua` remains good defensive programming.

---

## 3. Server State & Offline Players (`AUTO_PAUSE=true`)

Tested on real save with 3 offline players and zero connected players:

- **Offline player attributes:**
  - `player.connected`: `false`.
  - `player.character`: `nil` for all offline players.
  - `player.physical_position`: accessible and returns a valid `MapPosition` table `{x, y}`.
  - `player.physical_surface`: accessible and returns a valid `LuaSurface`.
  - `player.position` and `player.surface`: match `physical_position` and `physical_surface`.
  - **Policy decision for Task 5 (`format_player`):** Even though `physical_position` is readable for offline players in Lua, user-facing MCP tools will enforce `position = null` and `surface = null` when `online = false` to preserve privacy and match protocol specifications.
- **Auto-pause behavior:**
  - `game.tick_paused`: `false` (Factorio's engine pauses execution at the loop level rather than setting the Lua-level flag).
  - `game.speed`: `1`.
  - `connected_players`: `0`.
  - `game.tick`: advanced by 1 tick over 2 seconds (only ticked during command execution). Simulation is frozen.
  - RCON responds immediately and reliably when the server is auto-paused.

---

## 4. Entity Search Profiling & Real Save Topology

Measured on the real save around the main production facility on `nauvis` (`x = -2071, y = -906`).

Allowlist for machine queries: `assembling-machine`, `furnace`, `lab`, `mining-drill`, `rocket-silo`, `agricultural-tower`.

Timings measured with `helpers.create_profiler()` averaged over 10 iterations:

| Radius (tiles) | Machine Count Found | Query Time | Evaluation |
|---|---|---|---|
| R = 32 | 39 | **0.020 ms** | Instantaneous (< 0.15% frame budget) |
| R = 64 | 101 | **0.059 ms** | Negligible (< 0.35% frame budget) |
| R = 128 | 164 | **0.190 ms** | Well below 0.5 ms budget |
| R = 256 | 164 | **0.352 ms** | Whole factory area; safe to run directly |

### Conclusion for Area Diagnostics (Task 10)
- Querying a 32-64 tile radius around a player or GPS coordinate takes under 0.06 ms.
- Default search radius for `inspect_area`: **32 tiles** (with support for up to 64-128 tiles without frame drops).

### Surface Chunk Distribution
Iterated via `surface.get_chunks()`:

| Surface | Generated Chunks | Notes |
|---|---|---|
| `nauvis` | 26,099 | Primary planet base |
| `gleba` | 7,238 | Planetary outpost |
| `vulcanus` | 5,418 | Planetary outpost |
| `fulgora` | 5,202 | Planetary outpost |
| `aquilo` | 2,778 | Planetary outpost |
| `platform-1` .. `platform-10` | 156 to 1,425 | Space platforms |

### Entity Types with `.status` on Real Save
Scanning all entities across surfaces revealed 57 entity types that report a status:
`accumulator`, `agricultural-tower`, `ammo-turret`, `arithmetic-combinator`, `artillery-turret`, `artillery-wagon`, `assembling-machine`, `asteroid-collector`, `beacon`, `boiler`, `car`, `cargo-bay`, `cargo-landing-pad`, `cargo-wagon`, `constant-combinator`, `container`, `decider-combinator`, `electric-turret`, `fish`, `fluid-turret`, `fluid-wagon`, `furnace`, `fusion-generator`, `fusion-reactor`, `generator`, `heat-pipe`, `inserter`, `lab`, `lamp`, `land-mine`, `locomotive`, `logistic-container`, `mining-drill`, `offshore-pump`, `pipe`, `pipe-to-ground`, `power-switch`, `programmable-speaker`, `pump`, `radar`, `rail-chain-signal`, `rail-signal`, `reactor`, `roboport`, `rocket-silo`, `selector-combinator`, `solar-panel`, `space-platform-hub`, `spider-vehicle`, `splitter`, `storage-tank`, `thruster`, `train-stop`, `transport-belt`, `tree`, `turret`, `wall`.

The allowlist for workstation diagnostics in Task 10 (`assembling-machine`, `furnace`, `lab`, `mining-drill`, `rocket-silo`, `agricultural-tower`) covers the production machines while strictly avoiding vehicles, containers, or personal inventories.

## MCP SDK (`mcp` 2.3.0, checked against the installed source)

Pinned: `mcp==2.3.0`, `uvicorn==0.54.0` (starlette 1.10.0 comes with `mcp`). The SDK's client side uses `httpx2`, not `httpx`.

- **(a) HTTP mounting and auth.** `MCPServer.streamable_http_app(...)` returns a Starlette app with a `/mcp` route and a lifespan that runs the session manager. Its built-in auth is OAuth-oriented (`TokenVerifier`, `AuthSettings`), so we do not use it. Instead a small pure-ASGI gate (`app._Gate`) wraps the SDK app: `/health` without a token, `?token=` rejected with 400, bearer check with an identical 401 body, everything else forwarded (including lifespan scopes).
- **(b) Identity in a tool call.** The gate sets a `ContextVar` before calling the SDK app. In stateless mode the tool handler runs in the request's context, so `current_identity()` works (verified: the audit line carries the caller's name). Identity never comes from tool arguments.
- **(c) Dynamic tool list.** `MCPServer.add_tool` / `remove_tool` work at runtime, so the visible set follows the mod's `hello`. We run `stateless_http=True, json_response=True`, so every request is self-contained and a client re-lists tools; `tools/list_changed` notifications are not needed.
- **(d) DNS-rebinding protection.** `TransportSecuritySettings(allowed_hosts, allowed_origins)`; `allowed_hosts` entries match the `Host` header exactly or as `host:*`. The SDK enables it automatically for loopback binds only. We pass our own settings when `FACTORIO_MCP_ALLOWED_HOSTS` is set (each host is allowed with and without a port); a request with another `Host` gets 421, any `Origin` gets 403 (we have no browser clients). With an empty list and a non-loopback bind the protection is off, so deployments must set it.
- **(e) uvicorn access log.** `access_log=False` is not enough: uvicorn decides per connection via `Logger.hasHandlers()`, and its `dictConfig` re-enables loggers after construction. A mistaken `?token=` would land in the access log, so `uvicorn_config()` disables the `uvicorn.access` logger after building the config (covered by `test_token_and_rcon_password_never_logged`).

## End-to-end (M1)

- Official `mcp` client (Streamable HTTP, Bearer) against the service and a real Factorio 2.1.24: `server_status` returns the mod list (`base`, `factorio-mcp`), `list_players` returns a list; no token -> 401; token removed from the file -> 401 without restart (`server/tests/live/test_e2e_live.py`).
- Claude Code (`claude --mcp-config <temp json> --strict-mcp-config -p ...`) answered "who is online and which mods" from live data; the audit log showed `who=<name> tool=server_status`.
- Factorio 2.1.24 encodes an empty Lua table as `{}` (observed for `players`, not `[]`). The service therefore normalizes list fields with `bridge.normalize_lists`; fields that are maps use `normalize_maps`.

## Reference data (Task 9)

- Full cache fill over RCON on the real save with the full mod set (Space Age + 7 modded planets), pages capped at the 48000-byte budget: recipes 2951 (401 ms), machines 71 (19 ms), items 755 (68 ms), fluids 59 (12 ms), modules 40 (23 ms), qualities 6 (10 ms), technologies 508 (157 ms), planets 18 (12 ms). Vanilla + Space Age dev save: recipes 442 in 84 ms. The cache is filled once per mod-set fingerprint, so the cost is paid once.
- In Factorio 2.1.24 `get_crafting_speed` / `get_max_health` on an entity prototype need an explicit quality (`"normal"`): without one they raise `Invalid QualityID` although the docs mark it optional. Methods are bound: call `obj.method(args)`, never `obj.method(obj, args)`.
- Empty Lua tables are encoded as `{}` by `helpers.table_to_json`, so list fields come back as `{}` when empty; `ReferenceCache` normalizes them.

## Area diagnostics (Task 10)

- Entity allowlist: `assembling-machine`, `furnace`, `lab`, `mining-drill`, `rocket-silo`, `agricultural-tower` (the production types from the status scan above). `find_entities_filtered` is always called with exactly this `type` list, so characters, corpses, cars, spider vehicles, boats and modded vehicle types are never read (unit test `area_scan_test.lua`; live test puts a car with items and a dead character with items next to a machine and checks neither appears).
- Round trip on the real save (RCON included), around the first assembling machine, `max_listed = 20`: radius 32: 4 ms, 21 machines; 64: 19 ms, 68; 128: 16 ms, 158; 256: 20 ms, 164 (lists truncated at 20, totals complete, reply < 48000 bytes). Same order as the in-game scan costs measured in Task 4.
- Furnaces use the `crafter_input` / `crafter_output` inventories in 2.1 (no `furnace_source`).

## Tick-split jobs (Task 11)

- Real save (one loaded surface, `nauvis`): 26,099 chunks, 2,993 machines/labs/drills in 149 recipe groups. A full `machines_overview` in idle mode (512 chunks per poll) took 51 polls and 1.7 s wall, of which 51 x 16 ms is the RCON round trip (`job_status` measured at 16 ms): the scan itself is about 0.9 s, i.e. **~0.033 ms per chunk** on average (dense factory chunks cost more, empty ones almost nothing).
- Default `factorio-mcp-chunks-per-tick = 8`: ~0.27 ms per tick on average (criterion: <= 0.5 ms), a full-map scan of this save in ~3,300 ticks (~55 s at 60 UPS). The first guess of 2 per tick would take ~3.6 minutes. A worst case of 8 very dense chunks in a row is a few ms, still well inside the 16.7 ms frame. Idle default: `factorio-mcp-idle-chunks-per-poll = 512` (~17 ms of work per poll when nobody is online).
- Entities on chunk borders are counted once: a chunk step only keeps entities whose position is inside its half-open 32x32 square.
- `storage.mcp` holds plain data only: the chunk list is a flat number array (3 numbers per chunk, ~78k numbers for this save while a job runs, dropped when it finishes). Finished results live for 36,000 ticks and at most 8 are kept.
- Save/load in the middle of a job (`scripts/live-job-reload.sh`, copy of the real save, game running): the save made while the job ran restored the job and its `on_tick` handler through `on_load`, the job finished, the handler was removed, and the game log had no errors. This test also showed the dev save persisting job state between runs, which is why the live tests cancel leftover jobs first.
- Areas: radius up to 64 tiles is answered at once; larger radii (up to a sanity bound of 1000) run as a job (`area` kind) and the answer matches the synchronous scan (live test).


## Block-counting scan (replaces the chunk-by-chunk scan)

The first job design visited every generated chunk (8 per tick). On a real server with 16 surfaces a
whole-base overview took ~109 s with a player online, longer than an MCP client waits for a reply.
Measurements on the real save (nauvis, 26,099 chunks, 3,015 machines/drills):

- Game API costs: `get_chunks` over all chunks 23 ms (one-off at job start), `count_entities_filtered`
  of a 512x512 block 0.28 ms (about 1 us per chunk), of a single chunk 5 us, `find_entities_filtered`
  4.5 us per entity. The old job spent ~0.9 s because of its own Lua overhead (a closure and a
  `pcall` per read) and because 26k mostly empty chunks were each queried.
- New scan (count blocks, skip empty, split crowded, read small areas, one `pcall` per entity):
  165 blocks, **3.2 s** in `ticks` mode at 50 units per tick (was ~55 s), **77 ms** in `idle` mode
  (was 1.7 s). About 6.5 microseconds per work unit, so 50 units per tick is about 0.33 ms.
- Accuracy: the job's machine total equals a direct `count_entities_filtered` of the whole surface
  (3,015 = 3,015, per-type 678 assemblers, 1,175 furnaces, 1,147 drills, 15 silos).
- Save/load in the middle of a job still resumes (`scripts/live-job-reload.sh`: the first run is
  auto-paused, so the job cannot progress while it is saved; the second, running server only finishes
  it if `on_load` brought the tick handler back).
- The `get_chunks` pass (23 ms for this surface) is a single-tick cost at `job_start`; it scales with
  the number of generated chunks of the requested surfaces.


## Local details and per-tick cost (Task 15, 0.4.0)

Copy of the real save (nauvis: 29,535 chunks, 185,044 resource tiles; Factorio 2.1.24, server under
`nice 10` on the owner's Mac). Method: the game's profiler around the mod's real handler
(`/sc __factorio-mcp__` + `package.loaded['__factorio-mcp__/scripts/dispatcher.lua'].execute`, so the
number includes grouping and JSON), average of 5 after a warm-up. Worst cases were built on the copy:
a solid 256x256 iron-ore field and a 64x64 block of loaded belts, inside the map's chunk bounds.
Goal (owner): the game must not stutter, so a synchronous answer stays around 2 ms and heavy work
runs as a job whose single tick stays around 2 ms.

- **Found first, before any change.** `resources` took 29-33 ms on the real save and 147 ms on the
  solid field at r=128: `get_resource_counts()` of the whole surface alone is 24-30 ms and cannot be
  split, and reading ore costs ~2.2 us per tile (find+read ~1 us, per-tile records ~1.2 us).
  `transport` on packed belts took 9.5 ms (r=16) and 14.5 ms (r=32). Every whole-map `job_start`
  took 32 ms in one tick, 24.6 ms of it the `get_chunks` walk for the map bounds. Counting is not
  free either: its cost grows with the area even where empty (+-1024 tiles 8.6 ms, +-16384 69 ms)
  and with the entities in it (a block of 65k ore tiles ~2.4 ms).
- **Changes.** `resources` counts the circle first, stopping at 1,001 (`count` with `limit`); above
  1,000 tiles it answers `job_needed` and the service runs job kind `resources`; ore is summed per
  chunk while reading (numeric keys, no per-tile records); the surface totals moved to job kind
  `resources_overview` (tool `base_resources_overview`). Job areas count with `limit = split + 1`;
  resource areas split at 300 tiles down to 16-tile squares. `transport` reads everything up to 600
  entities; above that, counts per name come from `count_entities_filtered` and only 300 inserters,
  100 belts and 300 fluid boxes are read (`sampled: true`). Map bounds live in `storage`, widened by
  `on_chunk_generated`, so `job_start` walks nothing.
- **Synchronous answers now** (ms in game, bytes): inventory 0.01-0.03 (60 B offline), alerts
  0.15-0.31 (1 KB), resources `job_needed` 0.06-0.10 at any radius on the solid field (the full
  count at r=128 was 2.36), transport real spots at r=32 1.0-1.6 (3.2-3.4 KB), packed belts r=8 0.4-0.5,
  r=16 0.5, r=32 1.2 (was 14.5). Largest answer 5.8 KB (`hello`).
- **Jobs now**, driven one tick budget (50 units) at a time, per-tick time:

  | Job | Ticks | Median | p99 | Max (before -> after `count` limit) |
  |---|---|---|---|---|
  | `resources` solid field r=128 (51,468 tiles) | 258 | 0.37 ms | 1.55 ms | 10.4 -> 2.0 ms |
  | `resources` real save r=128 (3,782 tiles) | 31 | 0.67 ms | 1.37 ms | 1.4 ms |
  | `resources_overview` nauvis (250k tiles) | 1,441 | 0.25 ms | 0.98 ms | 16.2 -> 1.7 ms |
  | `machines_overview` (existing kind) | 470 | 0.05 ms | 1.34 ms | 8.7 -> 2.4 ms |

  `job_start` 0.13-1.7 ms (was 32 ms). At 60 UPS the overview takes ~24 s in `ticks` mode. What is
  left in the worst tick is two 512-tile counts of busy ground (~1.2 ms each).
- **Accuracy.** `resources_overview` equals `get_resource_counts()` for every resource on nauvis
  (within 0.1%, drills may mine meanwhile; live test). Fluids: `get_fluid(i)` is each entity's own
  share of its segment (pipe 18/100, tank 4,620/25,000), and a tank filled with 1,000 water plus a pipe
  report 1,000. Pollution `per_minute`: 40 stone furnaces x 2/min read 80.00 in the 5 s and 1 min
  windows.
- **Factorio 2.1 API.** `LuaEntity.fluidbox` does not exist (use `fluids_count`, `get_fluid(i)`);
  an offline player has no character and `get_main_inventory()` returns an empty stand-in.
