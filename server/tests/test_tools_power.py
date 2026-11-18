from __future__ import annotations

import json

from stack_fixture import hello_reply

from factorio_mcp.commands import build_command

ALL = ("hello", "server_info", "players", "power")

POWER = {
    "v": 1,
    "ok": True,
    "result": {
        "center": {"surface": "nauvis", "x": 0, "y": 0},
        "radius": 32,
        "window": "5s",
        "networks": [
            {
                "id": 7,
                "poles": 3,
                "gps": "[gps=1,2,nauvis]",
                "produced_kw": 240,
                "consumed_kw": 2.5,
                "top_producers": [{"name": "solar-panel", "kw": 240}],
                "top_consumers": [],
                "accumulators": {"count": 0},
                "starved": {"low_power": 2, "no_power": 0},
            }
        ],
        "networks_total": 1,
        "starved_examples": [],
    },
}


async def _setup(stack):
    stack.fake.responses[build_command("hello")] = hello_reply(ALL)
    await stack.bridge.refresh_hello()


async def _call(stack, arguments):
    r = await stack.rpc("tools/call", {"name": "inspect_power", "arguments": arguments})
    assert r.status_code == 200, r.text
    return r.json()["result"]


async def test_power_defaults(stack):
    await _setup(stack)
    cmd = build_command("power", {"caller": "aliceNick", "player": "aliceNick", "radius": 32.0, "limit": 10})
    stack.fake.responses[cmd] = json.dumps(POWER)
    data = json.loads((await _call(stack, {}))["content"][0]["text"])
    assert data["networks"][0]["produced_kw"] == 240
    assert data["networks"][0]["top_consumers"] == []
    assert data["starved_examples"] == []


async def test_power_gps(stack):
    await _setup(stack)
    cmd = build_command("power", {"caller": "aliceNick", "surface": "gleba", "x": 5.0, "y": -5.0, "radius": 64.0, "limit": 10})
    stack.fake.responses[cmd] = json.dumps(POWER)
    data = json.loads((await _call(stack, {"gps": "[gps=5,-5,gleba]", "radius": 64}))["content"][0]["text"])
    assert data["networks_total"] == 1


async def test_power_offline_caller_needs_gps(stack):
    await _setup(stack)
    cmd = build_command("power", {"caller": "aliceNick", "player": "aliceNick", "radius": 32.0, "limit": 10})
    stack.fake.responses[cmd] = json.dumps(
        {"v": 1, "ok": False, "error": {"code": "not_found", "message": "player is offline: position unknown"}}
    )
    res = await _call(stack, {})
    assert res["isError"] is True
    assert "[gps=x,y,surface]" in res["content"][0]["text"]


def _env(result):
    return json.dumps({"v": 1, "ok": True, "result": result})


OVERVIEW_NETS = [
    {"id": 9, "surface": "nauvis", "poles": 4, "gps": "[gps=1,1,nauvis]", "produced_kw": 100, "consumed_kw": 90,
     "top_producers": [], "top_consumers": {}, "starved": {"low_power": 2, "no_power": 0}, "accumulators": {"count": 0}},
    {"id": 7, "surface": "nauvis", "poles": 30, "gps": "[gps=5,5,nauvis]", "produced_kw": 900, "consumed_kw": 400,
     "top_producers": [], "top_consumers": [], "starved": [], "accumulators": {"count": 2, "charge": 0.5}},
]


async def test_base_power_overview_visible_only_with_power_command(stack):
    stack.fake.responses[build_command("hello")] = hello_reply(("hello", "job_start", "job_result"))
    await stack.bridge.refresh_hello()
    assert "base_power_overview" not in await stack.tool_names()  # a 0.3.0 mod has job_start but no power kind
    await _setup(stack)
    assert "base_power_overview" in await stack.tool_names()


async def test_base_power_overview_collects_and_pages(stack):
    stack.fake.responses[build_command("hello")] = hello_reply(ALL + ("job_start", "job_result"))
    await stack.bridge.refresh_hello()
    start = build_command("job_start", {"kind": "power_overview", "params": {"caller": "aliceNick"}})
    stack.fake.responses[start] = _env({"job_id": 3, "mode": "idle", "work_items": 4})
    stack.fake.responses[build_command("job_result", {"job_id": 3, "offset": 0})] = _env(
        {"state": "done", "summary": {"networks": 3, "starved_networks": 1, "tiny": 1}, "networks": OVERVIEW_NETS, "total": 2}
    )
    r = await stack.rpc("tools/call", {"name": "base_power_overview", "arguments": {"limit": 1}})
    data = json.loads(r.json()["result"]["content"][0]["text"])
    assert start in stack.fake.received
    assert data["summary"]["tiny"] == 1
    assert [n["id"] for n in data["networks"]] == [9]
    assert data["networks"][0]["top_consumers"] == []
    assert data["total_networks"] == 2 and data["next"] == 1


async def test_base_power_overview_unknown_caller(stack):
    stack.fake.responses[build_command("hello")] = hello_reply(ALL + ("job_start", "job_result"))
    await stack.bridge.refresh_hello()
    start = build_command("job_start", {"kind": "power_overview", "params": {"caller": "aliceNick"}})
    stack.fake.responses[start] = json.dumps(
        {"v": 1, "ok": False, "error": {"code": "not_found", "message": "no such player"}}
    )
    r = await stack.rpc("tools/call", {"name": "base_power_overview", "arguments": {}})
    res = r.json()["result"]
    assert res["isError"] is True and res["content"][0]["text"].endswith("no such player")
