from __future__ import annotations

import json

from stack_fixture import TOKEN_BOB, hello_reply

from factorio_mcp.commands import build_command

ALL = ("hello", "server_info", "players", "inventory", "alerts")


def _env(result):
    return json.dumps({"v": 1, "ok": True, "result": result})


async def _setup(stack):
    stack.fake.responses[build_command("hello")] = hello_reply(ALL)
    await stack.bridge.refresh_hello()


async def _tool(stack, name, arguments, token=None):
    kwargs = {"token": token} if token else {}
    r = await stack.rpc("tools/call", {"name": name, "arguments": arguments}, **kwargs)
    assert r.status_code == 200, r.text
    return r.json()["result"]


async def _schema(stack, name):
    r = await stack.rpc("tools/list", {})
    return next(t for t in r.json()["result"]["tools"] if t["name"] == name)["inputSchema"]


async def test_my_inventory_uses_token_nick_only(stack):
    await _setup(stack)
    cmd = build_command("inventory", {"caller": "aliceNick"})
    stack.fake.responses[cmd] = _env({"online": True, "readable": True, "main": [{"name": "coal", "quality": "normal", "count": 5}],
                                      "guns": {}, "ammo": [], "crafting_queue_size": 0})
    data = json.loads((await _tool(stack, "my_inventory", {}))["content"][0]["text"])
    assert data["main"][0]["name"] == "coal" and data["guns"] == []
    assert [c for c in stack.fake.received if c.startswith("/factorio-mcp inventory")] == [cmd]
    assert "player" not in (await _schema(stack, "my_inventory")).get("properties", {})


async def test_my_inventory_ignores_a_player_argument(stack):
    await _setup(stack)
    cmd = build_command("inventory", {"caller": "aliceNick"})
    stack.fake.responses[cmd] = _env({"online": False, "readable": False})
    await _tool(stack, "my_inventory", {"player": "bobNick"})
    sent = [c for c in stack.fake.received if c.startswith("/factorio-mcp inventory")]
    assert sent == [cmd], "another player's name never reaches the mod"


async def test_my_alerts_uses_token_nick_only(stack):
    await _setup(stack)
    cmd = build_command("alerts", {"caller": "bobNick", "limit": 5})
    stack.fake.responses[cmd] = _env({"online": True, "by_type": [{"type": "turret_out_of_ammo", "count": 2, "examples": {}}]})
    data = json.loads((await _tool(stack, "my_alerts", {}, token=TOKEN_BOB))["content"][0]["text"])
    assert data["by_type"][0]["examples"] == []
    assert [c for c in stack.fake.received if c.startswith("/factorio-mcp alerts")] == [cmd]
    assert "player" not in (await _schema(stack, "my_alerts")).get("properties", {})


async def test_my_alerts_none(stack):
    await _setup(stack)
    cmd = build_command("alerts", {"caller": "aliceNick", "limit": 5})
    stack.fake.responses[cmd] = _env({"online": False, "by_type": {}})
    data = json.loads((await _tool(stack, "my_alerts", {}))["content"][0]["text"])
    assert data["by_type"] == []
