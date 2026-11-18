from __future__ import annotations

import pytest
from mcp.server.mcpserver.exceptions import ToolError

from factorio_mcp.bridge import ModError
from factorio_mcp.identity import reset_identity, set_identity
from factorio_mcp.tokens import Identity
from factorio_mcp.tools.common import call_mod, caller_args, point_args


@pytest.fixture
def alice():
    token = set_identity(Identity(name="alice", nick="aliceNick"))
    yield
    reset_identity(token)


def test_point_args_from_gps(alice):
    assert point_args("[gps=1,2,gleba]", None) == {"surface": "gleba", "x": 1.0, "y": 2.0}


def test_point_args_from_player(alice):
    assert point_args(None, "bob") == {"player": "bob"}


def test_point_args_defaults_to_token_nick(alice):
    assert point_args(None, None) == {"player": "aliceNick"}


def test_point_args_bad_gps(alice):
    with pytest.raises(ToolError, match="Could not read the gps tag"):
        point_args("[gps=oops]", None)


def test_caller_args_is_the_token_nick(alice):
    assert caller_args() == {"caller": "aliceNick"}


class _Bridge:
    def __init__(self, error=None, result=None):
        self.error, self.result, self.calls = error, result, []

    async def call(self, sub, args):
        self.calls.append((sub, args))
        if self.error:
            raise self.error
        return self.result


async def test_call_mod_turns_not_found_into_tool_error():
    with pytest.raises(ToolError, match="^no such player$"):
        await call_mod(_Bridge(ModError("not_found", "no such player")), "production", {"caller": "x"})


async def test_call_mod_turns_bad_params_into_tool_error():
    with pytest.raises(ToolError, match="limit must be"):
        await call_mod(_Bridge(ModError("bad_params", "limit must be an integer between 1 and 50")), "production", {})


async def test_call_mod_keeps_other_errors():
    with pytest.raises(ModError):
        await call_mod(_Bridge(ModError("internal", "boom")), "production", {})


async def test_call_mod_returns_result():
    bridge = _Bridge(result={"ok": 1})
    assert await call_mod(bridge, "production", {"caller": "a"}) == {"ok": 1}
    assert bridge.calls == [("production", {"caller": "a"})]


async def test_call_mod_offline_player_suggests_gps():
    with pytest.raises(ToolError, match=r"give a \[gps=x,y,surface\] tag"):
        await call_mod(_Bridge(ModError("not_found", "player is offline: position unknown")), "power", {})
