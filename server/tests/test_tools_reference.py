from __future__ import annotations

import json

from stack_fixture import hello_reply

from factorio_mcp.commands import build_command

ALL = ("hello", "server_info", "players", "proto_recipes", "proto_machines", "proto_planets")
RECIPES = [{"name": f"recipe-{i:02d}", "categories": ["crafting"], "hidden": i == 0,
            "ingredients": [], "products": [{"type": "item", "name": f"thing-{i}", "amount": 1}]} for i in range(12)]
MACHINES = [{"name": "assembling-machine-2", "crafting_categories": ["crafting"], "resource_categories": []}]


async def _setup(stack):
    stack.fake.responses[build_command("hello")] = hello_reply(ALL)
    await stack.bridge.refresh_hello()
    stack.fake.responses[build_command("proto_recipes", {"offset": 0})] = json.dumps(
        {"v": 1, "ok": True, "result": {"kind": "recipes", "total": 12, "offset": 0, "items": RECIPES}})
    stack.fake.responses[build_command("proto_machines", {"offset": 0})] = json.dumps(
        {"v": 1, "ok": True, "result": {"kind": "machines", "total": 1, "offset": 0, "items": MACHINES}})


async def _call(stack, name, arguments):
    r = await stack.rpc("tools/call", {"name": name, "arguments": arguments})
    assert r.status_code == 200, r.text
    return json.loads(r.json()["result"]["content"][0]["text"])


async def test_tools_listed_with_schema(stack):
    await _setup(stack)
    tools = {t["name"]: t for t in (await stack.rpc("tools/list")).json()["result"]["tools"]}
    assert {"reference_recipes", "reference_machines", "reference_planets"} <= set(tools)
    assert "produces" in tools["reference_recipes"]["inputSchema"]["properties"]
    assert "reference_items" not in tools  # the mod does not know proto_items in this scenario


async def test_tool_limit_and_offset(stack):
    await _setup(stack)
    page = await _call(stack, "reference_recipes", {"limit": 4, "offset": 0})
    assert page["total"] == 11 and len(page["items"]) == 4 and page["next"] == 4  # hidden one skipped
    page = await _call(stack, "reference_recipes", {"limit": 4, "offset": 8})
    assert len(page["items"]) == 3 and page["next"] is None


async def test_search_is_case_insensitive_and_filters(stack):
    await _setup(stack)
    page = await _call(stack, "reference_recipes", {"search": "RECIPE-05"})
    assert [i["name"] for i in page["items"]] == ["recipe-05"]
    page = await _call(stack, "reference_recipes", {"produces": "thing-3"})
    assert [i["name"] for i in page["items"]] == ["recipe-03"]
    page = await _call(stack, "reference_recipes", {"machine": "assembling-machine-2", "limit": 200})
    assert page["total"] == 11
    page = await _call(stack, "reference_recipes", {"name": "recipe-00"})  # exact name finds hidden too
    assert page["total"] == 1
