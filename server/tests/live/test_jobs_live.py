"""Tick-split jobs against a real game. Run with AUTO_PAUSE=true and =false (scripts/live.sh passes it through)."""

from __future__ import annotations

import asyncio
import time

import pytest
import pytest_asyncio  # noqa: F401

from factorio_mcp.bridge import ModBridge, ModError

pytestmark = pytest.mark.live


@pytest_asyncio.fixture(autouse=True)
async def no_leftover_jobs(rcon):
    """The dev save may carry a job from an earlier run (that is the save/load path working)."""
    bridge = ModBridge(rcon)
    jobs = (await bridge.call("job_status"))["jobs"]
    for job in jobs if isinstance(jobs, list) else []:
        await bridge.call("job_cancel", {"job_id": job["id"]})
    yield


async def drain(bridge: ModBridge, job_id: int, limit: int = 20000) -> tuple[dict, int]:
    """Poll until done; returns the first page and the number of polls."""
    polls = 0
    while polls < limit:
        polls += 1
        page = await bridge.call("job_result", {"job_id": job_id})
        if page["state"] != "running":
            return page, polls
        await asyncio.sleep(0.02)
    raise AssertionError("job did not finish")


async def test_idle_job_finishes_by_polling_and_does_not_need_ticks(rcon, game_log_errors):
    errors_before = game_log_errors()
    bridge = ModBridge(rcon)
    info = await bridge.call("server_info")
    started = await bridge.call("job_start", {"kind": "machines_overview"})
    assert started["mode"] == "idle"  # nobody is online
    tick_before = info["tick"]
    page, polls = await drain(bridge, started["job_id"])
    assert page["state"] == "done" and "summary" in page
    status = await bridge.call("job_status")
    assert status["tick_handler_registered"] is False
    if info["paused"]:  # AUTO_PAUSE=true: the game is frozen, which proves the idle path did the work
        assert (await bridge.call("server_info"))["tick"] == tick_before
    assert game_log_errors() == errors_before


async def test_ticks_job_finishes_and_handler_is_removed(rcon):
    bridge = ModBridge(rcon)
    if (await bridge.call("server_info"))["paused"]:
        pytest.skip("ticks mode cannot advance while the game is paused (AUTO_PAUSE=true)")
    started = await bridge.call("job_start", {"kind": "machines_overview", "mode": "ticks"})
    assert started["mode"] == "ticks"
    assert (await bridge.call("job_status"))["tick_handler_registered"] is True
    page, _ = await drain(bridge, started["job_id"])
    assert page["state"] == "done"
    assert (await bridge.call("job_status"))["tick_handler_registered"] is False
    with pytest.raises(ModError) as info:
        await bridge.call("job_result", {"job_id": started["job_id"]})
    assert info.value.code == "job_not_found"


async def test_cancel_removes_the_handler(rcon):
    bridge = ModBridge(rcon)
    started = await bridge.call("job_start", {"kind": "machines_overview", "mode": "ticks"})
    assert (await bridge.call("job_cancel", {"job_id": started["job_id"]}))["cancelled"] is True
    assert (await bridge.call("job_status"))["tick_handler_registered"] is False


async def test_big_area_matches_the_synchronous_scan(rcon):
    bridge = ModBridge(rcon)
    found = await rcon.exec(
        '/sc local m = game.surfaces.nauvis.find_entities_filtered{type = "assembling-machine", limit = 1}[1]'
        ' if m then rcon.print(helpers.table_to_json({x = m.position.x, y = m.position.y})) else rcon.print("none") end',
        timeout=10,
    )
    if found.strip() in ("", "none") or "achievements" in found:
        await rcon.exec("/sc rcon.print('ok')", timeout=10)
        found = await rcon.exec(
            '/sc local m = game.surfaces.nauvis.find_entities_filtered{type = "assembling-machine", limit = 1}[1]'
            ' if m then rcon.print(helpers.table_to_json({x = m.position.x, y = m.position.y})) else rcon.print("none") end',
            timeout=10,
        )
    if found.strip() == "none":
        pytest.skip("no assembling machine in this save")
    import json

    where = json.loads(found)
    args = {"surface": "nauvis", "x": where["x"], "y": where["y"]}
    sync = await bridge.call("area", {**args, "radius": 60})
    started = await bridge.call("job_start", {"kind": "area", "params": {**args, "radius": 60}})
    page, _ = await drain(bridge, started["job_id"])
    assert page["totals"] == sync["totals"]
    assert [g["name"] for g in page["groups"]] == [g["name"] for g in sync["groups"]]


async def test_measure_job_costs(rcon, capsys):
    bridge = ModBridge(rcon)
    started = await bridge.call("job_start", {"kind": "machines_overview", "mode": "idle"})
    t0 = time.monotonic()
    page, polls = await drain(bridge, started["job_id"])
    elapsed = time.monotonic() - t0
    with capsys.disabled():
        print(
            f"\njob machines_overview: chunks={started['total_chunks']} polls={polls} "
            f"wall={elapsed * 1000:.0f} ms summary={page['summary']}"
        )
    t0 = time.monotonic()
    for _ in range(20):
        await bridge.call("job_status")
    with capsys.disabled():
        print(f"RCON round trip (job_status): {(time.monotonic() - t0) / 20 * 1000:.2f} ms")
