"""Power networks against a real game. `/sc` is used here, in tests, on the dev server only."""

from __future__ import annotations

import asyncio
import json

import pytest

from factorio_mcp.bridge import ModBridge

pytestmark = pytest.mark.live


async def sc(rcon, code: str) -> str:
    return await rcon.exec("/sc " + code.replace("\n", " "), timeout=20)


# A solar network and, 20 tiles away, a pole with an assembler but no generator (no power).
# The dev save keeps entities between runs, so each run builds in a fresh spot.
SETUP = """
local s = game.surfaces.nauvis
s.always_day = true
local bx = 2000 + (game.tick % 50) * 64
local by = 3000
s.request_to_generate_chunks({bx, by}, 2); s.force_generate_chunk_requests()
for i = 0, 3 do s.create_entity{name = 'solar-panel', position = {bx + i * 3, by}, force = 'player'} end
s.create_entity{name = 'medium-electric-pole', position = {bx + 6, by + 3}, force = 'player'}
s.create_entity{name = 'assembling-machine-1', position = {bx + 6, by + 6}, force = 'player'}.set_recipe('iron-gear-wheel')
s.create_entity{name = 'medium-electric-pole', position = {bx + 26, by + 3}, force = 'player'}
s.create_entity{name = 'assembling-machine-1', position = {bx + 26, by + 6}, force = 'player'}.set_recipe('iron-gear-wheel')
rcon.print(helpers.table_to_json({x = bx + 12, y = by + 3}))
"""


async def test_power_networks_and_starved_machines(armed, caller_nick):
    where = json.loads(await sc(armed, SETUP))
    await asyncio.sleep(6)
    result = await ModBridge(armed).call(
        "power", {"caller": caller_nick, "surface": "nauvis", "x": where["x"], "y": where["y"], "radius": 32}
    )
    assert result["networks_total"] >= 2
    powered = [n for n in result["networks"] if n["produced_kw"] > 0]
    assert powered and any(p["name"] == "solar-panel" for p in powered[0]["top_producers"])
    statuses = {e["status"] for e in result["starved_examples"]}
    assert "no_power" in statuses


async def test_power_unknown_caller(armed):
    from factorio_mcp.bridge import ModError

    with pytest.raises(ModError) as info:
        await ModBridge(armed).call("power", {"caller": "nobody-here-123", "surface": "nauvis", "x": 0, "y": 0})
    assert info.value.code == "not_found"
