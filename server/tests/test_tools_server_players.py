from __future__ import annotations

import json
import logging

from stack_fixture import TOKEN_BOB

SERVER_INFO = {"v": 1, "ok": True, "result": {"tick": 5, "mods": {"base": "2.1.24"}}}
PLAYERS = {"v": 1, "ok": True, "result": {"players": [{"name": "alice", "online": True}]}}


async def _call(stack, name, arguments=None, token=None):
    kwargs = {"token": token} if token else {}
    r = await stack.rpc("tools/call", {"name": name, "arguments": arguments or {}}, **kwargs)
    assert r.status_code == 200, r.text
    return r.json()["result"]


async def test_server_status_ok(stack):
    stack.reply("server_info", SERVER_INFO)
    res = await _call(stack, "server_status")
    data = json.loads(res["content"][0]["text"])
    assert data["status"] == "ok" and data["mods"] == {"base": "2.1.24"}


async def test_server_status_when_mod_missing_is_honest(stack):
    stack.reply("server_info", "Unknown command. Type /help for help.")
    data = json.loads((await _call(stack, "server_status"))["content"][0]["text"])
    assert data == {"status": "mod not installed"}


async def test_server_status_when_game_unavailable_is_honest(stack):
    stack.link._drop()
    stack.link._retry_delay = 60
    data = json.loads((await _call(stack, "server_status"))["content"][0]["text"])
    assert data == {"status": "game unavailable"}


async def test_list_players(stack):
    stack.reply("players", PLAYERS)
    data = json.loads((await _call(stack, "list_players"))["content"][0]["text"])
    assert data["players"][0]["name"] == "alice"


async def test_identity_comes_from_token_not_arguments(stack, caplog):
    stack.reply("players", PLAYERS)
    with caplog.at_level(logging.INFO, logger="factorio_mcp.audit"):
        await _call(stack, "list_players", {"nick": "bob"}, token=None)  # alice's token
    assert "who=alice" in caplog.text and "who=bob" not in caplog.text
    tools = (await stack.rpc("tools/list")).json()["result"]["tools"]
    for tool in tools:
        assert "nick" not in tool["inputSchema"].get("properties", {})
        assert "nick" not in json.dumps(tool["inputSchema"])
    assert TOKEN_BOB  # bob exists; his token is not used above


async def test_audit_line_has_who_tool_ms_and_no_arguments(stack, caplog):
    stack.reply("players", PLAYERS)
    with caplog.at_level(logging.INFO, logger="factorio_mcp.audit"):
        await _call(stack, "list_players", {"secret_argument": "XYZZY"})
    lines = [r.getMessage() for r in caplog.records if r.name == "factorio_mcp.audit"]
    assert len(lines) == 1
    assert lines[0].startswith("who=alice tool=list_players ms=") and lines[0].endswith("outcome=ok")
    assert "XYZZY" not in caplog.text
