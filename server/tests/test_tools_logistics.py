from __future__ import annotations

import json

from stack_fixture import hello_reply

from factorio_mcp.commands import build_command

ALL = ("hello", "server_info", "players", "logistics", "trains", "platforms")


def _env(result):
    return json.dumps({"v": 1, "ok": True, "result": result})


async def _setup(stack):
    stack.fake.responses[build_command("hello")] = hello_reply(ALL)
    await stack.bridge.refresh_hello()


async def _tool(stack, name, arguments):
    r = await stack.rpc("tools/call", {"name": name, "arguments": arguments})
    assert r.status_code == 200, r.text
    return r.json()["result"]


def _data(res):
    return json.loads(res["content"][0]["text"])


async def test_logistics_default(stack):
    await _setup(stack)
    cmd = build_command("logistics", {"caller": "aliceNick", "limit": 15})
    stack.fake.responses[cmd] = _env({"total": 1, "networks": [{
        "surface": "nauvis", "id": 1, "gps": "[gps=1,1,nauvis]", "roboports": 4, "charging": 2,
        "logistic_robots": {"available": 1, "total": 10}, "construction_robots": {"available": 5, "total": 5},
        "top_contents": [{"name": "iron-plate", "quality": "normal", "count": 500}]}]})
    data = _data(await _tool(stack, "logistic_networks", {}))
    assert data["networks"][0]["logistic_robots"]["total"] == 10


async def test_logistics_by_name(stack):
    await _setup(stack)
    cmd = build_command("logistics", {"caller": "aliceNick", "limit": 15, "surface": "nauvis", "name": "iron-plate"})
    stack.fake.responses[cmd] = _env({"name": "iron-plate", "total": 505, "by_network": [{"surface": "nauvis", "id": 1, "count": 505}]})
    data = _data(await _tool(stack, "logistic_networks", {"surface": "nauvis", "name": "iron-plate"}))
    assert data["total"] == 505


async def test_logistics_none(stack):
    await _setup(stack)
    cmd = build_command("logistics", {"caller": "aliceNick", "limit": 15})
    stack.fake.responses[cmd] = _env({"total": 0, "networks": {}})
    data = _data(await _tool(stack, "logistic_networks", {}))
    assert data["networks"] == [] and data["total"] == 0


async def test_logistics_unknown_caller(stack):
    await _setup(stack)
    cmd = build_command("logistics", {"caller": "aliceNick", "limit": 15})
    stack.fake.responses[cmd] = json.dumps({"v": 1, "ok": False, "error": {"code": "not_found", "message": "no such player"}})
    res = await _tool(stack, "logistic_networks", {})
    assert res["isError"] is True and res["content"][0]["text"].endswith("no such player")
