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
