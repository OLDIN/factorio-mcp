from __future__ import annotations

import json

import pytest

pytestmark = pytest.mark.live


async def call(rcon, command: str) -> dict:
    reply = await rcon.exec(command, timeout=10)
    return json.loads(reply)


async def test_hello(rcon, game_log_errors):
    errors_before = game_log_errors()
    reply = await call(rcon, "/factorio-mcp hello")
    assert reply["v"] == 1 and reply["ok"] is True
    result = reply["result"]
    assert result["protocol"] == 1
    assert "hello" in result["commands"]
    assert result["mod_version"]
    assert "mod:base=" in result["fingerprint"] and "mod:factorio-mcp=" in result["fingerprint"]
    assert result["max_response_bytes"] > 0
    assert game_log_errors() == errors_before


async def test_unknown_command_is_a_json_error_not_a_lua_error(rcon, game_log_errors):
    errors_before = game_log_errors()
    reply = await call(rcon, "/factorio-mcp nope")
    assert reply["ok"] is False
    assert reply["error"]["code"] == "unknown_command"
    assert game_log_errors() == errors_before


async def test_garbage_parameters_are_bad_params(rcon, game_log_errors):
    errors_before = game_log_errors()
    for command in ("/factorio-mcp hello {x", "/factorio-mcp hello []", "/factorio-mcp hello 5"):
        reply = await call(rcon, command)
        assert reply["ok"] is False and reply["error"]["code"] == "bad_params", command
    assert game_log_errors() == errors_before
