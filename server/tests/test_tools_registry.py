from __future__ import annotations

from stack_fixture import hello_reply

from factorio_mcp.bridge import Hello
from factorio_mcp.tools.registry import ToolSpec, visible


async def _noop():
    return {}


SPECS = [ToolSpec("server_status", None, "d", _noop), ToolSpec("list_players", "players", "d", _noop)]


def _hello(commands):
    return Hello("0.1.0", 1, frozenset(commands), "f", 48000)


def test_visible_all_while_hello_unknown():
    assert [s.name for s in visible(SPECS, None)] == ["server_status", "list_players"]


def test_visible_hides_tool_without_mod_command():
    assert [s.name for s in visible(SPECS, _hello({"hello"}))] == ["server_status"]


async def test_tools_hidden_without_mod_command(stack):
    stack.reply("hello", hello_reply(commands=("hello", "server_info")))
    await stack.bridge.refresh_hello()
    assert await stack.tool_names() == ["server_status"]
    stack.reply("hello", hello_reply())
    await stack.bridge.refresh_hello()
    assert "list_players" in await stack.tool_names()
