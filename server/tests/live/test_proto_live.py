from __future__ import annotations

import time

import pytest

from factorio_mcp.bridge import ModBridge
from factorio_mcp.reference import KINDS, ReferenceCache

pytestmark = pytest.mark.live


async def test_reference_against_real_game(rcon, game_log_errors, capsys):  # noqa: PLR0915
    errors_before = game_log_errors()
    bridge = ModBridge(rcon)
    await bridge.refresh_hello()
    assert {f"proto_{k}" for k in KINDS} <= bridge.last_hello.commands
    cache = ReferenceCache(bridge)

    timings = {}
    for kind in KINDS:
        started = time.monotonic()
        items = await cache.get(kind)
        timings[kind] = (len(items), round((time.monotonic() - started) * 1000))
        assert items, kind
    with capsys.disabled():
        print("\nreference fill (kind: count, ms):", timings)

    recipes = await cache.get("recipes")
    assert all(isinstance(r["ingredients"], list) and isinstance(r["products"], list) for r in recipes)
    machines = await cache.get("machines")
    assert all(isinstance(m["crafting_categories"], list) for m in machines)
    assert any(m.get("crafting_speed") for m in machines)

    info = await bridge.call("server_info")
    planets = {p["name"] for p in await cache.get("planets")}
    for surface in info["surfaces"]:
        planet = surface.get("planet")
        if planet:
            assert planet in planets, planet

    sent = []
    original = rcon.exec

    async def counting(command, timeout=5.0):
        sent.append(command)
        return await original(command, timeout)

    rcon.exec = counting
    await cache.get("recipes")
    assert sent == [], "second call must be served from cache"
    assert game_log_errors() == errors_before
