from __future__ import annotations

import json

from stack_fixture import hello_reply

from factorio_mcp.commands import build_command

ALL = ("hello", "server_info", "players", "research")


def _env(result):
    return json.dumps({"v": 1, "ok": True, "result": result})


async def _setup(stack):
    stack.fake.responses[build_command("hello")] = hello_reply(ALL)
    await stack.bridge.refresh_hello()


async def _call(stack, arguments):
    r = await stack.rpc("tools/call", {"name": "research_status", "arguments": arguments})
    assert r.status_code == 200, r.text
    return r.json()["result"]


async def test_research_overview(stack):
    await _setup(stack)
    cmd = build_command("research", {"caller": "aliceNick", "offset": 0, "limit": 20})
    stack.fake.responses[cmd] = _env({
        "current": {"name": "automation", "level": 1, "progress": 0.25},
        "queue": {},  # an empty Lua table arrives as {} or []
        "researched": 3, "total": 200,
        "available": {"total": 1, "offset": 0, "items": ["logistics"]},
    })
    data = json.loads((await _call(stack, {}))["content"][0]["text"])
    assert data["current"]["name"] == "automation"
    assert data["queue"] == []
    assert data["available"]["items"] == ["logistics"] and data["available"].get("next") is None


async def test_research_nothing_running(stack):
    await _setup(stack)
    cmd = build_command("research", {"caller": "aliceNick", "offset": 20, "limit": 5})
    stack.fake.responses[cmd] = _env(
        {"queue": [], "researched": 0, "total": 10, "available": {"total": 30, "offset": 20, "items": [], "next": 25}}
    )
    data = json.loads((await _call(stack, {"offset": 20, "limit": 5}))["content"][0]["text"])
    assert data["current"] is None
    assert data["available"]["next"] == 25


async def test_research_by_name(stack):
    await _setup(stack)
    cmd = build_command("research", {"caller": "aliceNick", "offset": 0, "limit": 20, "name": "electronics"})
    stack.fake.responses[cmd] = _env({
        "name": "electronics", "level": 1, "researched": False, "enabled": True, "progress": 0,
        "unit_count": 30, "ingredients": [{"name": "automation-science-pack", "amount": 1}],
        "missing_prerequisites": {},
    })
    data = json.loads((await _call(stack, {"name": "electronics"}))["content"][0]["text"])
    assert data["missing_prerequisites"] == []
    assert data["ingredients"][0]["amount"] == 1


async def test_research_unknown_name(stack):
    await _setup(stack)
    cmd = build_command("research", {"caller": "aliceNick", "offset": 0, "limit": 20, "name": "nope"})
    stack.fake.responses[cmd] = json.dumps(
        {"v": 1, "ok": False, "error": {"code": "not_found", "message": "no such technology"}}
    )
    res = await _call(stack, {"name": "nope"})
    assert res["isError"] is True and res["content"][0]["text"].endswith("no such technology")
