from __future__ import annotations

import asyncio

from stack_fixture import hello_reply

from factorio_mcp.commands import build_command
from factorio_mcp.reference import ReferenceCache

P1 = {"v": 1, "ok": True, "result": {"kind": "recipes", "total": 3, "offset": 0, "next": 2, "items": [
    {"name": "a", "categories": {}, "ingredients": {}, "products": {}, "surface_conditions": {}},
    {"name": "b", "categories": ["crafting"], "ingredients": [], "products": [], "surface_conditions": []}]}}
P2 = {"v": 1, "ok": True, "result": {"kind": "recipes", "total": 3, "offset": 2, "items": [{"name": "c"}]}}


def _setup(stack):
    import json

    stack.fake.responses[build_command("proto_recipes", {"offset": 0})] = json.dumps(P1)
    stack.fake.responses[build_command("proto_recipes", {"offset": 2})] = json.dumps(P2)


def _count(stack) -> int:
    return sum(1 for c in stack.fake.received if "proto_recipes" in c)


async def test_cache_fetches_all_pages_once_and_normalizes(stack):
    _setup(stack)
    cache = ReferenceCache(stack.bridge)
    first = await cache.get("recipes")
    assert [r["name"] for r in first] == ["a", "b", "c"]
    assert first[0]["ingredients"] == [] and first[0]["categories"] == []  # `{}` -> []
    assert _count(stack) == 2
    await cache.get("recipes")
    assert _count(stack) == 2  # second call served from cache


async def test_cache_invalidated_on_fingerprint_change(stack):
    _setup(stack)
    cache = ReferenceCache(stack.bridge)
    await cache.get("recipes")
    stack.fake.responses[build_command("hello")] = hello_reply().replace("base=2.1.24", "base=2.1.25")
    await stack.bridge.refresh_hello()
    await cache.get("recipes")
    assert _count(stack) == 4


async def test_concurrent_gets_share_one_fetch(stack):
    _setup(stack)
    cache = ReferenceCache(stack.bridge)
    results = await asyncio.gather(*(cache.get("recipes") for _ in range(5)))
    assert all(len(r) == 3 for r in results)
    assert _count(stack) == 2
