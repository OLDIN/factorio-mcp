from __future__ import annotations

import json

from stack_fixture import hello_reply

from factorio_mcp.commands import build_command

ALL = ("hello", "server_info", "players", "resources", "transport", "job_start", "job_result")


def _env(result):
    return json.dumps({"v": 1, "ok": True, "result": result})


async def _setup(stack, subs=ALL):
    stack.fake.responses[build_command("hello")] = hello_reply(subs)
    await stack.bridge.refresh_hello()


async def _tool(stack, name, arguments):
    r = await stack.rpc("tools/call", {"name": name, "arguments": arguments})
    assert r.status_code == 200, r.text
    return r.json()["result"]


def _data(res):
    return json.loads(res["content"][0]["text"])


RESOURCES = {
    "center": {"surface": "nauvis", "x": 0, "y": 0},
    "radius": 64,
    "patches": [
        {"name": "iron-ore", "amount": 120000, "tiles": 300, "gps": "[gps=40,-20,nauvis]", "fluid": False},
        {"name": "crude-oil", "amount": 900000, "wells": 3, "gps": "[gps=-50,10,nauvis]", "fluid": True},
    ],
    "patches_total": 2,
}


async def test_resources_defaults_around_yourself(stack):
    await _setup(stack)
    cmd = build_command("resources", {"caller": "aliceNick", "player": "aliceNick", "radius": 64.0, "limit": 10})
    stack.fake.responses[cmd] = _env(RESOURCES)
    data = _data(await _tool(stack, "inspect_resources", {}))
    assert data["patches"][0]["gps"] == "[gps=40,-20,nauvis]" and data["patches"][1]["wells"] == 3
    assert [c for c in stack.fake.received if c.startswith("/factorio-mcp resources")] == [cmd]


async def test_resources_gps_and_empty(stack):
    await _setup(stack)
    cmd = build_command("resources", {"caller": "aliceNick", "surface": "vulcanus", "x": 5.0, "y": -7.0, "radius": 128.0, "limit": 3})
    stack.fake.responses[cmd] = _env({**RESOURCES, "patches": {}, "patches_total": 0})
    data = _data(await _tool(stack, "inspect_resources", {"gps": "[gps=5,-7,vulcanus]", "radius": 128, "limit": 3}))
    assert data["patches"] == [] and "surface_totals" not in data


async def test_resources_rich_area_runs_as_job(stack):
    # the mod counted too many tiles to read in one tick: the same question runs as a job, at the
    # centre the mod resolved (here the caller's own position)
    await _setup(stack)
    cmd = build_command("resources", {"caller": "aliceNick", "player": "aliceNick", "radius": 128.0, "limit": 10})
    center = {"surface": "nauvis", "x": 12.5, "y": -3.0}
    stack.fake.responses[cmd] = _env({"job_needed": True, "center": center, "radius": 128})
    params = {"caller": "aliceNick", "surface": "nauvis", "x": 12.5, "y": -3.0, "radius": 128.0, "limit": 10}
    start = build_command("job_start", {"kind": "resources", "params": params})
    stack.fake.responses[start] = _env({"job_id": 7, "mode": "idle", "work_items": 4})
    done = {"state": "done", **RESOURCES, "patches": {}, "center": center, "radius": 128}
    stack.fake.responses[build_command("job_result", {"job_id": 7, "offset": 0})] = _env(done)
    data = _data(await _tool(stack, "inspect_resources", {"radius": 128}))
    assert start in stack.fake.received
    assert data["patches"] == [] and data["center"] == center and "job_needed" not in data


async def test_resources_overview(stack):
    await _setup(stack)
    start = build_command(
        "job_start", {"kind": "resources_overview", "params": {"caller": "aliceNick", "surfaces": ["nauvis"]}}
    )
    stack.fake.responses[start] = _env({"job_id": 3, "mode": "idle", "work_items": 30})
    rows = [
        {"surface": "nauvis", "name": "iron-ore", "amount": 9000000, "tiles": 40000, "fluid": False},
        {"surface": "nauvis", "name": "coal", "amount": 4000000, "tiles": 20000, "fluid": False},
        {"surface": "nauvis", "name": "crude-oil", "amount": 3000000, "wells": 12, "fluid": True},
    ]
    done = {"state": "done", "summary": {"surfaces": 1, "resources": 3}, "resources": rows, "total": 3}
    stack.fake.responses[build_command("job_result", {"job_id": 3, "offset": 0})] = _env(done)
    data = _data(await _tool(stack, "base_resources_overview", {"surfaces": ["nauvis", "nauvis"], "limit": 2}))
    assert start in stack.fake.received, "each surface once"
    assert [r["name"] for r in data["resources"]] == ["iron-ore", "coal"]
    assert data["total_resources"] == 3 and data["next"] == 2 and data["summary"]["resources"] == 3


async def test_resources_hidden_on_an_old_mod(stack):
    await _setup(stack, ("hello", "server_info", "players"))
    r = await stack.rpc("tools/list", {})
    names = {t["name"] for t in r.json()["result"]["tools"]}
    assert "inspect_resources" not in names and "inspect_transport" not in names
    assert "base_resources_overview" not in names


TRANSPORT = {
    "center": {"surface": "nauvis", "x": 0, "y": 0},
    "radius": 16,
    "counts": {"transport-belt": 40, "inserter": 3},
    "inserters": {
        "by_status": {"working": 2, "waiting_for_space_in_destination": 1},
        "stuck": [{"name": "inserter", "gps": "[gps=3,4,nauvis]", "status": "waiting_for_space_in_destination"}],
        "stuck_total": 1,
    },
    "belts": {"items": [{"name": "iron-plate", "count": 57}], "read": 38, "total": 38},
    "fluids": [{"name": "water", "amount": 1200}],
}


async def test_transport_defaults_around_yourself(stack):
    await _setup(stack)
    cmd = build_command("transport", {"caller": "aliceNick", "player": "aliceNick", "radius": 16.0, "limit": 15})
    stack.fake.responses[cmd] = _env(TRANSPORT)
    data = _data(await _tool(stack, "inspect_transport", {}))
    assert data["inserters"]["stuck"][0]["status"] == "waiting_for_space_in_destination"
    assert data["belts"]["items"][0]["name"] == "iron-plate"


async def test_transport_another_player_and_empty(stack):
    await _setup(stack)
    cmd = build_command("transport", {"caller": "aliceNick", "player": "bobNick", "radius": 32.0, "limit": 15})
    empty = {**TRANSPORT, "counts": [], "inserters": {"by_status": [], "stuck": {}, "stuck_total": 0},
             "belts": {"items": {}}, "fluids": {}}
    stack.fake.responses[cmd] = _env(empty)
    data = _data(await _tool(stack, "inspect_transport", {"player": "bobNick", "radius": 32}))
    assert data["counts"] == {} and data["inserters"]["by_status"] == {} and data["inserters"]["stuck"] == []
    assert data["belts"]["items"] == [] and data["fluids"] == []
