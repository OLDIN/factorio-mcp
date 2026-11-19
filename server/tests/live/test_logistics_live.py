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
