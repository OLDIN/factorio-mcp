"""Production statistics against a real game. `/sc` is used here, in tests, on the dev server only."""

from __future__ import annotations

import asyncio
import json

import pytest

from factorio_mcp.bridge import ModBridge

pytestmark = pytest.mark.live


async def sc(rcon, code: str) -> str:
    return await rcon.exec("/sc " + code.replace("\n", " "), timeout=20)


async def test_production_flow_unit(armed):
    """get_flow_count(count=false) is per minute for every window; a plain name is normal quality only."""
    await sc(armed, "game.forces.player.get_item_production_statistics('nauvis').on_flow('iron-stick', 600)")
    await asyncio.sleep(1)  # statistics take the flow on the next sample
    reply = await sc(
        armed,
        """
local st = game.forces.player.get_item_production_statistics('nauvis')
local fi = defines.flow_precision_index
local function f(pi) return st.get_flow_count{name = 'iron-stick', category = 'input', precision_index = fi[pi], count = false} end
rcon.print(helpers.table_to_json({s5 = f('five_seconds'), m1 = f('one_minute'), m10 = f('ten_minutes'), h1 = f('one_hour')}))
""",
    )
    got = json.loads(reply)
    # 600 items within the last 5 s = 7200 per minute; longer windows also hold earlier runs' flows
    # (the dev save is kept), so they are only bounded from below
    assert got["s5"] == pytest.approx(7200, rel=0.05)
    assert got["m1"] >= 600 and got["m10"] >= 60 and got["h1"] >= 10


async def test_electric_flow_direction(armed):
    """Electric statistics: output = production, input = consumption, values in joules per tick."""
    # The dev save keeps entities between runs: build in a fresh spot each time and remember the pole.
    where = json.loads(
        await sc(
            armed,
            """
local s = game.surfaces.nauvis
s.always_day = true
local bx = 2000 + (game.tick % 50) * 64
s.request_to_generate_chunks({bx, 2000}, 2); s.force_generate_chunk_requests()
for i = 0, 3 do s.create_entity{name = 'solar-panel', position = {bx + i * 3, 2000}, force = 'player'} end
local pole = s.create_entity{name = 'medium-electric-pole', position = {bx + 6, 2003}, force = 'player'}
s.create_entity{name = 'assembling-machine-1', position = {bx + 6, 2006}, force = 'player'}.set_recipe('iron-gear-wheel')
rcon.print(helpers.table_to_json({x = pole.position.x, y = pole.position.y, net = pole.electric_network_id}))
""",
        )
    )
    await asyncio.sleep(6)  # the 5 s window averages over its whole length
    reply = await sc(
        armed,
        f"""
local s = game.surfaces.nauvis
local pole = s.find_entities_filtered{{name = 'medium-electric-pole', position = {{{where["x"]}, {where["y"]}}}, radius = 0.5}}[1]
local es = pole.electric_network_statistics
local fi = defines.flow_precision_index.five_seconds
local function f(n, c) return es.get_flow_count{{name = n, category = c, precision_index = fi}} end
rcon.print(helpers.table_to_json({{solar_out = f('solar-panel', 'output'), solar_in = f('solar-panel', 'input'),
  asm_in = f('assembling-machine-1', 'input')}}))
""",
    )
    got = json.loads(reply)
    assert got["solar_out"] > 0 and got["solar_in"] == 0
    # an idle assembling machine 1 draws its 2.5 kW drain: 41.67 J per tick
    assert got["asm_in"] == pytest.approx(2500 / 60, rel=0.05)


async def test_production_reports_flow(armed, caller_nick):
    await sc(armed, "game.forces.player.get_item_production_statistics('nauvis').on_flow('iron-chest', 300)")
    result = await ModBridge(armed).call("production", {"caller": caller_nick, "window": "5s", "name": "iron-chest"})
    assert result["kind"] == "item"
    assert result["total"]["produced"] > 0


async def test_production_unknown_caller(armed):
    from factorio_mcp.bridge import ModError

    with pytest.raises(ModError) as info:
        await ModBridge(armed).call("production", {"caller": "nobody-here-123"})
    assert info.value.code == "not_found"
