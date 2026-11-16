from __future__ import annotations

import json

from stack_fixture import TOKEN_BOB, hello_reply

from factorio_mcp.commands import build_command

ALL = ("hello", "server_info", "players", "area")
AREA = {"v": 1, "ok": True, "result": {
    "center": {"surface": "nauvis", "x": 1, "y": 2}, "radius": 32, "truncated": False,
    "totals": {"machines": 0, "working": 0, "by_status": []}, "groups": {}, "stopped": {}, "drills": {}}}


async def _setup(stack):
    stack.fake.responses[build_command("hello")] = hello_reply(ALL)
    await stack.bridge.refresh_hello()


def _area_commands(stack) -> list[str]:
    return [c for c in stack.fake.received if "area" in c and not c.startswith("/factorio-mcp hello")]


async def _call(stack, arguments, token=None):
    kwargs = {"token": token} if token else {}
    r = await stack.rpc("tools/call", {"name": "inspect_area", "arguments": arguments}, **kwargs)
    assert r.status_code == 200, r.text
    return r.json()["result"]


async def test_no_arguments_uses_nick_from_token(stack):
    await _setup(stack)
    stack.fake.responses[build_command("area", {"radius": 32.0, "player": "aliceNick"})] = json.dumps(AREA)
    res = await _call(stack, {})
    data = json.loads(res["content"][0]["text"])
    assert data["groups"] == [] and data["stopped"] == [] and data["totals"]["by_status"] == {}
    assert _area_commands(stack) == [build_command("area", {"radius": 32.0, "player": "aliceNick"})]


async def test_other_token_means_other_nick(stack):
    await _setup(stack)
    stack.fake.responses[build_command("area", {"radius": 32.0, "player": "bobNick"})] = json.dumps(AREA)
    await _call(stack, {"nick": "aliceNick"}, token=TOKEN_BOB)  # an extra "nick" argument is ignored
    assert "bobNick" in _area_commands(stack)[0] and "aliceNick" not in _area_commands(stack)[0]


async def test_no_tool_has_a_nick_parameter(stack):
    await _setup(stack)
    tools = (await stack.rpc("tools/list")).json()["result"]["tools"]
    assert "inspect_area" in {t["name"] for t in tools}
    assert all("nick" not in json.dumps(t["inputSchema"]) for t in tools)


async def test_gps_is_parsed_into_structured_args(stack):
    await _setup(stack)
    cmd = build_command("area", {"radius": 10.0, "surface": "vulcanus", "x": 1.5, "y": -2.0})
    stack.fake.responses[cmd] = json.dumps(AREA)
    await _call(stack, {"gps": "look [gps=1.5,-2,vulcanus]", "radius": 10})
    assert _area_commands(stack) == [cmd]


async def test_bad_gps_is_refused_without_rcon(stack):
    await _setup(stack)
    before = list(stack.fake.received)
    res = await _call(stack, {"gps": "[gps=1,2,na\nuvis]"})
    assert res["isError"] is True and "gps" in res["content"][0]["text"].lower()
    assert stack.fake.received == before  # nothing was sent to the game


async def test_player_argument_targets_that_player(stack):
    await _setup(stack)
    cmd = build_command("area", {"radius": 32.0, "player": "carol"})
    stack.fake.responses[cmd] = json.dumps(AREA)
    await _call(stack, {"player": "carol"})
    assert _area_commands(stack) == [cmd]
