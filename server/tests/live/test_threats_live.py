"""Threats and pollution against a real game. `/sc` is used here, in tests, on the dev server only."""

from __future__ import annotations

import asyncio
import json

import pytest

from factorio_mcp.bridge import ModBridge, ModError

pytestmark = pytest.mark.live


async def sc(rcon, code: str) -> str:
    return await rcon.exec("/sc " + code.replace("\n", " "), timeout=20)


# A nest and a worm 150 tiles east of a fresh spot (the dev save keeps entities between runs).
SETUP = """
local s = game.surfaces.nauvis
local bx = -3000 - (game.tick % 50) * 64
local by = 4000
s.request_to_generate_chunks({bx + 150, by}, 3); s.force_generate_chunk_requests()
local function put(name, x, y)
  local p = s.find_non_colliding_position(name, {x, y}, 20, 1)
  return s.create_entity{name = name, position = p, force = 'enemy'}
end
put('biter-spawner', bx + 150, by)
put('medium-worm-turret', bx + 150, by + 12)
rcon.print(helpers.table_to_json({x = bx, y = by}))
"""


async def test_threats_finds_nest_and_worm(armed, caller_nick):
    where = json.loads(await sc(armed, SETUP))
    bridge = ModBridge(armed)
    result = await bridge.call(
        "threats", {"caller": caller_nick, "surface": "nauvis", "x": where["x"], "y": where["y"], "radius": 200}
    )
    names = {n["name"] for n in result["nearest"]}
    assert {"biter-spawner", "medium-worm-turret"} <= names
    nest = next(n for n in result["nearest"] if n["name"] == "biter-spawner")
    assert nest["direction"] == "E" and 140 <= nest["distance"] <= 170 and "pollution" in nest


async def test_threats_job_matches_sync(armed, caller_nick):
    where = json.loads(await sc(armed, SETUP))
    bridge = ModBridge(armed)
    params = {"caller": caller_nick, "surface": "nauvis", "x": where["x"], "y": where["y"], "radius": 300}
    start = await bridge.call("job_start", {"kind": "threats", "params": params, "mode": "idle"})
    for _ in range(200):
        page = await bridge.call("job_result", {"job_id": start["job_id"]})
        if page["state"] == "done":
            break
        await asyncio.sleep(0.1)
    assert page["state"] == "done"
    assert page["total"] >= 2


async def test_threats_unknown_caller(armed):
    with pytest.raises(ModError) as info:
        await ModBridge(armed).call("threats", {"caller": "nobody-here-123", "surface": "nauvis", "x": 0, "y": 0})
    assert info.value.code == "not_found"


async def test_pollution_on_nauvis(armed, caller_nick):
    where = json.loads(await sc(armed, SETUP))
    result = await ModBridge(armed).call(
        "pollution", {"caller": caller_nick, "surface": "nauvis", "x": where["x"], "y": where["y"], "grid": 3}
    )
    assert result["pollutant"] == "pollution"
    assert result["grid"] == 3 and isinstance(result["total"], (int, float))


async def test_pollution_spores_on_gleba(armed, caller_nick):
    has_gleba = (await sc(armed, "rcon.print(game.planets.gleba and 'yes' or 'no')")).strip()
    if has_gleba != "yes":
        pytest.skip("Space Age is not enabled (run with SPACE_AGE=true)")
    await sc(armed, "if not game.surfaces.gleba then game.planets.gleba.create_surface() end")
    result = await ModBridge(armed).call("pollution", {"caller": caller_nick, "surface": "gleba", "x": 0, "y": 0, "grid": 1})
    assert result["pollutant"] == "spores"


async def test_pollution_unknown_caller(armed):
    with pytest.raises(ModError) as info:
        await ModBridge(armed).call("pollution", {"caller": "nobody-here-123", "surface": "nauvis", "x": 0, "y": 0})
    assert info.value.code == "not_found"
