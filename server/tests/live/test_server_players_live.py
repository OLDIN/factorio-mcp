from __future__ import annotations

import json
import pytest

pytestmark = pytest.mark.live


async def call(rcon, command: str) -> dict:
    reply = await rcon.exec(command, timeout=10)
    return json.loads(reply)


async def test_server_info_live(rcon, game_log_errors):
    errors_before = game_log_errors()
    reply = await call(rcon, "/factorio-mcp server_info")
    assert reply["v"] == 1 and reply["ok"] is True
    res = reply["result"]

    assert isinstance(res["tick"], int)
    assert isinstance(res["ticks_played"], int)
    assert isinstance(res["paused"], bool)
    assert isinstance(res["speed"], (int, float))
    assert isinstance(res["players_online"], int)

    # mods
    assert "base" in res["mods"]
    assert "factorio-mcp" in res["mods"]

    # surfaces
    assert isinstance(res["surfaces"], list)
    assert any(s["name"] == "nauvis" for s in res["surfaces"])

    # mod_settings redaction
    mod_settings = res.get("mod_settings", {})
    for category in ("startup", "runtime_global"):
        cat_settings = mod_settings.get(category, {})
        for name, val in cat_settings.items():
            lower = name.lower()
            if any(secret in lower for secret in ("token", "secret", "password")):
                val_content = val.get("value") if isinstance(val, dict) else val
                assert not isinstance(val_content, str), f"Secret setting {name} was not redacted!"

    assert game_log_errors() == errors_before


async def test_players_live(rcon, game_log_errors):
    errors_before = game_log_errors()
    reply = await call(rcon, "/factorio-mcp players")
    assert reply["v"] == 1 and reply["ok"] is True
    res = reply["result"]

    players = res["players"]
    # Empty Lua table is serialized as {} by Factorio table_to_json
    if isinstance(players, dict) and not players:
        players = []
    assert isinstance(players, list)
    for p in players:
        assert "name" in p
        assert "index" in p
        assert isinstance(p["online"], bool)
        assert isinstance(p["admin"], bool)
        assert "afk_ticks" in p
        assert "online_ticks" in p
        assert "color" in p
        if not p["online"]:
            assert p.get("position") is None
            assert p.get("surface") is None

    assert game_log_errors() == errors_before
