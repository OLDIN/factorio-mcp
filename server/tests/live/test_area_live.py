"""Area diagnostics against a real game. `/sc` is used here, in tests, on the dev server only."""

from __future__ import annotations

import json
import time

import pytest

from factorio_mcp.bridge import ModBridge

pytestmark = pytest.mark.live


async def sc(rcon, code: str) -> str:
    return await rcon.exec("/sc " + code.replace("\n", " "), timeout=20)


async def arm(rcon) -> None:
    # The first /sc in a save asks to disable achievements; a second one runs.
    await rcon.exec("/sc rcon.print('ready')", timeout=10)
    await rcon.exec("/sc rcon.print('ready')", timeout=10)


SETUP = """
local s = game.surfaces.nauvis
s.request_to_generate_chunks({0, 0}, 3); s.force_generate_chunk_requests()
local function put(name, x, y)
  local p = s.find_non_colliding_position(name, {x, y}, 30, 1)
  return s.create_entity{name = name, position = p, force = "player"}
end
local asm = put("assembling-machine-2", 10, 10)
asm.set_recipe("iron-gear-wheel")
local furnace = put("stone-furnace", 10, 10)
local car = put("car", 10, 10)
car.get_inventory(defines.inventory.car_trunk).insert{name = "artillery-shell", count = 5}
local ch = put("character", 10, 10)
ch.get_main_inventory().insert{name = "power-armor", count = 1}
ch.die()
rcon.print(helpers.table_to_json({x = asm.position.x, y = asm.position.y}))
"""


async def test_private_entities_never_appear(rcon, game_log_errors):
    errors_before = game_log_errors()
    await arm(rcon)
    reply = await sc(rcon, SETUP)
    where = json.loads(reply)
    bridge = ModBridge(rcon)
    result = await bridge.call("area", {"surface": "nauvis", "x": where["x"], "y": where["y"], "radius": 40})
    names = {g["name"] for g in result["groups"]}
    assert {"assembling-machine-2", "stone-furnace"} <= names
    text = json.dumps(result)
    for secret in ("car", "artillery-shell", "power-armor", "corpse", "character"):
        assert secret not in text, secret
    assert game_log_errors() == errors_before


async def test_unknown_surface_and_offline_player(rcon):
    bridge = ModBridge(rcon)
    from factorio_mcp.bridge import ModError

    with pytest.raises(ModError) as info:
        await bridge.call("area", {"surface": "no-such", "x": 0, "y": 0})
    assert info.value.code == "not_found"
    with pytest.raises(ModError) as info:
        await bridge.call("area", {"player": "nobody-here"})
    assert info.value.code == "not_found"


async def test_synchronous_area_refuses_big_radius(rcon):
    from factorio_mcp.bridge import ModError

    with pytest.raises(ModError) as info:
        await ModBridge(rcon).call("area", {"surface": "nauvis", "x": 0, "y": 0, "radius": 65})
    assert info.value.code == "bad_params" and "job" in info.value.message


async def test_area_on_real_base_is_fast_and_parses(rcon, capsys):
    await arm(rcon)
    found = await sc(rcon, """
local m = game.surfaces.nauvis.find_entities_filtered{type = "assembling-machine", limit = 1}[1]
if m then rcon.print(helpers.table_to_json({x = m.position.x, y = m.position.y})) else rcon.print("none") end
""")
    if found == "none":
        pytest.skip("no assembling machine in this save")
    where = json.loads(found)
    bridge = ModBridge(rcon)
    timings = {}
    for radius in (32, 64):  # larger radii run as jobs (see test_jobs_live)
        started = time.monotonic()
        res = await bridge.call("area", {"surface": "nauvis", "x": where["x"], "y": where["y"], "radius": radius})
        timings[radius] = (round((time.monotonic() - started) * 1000), res["totals"]["machines"], res["truncated"])
        assert res["totals"]["machines"] >= len(res["stopped"])
        assert len(json.dumps(res)) < 48000
    with capsys.disabled():
        print("\narea (radius: ms, machines, truncated):", timings)
