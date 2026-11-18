from __future__ import annotations

import json

from stack_fixture import hello_reply

from factorio_mcp.commands import build_command

ALL = ("hello", "server_info", "players", "threats", "job_start", "job_result")


def _env(result):
    return json.dumps({"v": 1, "ok": True, "result": result})


THREATS = {
    "total": 2,
    "counts": {"biter-spawner": 1, "medium-worm-turret": 1},
    "nearest": [
        {"name": "medium-worm-turret", "type": "turret", "distance": 50, "direction": "SE", "gps": "[gps=30,40,nauvis]"},
        {"name": "biter-spawner", "type": "unit-spawner", "distance": 100, "direction": "N", "gps": "[gps=0,-100,nauvis]", "pollution": 12.5},
    ],
    "center": {"surface": "nauvis", "x": 0, "y": 0},
    "radius": 128,
}


async def _setup(stack):
    stack.fake.responses[build_command("hello")] = hello_reply(ALL)
    await stack.bridge.refresh_hello()


async def _call(stack, arguments):
    r = await stack.rpc("tools/call", {"name": "inspect_threats", "arguments": arguments})
    assert r.status_code == 200, r.text
    return r.json()["result"]


async def test_threats_sync_defaults(stack):
    await _setup(stack)
    cmd = build_command("threats", {"caller": "aliceNick", "player": "aliceNick", "radius": 128.0, "limit": 10})
    stack.fake.responses[cmd] = _env(THREATS)
    data = json.loads((await _call(stack, {}))["content"][0]["text"])
    assert data["nearest"][0]["direction"] == "SE" and data["counts"]["biter-spawner"] == 1


async def test_threats_empty_answer(stack):
    await _setup(stack)
    cmd = build_command("threats", {"caller": "aliceNick", "surface": "nauvis", "x": 1.0, "y": 2.0, "radius": 64.0, "limit": 10})
    stack.fake.responses[cmd] = _env({"total": 0, "counts": [], "nearest": [], "center": {}, "radius": 64})
    data = json.loads((await _call(stack, {"gps": "[gps=1,2,nauvis]", "radius": 64}))["content"][0]["text"])
    assert data["counts"] == {} and data["nearest"] == []


async def test_threats_big_radius_runs_as_job(stack):
    await _setup(stack)
    start = build_command(
        "job_start",
        {"kind": "threats", "params": {"caller": "aliceNick", "surface": "nauvis", "x": 5.0, "y": 6.0, "radius": 600.0, "limit": 10}},
    )
    stack.fake.responses[start] = _env({"job_id": 4, "mode": "idle", "work_items": 9})
    stack.fake.responses[build_command("job_result", {"job_id": 4, "offset": 0})] = _env({"state": "done", **THREATS, "radius": 600})
    data = json.loads((await _call(stack, {"gps": "[gps=5,6,nauvis]", "radius": 600}))["content"][0]["text"])
    assert start in stack.fake.received
    assert data["radius"] == 600 and len(data["nearest"]) == 2


async def test_threats_big_radius_uses_players_position(stack):
    await _setup(stack)
    stack.fake.responses[build_command("players")] = _env(
        {"players": [{"name": "aliceNick", "online": True, "position": {"x": 4.5, "y": 6}, "surface": "nauvis"}]}
    )
    start = build_command(
        "job_start",
        {"kind": "threats", "params": {"caller": "aliceNick", "surface": "nauvis", "x": 4.5, "y": 6, "radius": 300.0, "limit": 10}},
    )
    stack.fake.responses[start] = _env({"job_id": 5, "mode": "idle", "work_items": 4})
    stack.fake.responses[build_command("job_result", {"job_id": 5, "offset": 0})] = _env({"state": "done", **THREATS})
    await _call(stack, {"radius": 300})
    assert start in stack.fake.received


async def test_threats_offline_caller_needs_gps(stack):
    await _setup(stack)
    cmd = build_command("threats", {"caller": "aliceNick", "player": "aliceNick", "radius": 128.0, "limit": 10})
    stack.fake.responses[cmd] = json.dumps(
        {"v": 1, "ok": False, "error": {"code": "not_found", "message": "player is offline: position unknown"}}
    )
    res = await _call(stack, {})
    assert res["isError"] is True and "[gps=x,y,surface]" in res["content"][0]["text"]
