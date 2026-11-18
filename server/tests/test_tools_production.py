from __future__ import annotations

import json

from stack_fixture import hello_reply

from factorio_mcp.commands import build_command

ALL = ("hello", "server_info", "players", "production")

SUMMARY = {
    "v": 1,
    "ok": True,
    "result": {
        "window": "1m",
        "surfaces": ["nauvis"],
        "items": {
            "top_produced": [{"name": "iron-plate", "produced": 180, "consumed": 200, "net": -20}],
            "top_consumed": [{"name": "iron-plate", "produced": 180, "consumed": 200, "net": -20}],
            "deficits": [{"name": "iron-plate", "produced": 180, "consumed": 200, "net": -20}],
        },
        "fluids": {"top_produced": [], "top_consumed": [], "deficits": []},
    },
}


async def _setup(stack):
    stack.fake.responses[build_command("hello")] = hello_reply(ALL)
    await stack.bridge.refresh_hello()


async def _call(stack, arguments):
    r = await stack.rpc("tools/call", {"name": "production_stats", "arguments": arguments})
    assert r.status_code == 200, r.text
    return r.json()["result"]


def _sent(stack):
    return [c for c in stack.fake.received if c.startswith("/factorio-mcp production")]


async def test_production_default_window_and_caller(stack):
    await _setup(stack)
    cmd = build_command("production", {"caller": "aliceNick", "window": "1m", "limit": 15})
    stack.fake.responses[cmd] = json.dumps(SUMMARY)
    data = json.loads((await _call(stack, {}))["content"][0]["text"])
    assert data["items"]["deficits"][0]["net"] == -20
    assert _sent(stack) == [cmd]


async def test_production_by_name(stack):
    await _setup(stack)
    cmd = build_command(
        "production", {"caller": "aliceNick", "window": "10m", "limit": 15, "surface": "nauvis", "name": "iron-plate"}
    )
    reply = {
        "v": 1,
        "ok": True,
        "result": {
            "window": "10m",
            "name": "iron-plate",
            "kind": "item",
            "total": {"produced": 120, "consumed": 100, "net": 20},
            "by_surface": [{"surface": "nauvis", "produced": 120, "consumed": 100, "net": 20}],
            "by_quality": {"normal": 100, "rare": 20},
        },
    }
    stack.fake.responses[cmd] = json.dumps(reply)
    res = await _call(stack, {"window": "10m", "surface": "nauvis", "name": "iron-plate"})
    data = json.loads(res["content"][0]["text"])
    assert data["total"]["net"] == 20 and data["by_quality"]["rare"] == 20


async def test_production_bad_window(stack):
    await _setup(stack)
    cmd = build_command("production", {"caller": "aliceNick", "window": "2m", "limit": 15})
    stack.fake.responses[cmd] = json.dumps(
        {"v": 1, "ok": False, "error": {"code": "bad_params", "message": "window must be one of: 5s, 1m, 10m, 1h, 10h"}}
    )
    res = await _call(stack, {"window": "2m"})
    assert res["isError"] is True
    assert "5s, 1m, 10m, 1h, 10h" in res["content"][0]["text"]


async def test_production_empty_surface(stack):
    await _setup(stack)
    cmd = build_command("production", {"caller": "aliceNick", "window": "1m", "limit": 15, "surface": "platform-1"})
    empty = {"top_produced": [], "top_consumed": [], "deficits": []}
    stack.fake.responses[cmd] = json.dumps(
        {"v": 1, "ok": True, "result": {"window": "1m", "surfaces": ["platform-1"], "items": empty, "fluids": empty}}
    )
    data = json.loads((await _call(stack, {"surface": "platform-1"}))["content"][0]["text"])
    assert data["items"] == empty and data["fluids"] == empty


async def test_production_empty_tables_become_lists(stack):
    await _setup(stack)
    cmd = build_command("production", {"caller": "aliceNick", "window": "1m", "limit": 15})
    # the mod's JSON encoder writes an empty table as [] whether it is a list or a map
    lua_empty = {"top_produced": [], "top_consumed": [], "deficits": []}
    stack.fake.responses[cmd] = json.dumps(
        {"v": 1, "ok": True, "result": {"window": "1m", "surfaces": [], "items": lua_empty, "fluids": []}}
    )
    data = json.loads((await _call(stack, {}))["content"][0]["text"])
    assert data["fluids"] == {"top_produced": [], "top_consumed": [], "deficits": []}


async def test_production_unknown_caller(stack):
    await _setup(stack)
    cmd = build_command("production", {"caller": "aliceNick", "window": "1m", "limit": 15})
    stack.fake.responses[cmd] = json.dumps(
        {"v": 1, "ok": False, "error": {"code": "not_found", "message": "no such player"}}
    )
    res = await _call(stack, {})
    assert res["isError"] is True
    assert res["content"][0]["text"].endswith(": no such player")
