"""Defense scan against a real game. `/sc` is used here, in tests, on the dev server only."""

from __future__ import annotations

import json

import pytest

from factorio_mcp.bridge import ModBridge, ModError

pytestmark = pytest.mark.live


async def sc(rcon, code: str) -> str:
    return await rcon.exec("/sc " + code.replace("\n", " "), timeout=20)


async def arm(rcon) -> None:
    # The first /sc in a save asks to disable achievements; a second one runs.
    await rcon.exec("/sc rcon.print('ready')", timeout=10)
    await rcon.exec("/sc rcon.print('ready')", timeout=10)


# Defenses near (300, 300), far from the area tests. The worm stands 55 tiles away: inside the
# scan radius but out of range of the turrets (and they of it), so nothing fights during the test.
SETUP = """
local s = game.surfaces.nauvis
s.request_to_generate_chunks({300, 300}, 4); s.force_generate_chunk_requests()
local function put(name, x, y, force)
  local p = s.find_non_colliding_position(name, {x, y}, 20, 1)
  return s.create_entity{name = name, position = p, force = force or "player"}
end
local ready = put("gun-turret", 300, 300)
ready.insert{name = "firearm-magazine", count = 10}
put("gun-turret", 304, 300)
put("laser-turret", 308, 300)
local flame = put("flamethrower-turret", 300, 306)
flame.insert_fluid{name = "light-oil", amount = 50}
local wall = put("stone-wall", 296, 296)
wall.health = 100
put("radar", 310, 310)
put("medium-worm-turret", 355, 300, "enemy")
rcon.print(helpers.table_to_json({x = 302, y = 302}))
"""


async def test_defenses_real_shapes(rcon, game_log_errors):
    errors_before = game_log_errors()
    await arm(rcon)
    where = json.loads(await sc(rcon, SETUP))
    bridge = ModBridge(rcon)
    result = await bridge.call("defenses", {"surface": "nauvis", "x": where["x"], "y": where["y"], "radius": 64})

    groups = {g["name"]: g for g in result["groups"]}
    assert {"gun-turret", "laser-turret", "flamethrower-turret", "stone-wall", "radar"} <= set(groups)
    assert "medium-worm-turret" not in json.dumps(result)

    assert groups["gun-turret"]["ammo"]["firearm-magazine"] >= 10
    assert groups["flamethrower-turret"]["fluids"]["light-oil"] > 0

    issues = result["summary"]["issues"]
    assert issues["no_ammo"] >= 1
    assert issues["no_power"] >= 2  # laser turret and radar, nothing powers them
    assert issues["damaged"] >= 1

    by_issue = {}
    for p in result["problems"]:
        by_issue.setdefault(p["issue"], []).append(p["name"])
    assert "gun-turret" in by_issue["no_ammo"]
    assert "laser-turret" in by_issue["no_power"]
    assert "stone-wall" in by_issue["damaged"]
    assert "flamethrower-turret" not in by_issue.get("no_fluid", [])
    assert result["problems"][0]["issue"] in ("no_ammo", "no_power")
    assert game_log_errors() == errors_before


async def test_defenses_bounds(rcon):
    bridge = ModBridge(rcon)
    for params in ({"radius": 65}, {"max_listed": 51}, {"max_listed": 0}):
        with pytest.raises(ModError) as info:
            await bridge.call("defenses", {"surface": "nauvis", "x": 0, "y": 0, **params})
        assert info.value.code == "bad_params"
