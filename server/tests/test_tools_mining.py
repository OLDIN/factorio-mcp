from __future__ import annotations

import json

from stack_fixture import hello_reply

from factorio_mcp.commands import build_command

BASE = ("hello", "server_info", "players", "area")
WORST = [
    {"surface": "nauvis", "name": "electric-mining-drill", "resource": "iron-ore", "remaining": 0,
     "depleted": True, "infinite": False, "gps": "[gps=1,1,nauvis]"},
    {"surface": "nauvis", "name": "electric-mining-drill", "resource": "copper-ore", "remaining": 300,
     "depleted": False, "infinite": False, "gps": "[gps=2,2,nauvis]"},
    {"surface": "vulcanus", "name": "pumpjack", "resource": "crude-oil", "remaining": 10,
     "depleted": False, "infinite": True, "gps": "[gps=3,3,vulcanus]"},
]
GROUPS = [
    {"surface": "nauvis", "resource": "iron-ore", "drills": 5, "depleted": 1, "low": 2, "ore_in_reach": 9000, "infinite": False},
    {"surface": "nauvis", "resource": "copper-ore", "drills": 3, "depleted": 0, "low": 1, "ore_in_reach": 4000, "infinite": False},
    {"surface": "vulcanus", "resource": "crude-oil", "drills": 1, "depleted": 0, "low": 1, "infinite": True},
]


def _env(result):
    return json.dumps({"v": 1, "ok": True, "result": result})


async def _setup(stack, commands):
    stack.fake.responses[build_command("hello")] = hello_reply(commands)
    await stack.bridge.refresh_hello()


def _done(worst=WORST, groups=GROUPS):
    return _env({"state": "done", "summary": {"drills": 9, "depleted": 1, "low": 4}, "groups": groups,
                 "worst": worst, "total": len(worst)})


async def _call(stack, arguments):
    r = await stack.rpc("tools/call", {"name": "base_mining_overview", "arguments": arguments})
    assert r.status_code == 200, r.text
    return r.json()["result"]


async def test_mining_overview_visible_only_with_the_0_4_mod(stack):
    await _setup(stack, BASE + ("job_start", "job_result"))
    assert "base_mining_overview" not in await stack.tool_names()  # mod 0.3.0: jobs but no mining kind
    await _setup(stack, BASE + ("job_start", "job_result", "threats"))
    assert "base_mining_overview" in await stack.tool_names()


async def test_mining_overview_runs_the_job_and_pages(stack):
    await _setup(stack, BASE + ("job_start", "job_result", "threats"))
    start = build_command("job_start", {"kind": "mining_overview", "params": {"caller": "aliceNick", "limit": 25}})
    stack.fake.responses[start] = _env({"job_id": 4, "mode": "idle", "work_items": 2})
    stack.fake.responses[build_command("job_result", {"job_id": 4, "offset": 0})] = _done()
    data = json.loads((await _call(stack, {"limit": 2}))["content"][0]["text"])
    assert start in stack.fake.received
    assert data["summary"]["depleted"] == 1
    assert [w["resource"] for w in data["worst"]] == ["iron-ore", "copper-ore"]
    assert data["worst_total"] == 3 and data["next"] == 2
    assert data["groups"][0]["resource"] == "iron-ore"


async def test_mining_overview_filters_by_resource(stack):
    await _setup(stack, BASE + ("job_start", "job_result", "threats"))
    start = build_command("job_start", {"kind": "mining_overview", "params": {"caller": "aliceNick", "limit": 25}})
    stack.fake.responses[start] = _env({"job_id": 5, "mode": "idle", "work_items": 2})
    stack.fake.responses[build_command("job_result", {"job_id": 5, "offset": 0})] = _done()
    data = json.loads((await _call(stack, {"resource": "copper-ore"}))["content"][0]["text"])
    assert [w["resource"] for w in data["worst"]] == ["copper-ore"]
    assert [g["resource"] for g in data["groups"]] == ["copper-ore"]
    assert data["next"] is None


async def test_mining_overview_passes_surfaces_and_normalizes_empty_lists(stack):
    await _setup(stack, BASE + ("job_start", "job_result", "threats"))
    start = build_command(
        "job_start", {"kind": "mining_overview", "params": {"caller": "aliceNick", "limit": 25, "surfaces": ["nauvis"]}}
    )
    stack.fake.responses[start] = _env({"job_id": 6, "mode": "idle", "work_items": 0})
    stack.fake.responses[build_command("job_result", {"job_id": 6, "offset": 0})] = _env(
        {"state": "done", "summary": {"drills": 0, "depleted": 0, "low": 0}, "groups": {}, "worst": {}, "total": 0}
    )
    data = json.loads((await _call(stack, {"surfaces": ["nauvis"]}))["content"][0]["text"])
    assert data["worst"] == [] and data["groups"] == [] and data["worst_total"] == 0 and data["next"] is None
