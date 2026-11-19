from __future__ import annotations

import json

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


ALL_COMMANDS = (
    "hello", "server_info", "players", "proto_recipes", "proto_machines", "proto_items", "proto_fluids",
    "proto_modules", "proto_qualities", "proto_technologies", "proto_planets", "area", "job_start",
    "job_result", "job_status", "job_cancel", "defenses", "production", "power", "research", "threats",
    "pollution", "logistics", "trains", "platforms", "inventory", "alerts", "resources", "transport",
)


def _titles(schema):
    """Every JSON-schema `title` (a string under the key "title") anywhere in a schema."""
    if isinstance(schema, dict):
        found = [v for k, v in schema.items() if k == "title" and isinstance(v, str)]
        for v in schema.values():
            found += _titles(v)
        return found
    if isinstance(schema, list):
        return [t for v in schema for t in _titles(v)]
    return []


async def test_tool_list_is_lean(stack):
    # tools/list is paid for in context on every conversation: no schema titles (they repeat the
    # parameter names), no output schema (results are JSON text)
    stack.reply("hello", hello_reply(commands=ALL_COMMANDS))
    await stack.bridge.refresh_hello()
    tools = (await stack.rpc("tools/list", {})).json()["result"]["tools"]
    size = len(json.dumps(tools, separators=(",", ":")))
    assert size <= 12000, f"tools/list grew to {size} bytes (~{size // 4} tokens in every conversation)"
    for tool in tools:
        assert _titles(tool["inputSchema"]) == [], tool["name"]
        assert "outputSchema" not in tool, tool["name"]
    stack.reply("players", '{"v":1,"ok":true,"result":{"players":[]}}')
    res = (await stack.rpc("tools/call", {"name": "list_players", "arguments": {}})).json()["result"]
    assert res["content"][0]["type"] == "text" and "structuredContent" not in res
