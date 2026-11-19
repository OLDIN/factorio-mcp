"""Own inventory and alerts, resources and transport against a real game. `/sc` is used here, in tests,
on the dev server only. Written 2026-11-19 without a live run (owner's call); run them before the release."""

from __future__ import annotations

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


async def test_resources_near_spawn(armed, caller_nick):
    await sc(armed, "local s = game.surfaces.nauvis; s.request_to_generate_chunks({0, 0}, 5); s.force_generate_chunk_requests()")
    result = await ModBridge(armed).call("resources", {"caller": caller_nick, "surface": "nauvis", "x": 0, "y": 0, "radius": 128})
    iron = [p for p in result["patches"] if p["name"] == "iron-ore"]
    assert iron and iron[0]["amount"] > 0 and iron[0]["tiles"] > 0 and iron[0]["fluid"] is False
    assert result["surface_totals"].get("iron-ore", 0) > 0


# A belt with iron plates, an unpowered inserter holding a plate between two full chests, and a tank of
# water with a pipe (2.1 has no LuaEntity.fluidbox), at a fresh spot.
TRANSPORT_SETUP = """
local s = game.surfaces.nauvis
local force = game.players[1].force
local bx = 3000 + (game.tick % 50) * 64
local by = -4000
s.request_to_generate_chunks({bx, by}, 1); s.force_generate_chunk_requests()
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

