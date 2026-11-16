from __future__ import annotations

import logging

from stack_fixture import RCON_PASSWORD, TOKEN_ALICE, TOKEN_BOB

from factorio_mcp.config import Settings


async def test_token_and_rcon_password_never_logged(stack, caplog):
    caplog.set_level(logging.DEBUG)
    stack.reply("server_info", "garbage{")
    stack.reply("players", {"v": 1, "ok": False, "error": {"code": "internal", "message": "boom"}})
    await stack.client.post(f"/mcp?token={TOKEN_ALICE}", json={}, headers=stack.auth())
    await stack.client.post("/mcp", json={}, headers={"Authorization": "Bearer nope-token"})
    await stack.rpc("tools/call", {"name": "server_status", "arguments": {}})
    await stack.rpc("tools/call", {"name": "list_players", "arguments": {}}, token=TOKEN_BOB)
    await stack.client.get("/health")
    stack.link._drop()
    await stack.rpc("tools/call", {"name": "server_status", "arguments": {}})
    for secret in (TOKEN_ALICE, TOKEN_BOB, RCON_PASSWORD, "nope-token"):
        assert secret not in caplog.text


async def test_rcon_password_not_in_any_tool_output(stack):
    for name in ("server_status", "list_players"):
        r = await stack.rpc("tools/call", {"name": name, "arguments": {}})
        assert RCON_PASSWORD not in r.text
    r = await stack.rpc("tools/list")
    assert RCON_PASSWORD not in r.text


def test_settings_repr_has_no_password():
    s = Settings(rcon_password=RCON_PASSWORD)
    assert RCON_PASSWORD not in repr(s) and RCON_PASSWORD not in str(s)
