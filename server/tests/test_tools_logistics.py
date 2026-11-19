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


TRAINS = {
    "by_state": {"on_the_path": 3, "no_path": 1}, "total": 4, "problems_total": 1,
    "trains": [{"id": 9, "state": "no_path", "surface": "nauvis", "gps": "[gps=1,2,nauvis]", "target": "Iron",
                "waiting_ticks": 0, "cargo": {}, "fluids": [], "problem": "no_path"}],
}


async def test_trains_default(stack):
    await _setup(stack)
    cmd = build_command("trains", {"caller": "aliceNick", "problems_only": False, "offset": 0, "limit": 15})
    stack.fake.responses[cmd] = _env(TRAINS)
    data = _data(await _tool(stack, "list_trains", {}))
    assert data["trains"][0]["problem"] == "no_path"
    assert data["trains"][0]["cargo"] == [] and data.get("next") is None


async def test_trains_problems_only_on_a_surface(stack):
    await _setup(stack)
    cmd = build_command(
        "trains", {"caller": "aliceNick", "problems_only": True, "offset": 0, "limit": 5, "surface": "nauvis"}
    )
    stack.fake.responses[cmd] = _env({**TRAINS, "next": 5})
    data = _data(await _tool(stack, "list_trains", {"problems_only": True, "limit": 5, "surface": "nauvis"}))
    assert data["next"] == 5


async def test_trains_none(stack):
    await _setup(stack)
    cmd = build_command("trains", {"caller": "aliceNick", "problems_only": False, "offset": 0, "limit": 15})
    stack.fake.responses[cmd] = _env({"by_state": [], "total": 0, "problems_total": 0, "trains": {}})
    data = _data(await _tool(stack, "list_trains", {}))
    assert data["trains"] == [] and data["by_state"] == {}


async def test_platforms_none(stack):
    await _setup(stack)
    cmd = build_command("platforms", {"caller": "aliceNick", "limit": 10})
    stack.fake.responses[cmd] = _env({"platforms": {}, "total": 0})
    data = _data(await _tool(stack, "list_platforms", {}))
    assert data["platforms"] == [] and data["total"] == 0


async def test_platforms_by_name(stack):
    await _setup(stack)
    cmd = build_command("platforms", {"caller": "aliceNick", "limit": 10, "name": "Alpha"})
    stack.fake.responses[cmd] = _env({"total": 1, "platforms": [{
        "name": "Alpha", "state": "on_the_path", "last_location": "nauvis", "speed": 0.5, "distance": 0.25,
        "damaged_tiles": 0, "hub_contents": {}}]})
    data = _data(await _tool(stack, "list_platforms", {"name": "Alpha"}))
    assert data["platforms"][0]["hub_contents"] == []


async def test_platforms_unknown_name(stack):
    await _setup(stack)
    cmd = build_command("platforms", {"caller": "aliceNick", "limit": 10, "name": "Nope"})
    stack.fake.responses[cmd] = json.dumps({"v": 1, "ok": False, "error": {"code": "not_found", "message": "no such platform"}})
    res = await _tool(stack, "list_platforms", {"name": "Nope"})
    assert res["isError"] is True and res["content"][0]["text"].endswith("no such platform")
