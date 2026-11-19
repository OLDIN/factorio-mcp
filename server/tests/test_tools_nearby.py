from __future__ import annotations

import json

from stack_fixture import hello_reply

from factorio_mcp.commands import build_command

ALL = ("hello", "server_info", "players", "resources")


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
    "surface_totals": {"iron-ore": 5000, "crude-oil": 12},
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
    stack.fake.responses[cmd] = _env({**RESOURCES, "patches": {}, "patches_total": 0, "surface_totals": []})
    data = _data(await _tool(stack, "inspect_resources", {"gps": "[gps=5,-7,vulcanus]", "radius": 128, "limit": 3}))
    assert data["patches"] == [] and data["surface_totals"] == {}


async def test_resources_hidden_on_an_old_mod(stack):
    await _setup(stack, ("hello", "server_info", "players"))
    r = await stack.rpc("tools/list", {})
    names = {t["name"] for t in r.json()["result"]["tools"]}
    assert "inspect_resources" not in names
