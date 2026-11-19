"""Own inventory and alerts, resources and transport against a real game. `/sc` is used here, in tests,
on the dev server only. Written 2026-11-19 without a live run (owner's call); run them before the release."""

from __future__ import annotations

import asyncio
import json

import pytest

from factorio_mcp.bridge import ModBridge, ModError

pytestmark = pytest.mark.live

STUCK = {"no_power", "low_power", "waiting_for_space_in_destination", "waiting_for_source_items"}


async def sc(rcon, code: str) -> str:
    return await rcon.exec("/sc " + code.replace("\n", " "), timeout=20)


@pytest.mark.parametrize("sub", ["inventory", "alerts", "resources", "transport"])
async def test_unknown_caller(armed, sub):
    args = {"caller": "nobody-here-123"}
    if sub in ("resources", "transport"):
        args.update({"surface": "nauvis", "x": 0, "y": 0})
    with pytest.raises(ModError) as info:
        await ModBridge(armed).call(sub, args)
    assert info.value.code == "not_found"


async def test_inventory_of_an_offline_player(armed, caller_nick):
    result = await ModBridge(armed).call("inventory", {"caller": caller_nick})
    assert result["online"] is False  # the dev server has no connected player
    # checked live (2.1.24): offline there is no character and the game hands out an empty stand-in
    assert result == {"online": False, "readable": False}


async def test_alerts_of_an_offline_player(armed, caller_nick):
    result = await ModBridge(armed).call("alerts", {"caller": caller_nick})
    assert result["online"] is False and isinstance(result["by_type"], (list, dict))


async def run_job(bridge: ModBridge, kind: str, params: dict) -> dict:
    start = await bridge.call("job_start", {"kind": kind, "params": params, "mode": "idle"})
    for _ in range(600):
        page = await bridge.call("job_result", {"job_id": start["job_id"]})
        if page["state"] == "done":
            assert page.get("next") is None, "one page is enough for these answers"
            return page
        await asyncio.sleep(0.05)
    raise AssertionError(f"{kind} job did not finish")


async def test_resources_near_spawn(armed, caller_nick):
    # rich spawn ore: above the tile threshold the command answers job_needed and the job gives the patches;
    # every tile in the circle lands in exactly one patch
    await sc(armed, "local s = game.surfaces.nauvis; s.request_to_generate_chunks({0, 0}, 5); s.force_generate_chunk_requests()")
    tiles = int(await sc(armed, "rcon.print(game.surfaces.nauvis.count_entities_filtered{position = {0, 0}, radius = 128, type = 'resource'})"))
    bridge = ModBridge(armed)
    args = {"caller": caller_nick, "surface": "nauvis", "x": 0, "y": 0, "radius": 128, "limit": 30}
    sync = await bridge.call("resources", args)
    if tiles > 1000:
        assert sync == {"job_needed": True, "center": {"surface": "nauvis", "x": 0, "y": 0}, "radius": 128}
        result = await run_job(bridge, "resources", args)
    else:
        result = sync
    iron = [p for p in result["patches"] if p["name"] == "iron-ore"]
    assert iron and iron[0]["amount"] > 0 and iron[0]["tiles"] > 0 and iron[0]["fluid"] is False
    if result["patches_total"] <= 30:
        assert sum(p.get("tiles", 0) + p.get("wells", 0) for p in result["patches"]) == tiles


async def test_resources_small_radius_answers_at_once(armed, caller_nick):
    spot = json.loads(await sc(armed, """
local e = game.surfaces.nauvis.find_entities_filtered{position = {0, 0}, radius = 300, name = 'iron-ore', limit = 1}[1]
rcon.print(helpers.table_to_json({x = e.position.x, y = e.position.y}))
"""))
    result = await ModBridge(armed).call(
        "resources", {"caller": caller_nick, "surface": "nauvis", "x": spot["x"], "y": spot["y"], "radius": 16}
    )
    assert "job_needed" not in result and any(p["name"] == "iron-ore" for p in result["patches"])


async def test_resources_overview_matches_the_game(armed, caller_nick):
    # the job's per-surface totals against the game's own (one big call, fine in a test)
    page = await run_job(ModBridge(armed), "resources_overview", {"caller": caller_nick, "surfaces": ["nauvis"]})
    game = json.loads(await sc(armed, "rcon.print(helpers.table_to_json(game.surfaces.nauvis.get_resource_counts()))"))
    ours = {r["name"]: r["amount"] for r in page["resources"] if r["surface"] == "nauvis"}
    assert set(ours) == set(game), (sorted(ours), sorted(game))
    for name, amount in game.items():
        assert abs(ours[name] - amount) <= max(1, amount * 0.001), (name, ours[name], amount)  # drills may mine meanwhile


# A belt with iron plates, an unpowered inserter holding a plate between two full chests, and a tank of
# water with a pipe (2.1 has no LuaEntity.fluidbox), at a fresh spot (cleared first: a real map may
# have water, cliffs or trees there).
TRANSPORT_SETUP = """
local s = game.surfaces.nauvis
local force = game.players[1].force
local bx = 3000 + (game.tick % 50) * 64
local by = -4000
s.request_to_generate_chunks({bx, by}, 1); s.force_generate_chunk_requests()
local tiles = {}
for dx = -10, 10 do for dy = -10, 10 do tiles[#tiles + 1] = {name = 'grass-1', position = {bx + dx, by + dy}} end end
s.set_tiles(tiles)
for _, e in ipairs(s.find_entities_filtered{area = {{bx - 10, by - 10}, {bx + 10, by + 10}}}) do e.destroy() end
local belt = s.create_entity{name = 'transport-belt', position = {bx, by + 3}, force = force}
belt.get_transport_line(1).insert_at_back({name = 'iron-plate', count = 1})
belt.get_transport_line(2).insert_at_back({name = 'iron-plate', count = 1})
for _, x in ipairs({bx - 1, bx + 1}) do
  local chest = s.create_entity{name = 'wooden-chest', position = {x, by}, force = force}
  chest.insert{name = 'stone', count = 800}
end
local ins = s.create_entity{name = 'inserter', position = {bx, by}, force = force, direction = defines.direction.east}
ins.held_stack.set_stack{name = 'iron-plate', count = 1}
local tank = s.create_entity{name = 'storage-tank', position = {bx - 3, by - 3}, force = force}
tank.insert_fluid({name = 'water', amount = 1000})
s.create_entity{name = 'pipe', position = {bx - 3, by - 6}, force = force}
rcon.print(helpers.table_to_json({x = bx, y = by}))
"""


async def test_transport_belt_and_stuck_inserter(armed, caller_nick):
    where = json.loads(await sc(armed, TRANSPORT_SETUP))
    result = await ModBridge(armed).call(
        "transport", {"caller": caller_nick, "surface": "nauvis", "x": where["x"], "y": where["y"], "radius": 8}
    )
    assert result["counts"]["inserter"] == 1 and result["counts"]["transport-belt"] == 1
    assert result["inserters"]["stuck"] and result["inserters"]["stuck"][0]["status"] in STUCK
    assert any(i["name"] == "iron-plate" for i in result["belts"]["items"])
    assert result["counts"]["storage-tank"] == 1 and result["counts"]["pipe"] == 1
    water = [f for f in result["fluids"] if f["name"] == "water"]
    assert water and 999 <= water[0]["amount"] <= 1001, "tank and pipe shares add up to what went in"



# A packed bus: more entities than one call reads in full, at a fresh cleared spot.
BUS_SETUP = """
local s = game.surfaces.nauvis
local force = game.players[1].force
local bx = -3000 - (game.tick % 50) * 64
local by = -5000
s.request_to_generate_chunks({bx, by}, 2); s.force_generate_chunk_requests()
local tiles = {}
for dx = -24, 24 do for dy = -24, 24 do tiles[#tiles + 1] = {name = 'grass-1', position = {bx + dx, by + dy}} end end
s.set_tiles(tiles)
for _, e in ipairs(s.find_entities_filtered{area = {{bx - 24, by - 24}, {bx + 24, by + 24}}}) do e.destroy() end
local n = 0
for dx = -14, 13 do for dy = -12, 12 do
  local belt = s.create_entity{name = 'transport-belt', position = {bx + dx + 0.5, by + dy + 0.5}, force = force}
  belt.get_transport_line(1).insert_at_back({name = 'iron-plate', count = 1})
  n = n + 1
end end
local ins = s.create_entity{name = 'inserter', position = {bx + 20, by}, force = force}
rcon.print(helpers.table_to_json({x = bx, y = by, belts = n}))
"""


async def test_transport_packed_bus_is_counted_and_sampled(armed, caller_nick):
    where = json.loads(await sc(armed, BUS_SETUP))
    assert where["belts"] > 600
    result = await ModBridge(armed).call(
        "transport", {"caller": caller_nick, "surface": "nauvis", "x": where["x"], "y": where["y"], "radius": 32}
    )
    assert result["sampled"] is True
    assert result["counts"]["transport-belt"] == where["belts"] and result["counts"]["inserter"] == 1
    assert result["belts"]["total"] == where["belts"] and result["belts"]["read"] == 100
    assert result["belts"]["items"][0] == {"name": "iron-plate", "count": 100}
    assert result["inserters"]["read"] == 1 and result["inserters"]["total"] == 1
