"""Logistic networks, trains and platforms against a real game. `/sc` is used here, on the dev server only."""

from __future__ import annotations

import json

import pytest

from factorio_mcp.bridge import ModBridge, ModError

pytestmark = pytest.mark.live


async def sc(rcon, code: str) -> str:
    return await rcon.exec("/sc " + code.replace("\n", " "), timeout=20)


ROBOPORT = """
local s = game.surfaces.nauvis
local bx = 5000 + (game.tick % 50) * 128
local by = 5000
s.request_to_generate_chunks({bx, by}, 2); s.force_generate_chunk_requests()
local port = s.create_entity{name = 'roboport', position = {bx, by}, force = 'player'}
port.get_inventory(defines.inventory.roboport_robot).insert{name = 'logistic-robot', count = 10}
local chest = s.create_entity{name = 'storage-chest', position = {bx + 4, by}, force = 'player'}
chest.get_inventory(defines.inventory.chest).insert{name = 'iron-plate', count = 123}
rcon.print(helpers.table_to_json({x = bx, y = by}))
"""


async def test_logistics_network_contents(armed, caller_nick):
    json.loads(await sc(armed, ROBOPORT))
    bridge = ModBridge(armed)
    result = await bridge.call("logistics", {"caller": caller_nick, "surface": "nauvis"})
    assert result["total"] >= 1
    one = await bridge.call("logistics", {"caller": caller_nick, "name": "iron-plate"})
    assert one["total"] >= 123


async def test_logistics_unknown_caller(armed):
    with pytest.raises(ModError) as info:
        await ModBridge(armed).call("logistics", {"caller": "nobody-here-123"})
    assert info.value.code == "not_found"


TRAIN = """
local s = game.surfaces.nauvis
local bx = 6000 + (game.tick % 50) * 128
local by = 6000
s.request_to_generate_chunks({bx, by}, 2); s.force_generate_chunk_requests()
for i = 0, 20 do s.create_entity{name = 'straight-rail', position = {bx + 1, by + i * 2 + 1}, force = 'player'} end
local loco = s.create_entity{name = 'locomotive', position = {bx + 1, by + 10}, force = 'player'}
rcon.print(helpers.table_to_json({id = loco and loco.train and loco.train.id or -1}))
"""


async def test_trains_lists_a_train_without_schedule(armed, caller_nick):
    made = json.loads(await sc(armed, TRAIN))
    assert made["id"] > 0, "the setup could not place a locomotive"
    result = await ModBridge(armed).call("trains", {"caller": caller_nick, "limit": 50})
    ids = {t["id"] for t in result["trains"]}
    assert made["id"] in ids or result["next"] is not None
    assert result["total"] >= 1


async def test_trains_unknown_caller(armed):
    with pytest.raises(ModError) as info:
        await ModBridge(armed).call("trains", {"caller": "nobody-here-123"})
    assert info.value.code == "not_found"


async def test_train_api_fields_the_mod_reads(armed):
    """The fields trains_logic reads exist on a real train (checked without a caller)."""
    made = json.loads(await sc(armed, TRAIN))
    assert made["id"] > 0, "the setup could not place a locomotive"
    reply = await sc(
        armed,
        f"""
local t = game.train_manager.get_train_by_id({made["id"]})
local sch = t.get_schedule()
rcon.print(helpers.table_to_json({{state = t.state, surface = t.front_stock.surface.name,
  ticks = sch and sch.ticks_in_station or -1, contents = #t.get_contents(), group = t.group or '',
  has_station = t.station ~= nil, has_target = t.path_end_stop ~= nil}}))
""",
    )
    got = json.loads(reply)
    assert got["surface"] == "nauvis" and isinstance(got["state"], int) and got["ticks"] >= 0


async def _platform(armed) -> str:
    has = (await sc(armed, "rcon.print(game.planets.nauvis and prototypes.item['space-platform-starter-pack'] and 'yes' or 'no')")).strip()
    if has != "yes":
        pytest.skip("Space Age is not enabled (run with SPACE_AGE=true)")
    return (
        await sc(
            armed,
            """
local name = 'test-' .. game.tick
local p = game.forces.player.create_space_platform{name = name, planet = 'nauvis', starter_pack = 'space-platform-starter-pack'}
rcon.print(p and p.name or '')
""",
        )
    ).strip()


async def test_platform_api_fields_the_mod_reads(armed):
    """The fields platforms_logic reads exist on a real platform (checked without a caller)."""
    name = await _platform(armed)
    assert name
    reply = await sc(
        armed,
        f"""
local p
for _, x in pairs(game.forces.player.platforms) do if x.name == '{name}' then p = x end end
rcon.print(helpers.table_to_json({{state = p.state, speed = p.speed, distance = p.distance,
  damaged = #p.damaged_tiles, has_loc = p.space_location ~= nil, hub = p.hub ~= nil}}))
""",
    )
    got = json.loads(reply)
    assert isinstance(got["state"], int) and got["damaged"] >= 0


async def test_platforms_lists_a_new_platform(armed, caller_nick):
    name = await _platform(armed)
    result = await ModBridge(armed).call("platforms", {"caller": caller_nick, "name": name})
    assert result["platforms"][0]["name"] == name
