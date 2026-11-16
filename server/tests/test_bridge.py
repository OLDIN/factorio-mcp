from __future__ import annotations

import asyncio
import json

import pytest
from fake_rcon import FakeRcon

from factorio_mcp.bridge import (
    GameUnavailable,
    ModBridge,
    ModError,
    ModMissing,
    normalize_maps,
)
from factorio_mcp.commands import build_command
from factorio_mcp.rcon import RconLink

HELLO = {
    "v": 1,
    "ok": True,
    "result": {
        "mod_version": "0.1.0",
        "protocol": 1,
        "commands": ["hello", "players"],
        "fingerprint": "base=2.1.24",
        "max_response_bytes": 48000,
    },
}


@pytest.fixture
async def env():
    fake = FakeRcon("secret")
    await fake.start()
    link = RconLink("127.0.0.1", fake.port, "secret", retry_delay=0.05)
    bridge = ModBridge(link)
    task = asyncio.create_task(link.run())
    for _ in range(100):
        if link.alive:
            break
        await asyncio.sleep(0.02)
    yield fake, link, bridge
    task.cancel()
    await asyncio.gather(task, return_exceptions=True)
    await fake.stop()


def _reply(fake, sub, text, args=None):
    fake.responses[build_command(sub, args)] = text if isinstance(text, str) else json.dumps(text)


async def test_hello_ok_and_fingerprint_hashed(env):
    fake, _, bridge = env
    _reply(fake, "hello", HELLO)
    hello = await bridge.refresh_hello()
    assert hello.commands == frozenset({"hello", "players"})
    assert hello.fingerprint != "base=2.1.24" and len(hello.fingerprint) == 64
    assert bridge.last_hello == hello


async def test_hello_changed_callback_fires_once(env):
    fake, _, bridge = env
    seen = []
    bridge.on_hello_changed.append(seen.append)
    _reply(fake, "hello", HELLO)
    await bridge.refresh_hello()
    await bridge.refresh_hello()
    assert len(seen) == 1


async def test_bridge_truncated_json_is_bad_response(env):
    fake, _, bridge = env
    _reply(fake, "players", '{"v":1,"ok":tru')
    with pytest.raises(ModError) as info:
        await bridge.call("players")
    assert info.value.code == "bad_response"


async def test_bridge_unknown_command_means_mod_missing(env):
    fake, _, bridge = env
    _reply(fake, "players", "Unknown command. Type /help for help.")
    with pytest.raises(ModMissing):
        await bridge.call("players")


async def test_bridge_rcon_down_means_game_unavailable():
    link = RconLink("127.0.0.1", 1, "x")
    bridge = ModBridge(link)
    with pytest.raises(GameUnavailable):
        await bridge.call("players")


async def test_bridge_error_envelope_maps_to_mod_error(env):
    fake, _, bridge = env
    _reply(fake, "players", {"v": 1, "ok": False, "error": {"code": "not_found", "message": "no"}})
    with pytest.raises(ModError) as info:
        await bridge.call("players")
    assert (info.value.code, info.value.message) == ("not_found", "no")


async def test_protocol_mismatch(env):
    fake, _, bridge = env
    _reply(fake, "players", {"v": 2, "ok": True, "result": {}})
    with pytest.raises(ModError) as info:
        await bridge.call("players")
    assert info.value.code == "protocol_mismatch"


async def test_call_returns_result(env):
    fake, _, bridge = env
    _reply(fake, "players", {"v": 1, "ok": True, "result": {"players": []}})
    assert await bridge.call("players") == {"players": []}


def test_normalize_maps_turns_list_into_dict():
    data = {"items": [{"by_status": []}, {"by_status": {"working": 1}}], "top": [], "keep": []}
    out = normalize_maps(data, ["items.*.by_status", "top"])
    assert out["items"][0]["by_status"] == {}
    assert out["items"][1]["by_status"] == {"working": 1}
    assert out["top"] == {}
    assert out["keep"] == []
