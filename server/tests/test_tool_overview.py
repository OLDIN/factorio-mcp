from __future__ import annotations

import json

from stack_fixture import hello_reply

from factorio_mcp.commands import build_command

ALL = ("hello", "server_info", "players", "area", "job_start", "job_result")


def env(result):
    return json.dumps({"v": 1, "ok": True, "result": result})


async def _setup(stack, commands=ALL):
    stack.fake.responses[build_command("hello")] = hello_reply(commands)
    await stack.bridge.refresh_hello()


async def _call(stack, name, arguments):
    r = await stack.rpc("tools/call", {"name": name, "arguments": arguments})
    assert r.status_code == 200, r.text
    return r.json()["result"]


async def test_overview_tool_visible_only_with_job_support(stack):
    await _setup(stack, ("hello", "server_info"))
    assert "base_machines_overview" not in await stack.tool_names()
    await _setup(stack)
    assert "base_machines_overview" in await stack.tool_names()


async def test_overview_collects_and_normalizes(stack):
    await _setup(stack)
    start = build_command("job_start", {"kind": "machines_overview", "params": {}})
    stack.fake.responses[start] = env({"job_id": 1, "mode": "idle", "total_chunks": 1})
    stack.fake.responses[build_command("job_result", {"job_id": 1, "offset": 0})] = env({
        "state": "done", "summary": {"machines": 1, "working": 0, "groups": 1, "surfaces": 1}, "total": 1,
        "groups": [{"surface": "nauvis", "name": "asm", "count": 1, "working": 0, "by_status": [], "examples": {}}]})
    data = json.loads((await _call(stack, "base_machines_overview", {}))["content"][0]["text"])
    group = data["groups"][0]
    assert group["by_status"] == {} and group["examples"] == []


async def test_surfaces_argument_is_passed(stack):
    await _setup(stack)
    start = build_command("job_start", {"kind": "machines_overview", "params": {"surfaces": ["vulcanus"]}})
    stack.fake.responses[start] = env({"job_id": 1, "mode": "idle", "total_chunks": 1})
    stack.fake.responses[build_command("job_result", {"job_id": 1, "offset": 0})] = env(
        {"state": "done", "summary": {}, "groups": [], "total": 0})
    await _call(stack, "base_machines_overview", {"surfaces": ["vulcanus"]})
    assert start in stack.fake.received


async def test_big_radius_area_runs_as_job_with_players_position(stack):
    await _setup(stack)
    stack.fake.responses[build_command("players")] = env({"players": [
        {"name": "aliceNick", "online": True, "position": {"x": 4.5, "y": 6}, "surface": "nauvis"}]})
    start = build_command("job_start", {"kind": "area", "params": {"radius": 200.0, "surface": "nauvis", "x": 4.5, "y": 6}})
    stack.fake.responses[start] = env({"job_id": 2, "mode": "idle", "total_chunks": 9})
    stack.fake.responses[build_command("job_result", {"job_id": 2, "offset": 0})] = env({
        "state": "done", "totals": {"machines": 0, "working": 0, "by_status": []}, "groups": {}, "stopped": {}, "drills": {},
        "truncated": False, "center": {"surface": "nauvis", "x": 4.5, "y": 6}, "radius": 200})
    res = await _call(stack, "inspect_area", {"radius": 200})
    data = json.loads(res["content"][0]["text"])
    assert data["radius"] == 200 and data["groups"] == [] and data["totals"]["by_status"] == {}
    assert start in stack.fake.received


async def test_big_radius_for_offline_player_is_refused(stack):
    await _setup(stack)
    stack.fake.responses[build_command("players")] = env({"players": [
        {"name": "aliceNick", "online": False, "position": None, "surface": None}]})
    res = await _call(stack, "inspect_area", {"radius": 200})
    assert res["isError"] is True and "offline" in res["content"][0]["text"]


async def test_duplicate_surfaces_are_sent_once(stack):
    await _setup(stack)
    start = build_command("job_start", {"kind": "machines_overview", "params": {"surfaces": ["nauvis"]}})
    stack.fake.responses[start] = env({"job_id": 1, "mode": "idle", "total_chunks": 1})
    stack.fake.responses[build_command("job_result", {"job_id": 1, "offset": 0})] = env(
        {"state": "done", "summary": {}, "groups": [], "total": 0})
    await _call(stack, "base_machines_overview", {"surfaces": ["nauvis"] * 50})
    assert start in stack.fake.received


async def test_long_scan_answers_running_then_resumes_by_handle(stack, monkeypatch):
    from factorio_mcp import jobs

    monkeypatch.setattr(jobs, "SOFT_TIMEOUT", 0.1)
    await _setup(stack)
    start = build_command("job_start", {"kind": "machines_overview", "params": {}})
    stack.fake.responses[start] = env({"job_id": 5, "mode": "ticks", "total_chunks": 99})
    result_cmd = build_command("job_result", {"job_id": 5, "offset": 0})
    stack.fake.responses[result_cmd] = env({"state": "running", "mode": "ticks", "progress": 0.25})
    first = json.loads((await _call(stack, "base_machines_overview", {}))["content"][0]["text"])
    assert first["status"] == "running" and first["progress"] == 0.25
    handle = first["job_id"]
    assert isinstance(handle, str) and handle != "5"

    stack.fake.responses[result_cmd] = env(
        {"state": "done", "summary": {"machines": 2, "working": 1, "groups": 1, "surfaces": 1}, "groups": [], "total": 0})
    second = json.loads((await _call(stack, "base_machines_overview", {"job_id": handle}))["content"][0]["text"])
    assert second["summary"]["machines"] == 2 and "status" not in second
    assert sum(1 for c in stack.fake.received if c == start) == 1  # started once, resumed once


async def test_a_guessed_or_foreign_handle_gets_the_same_clear_message(stack, monkeypatch):
    from factorio_mcp import jobs
    from stack_fixture import TOKEN_BOB

    monkeypatch.setattr(jobs, "SOFT_TIMEOUT", 0.1)
    await _setup(stack)
    start = build_command("job_start", {"kind": "machines_overview", "params": {}})
    stack.fake.responses[start] = env({"job_id": 5, "mode": "ticks", "total_chunks": 99})
    stack.fake.responses[build_command("job_result", {"job_id": 5, "offset": 0})] = env(
        {"state": "running", "mode": "ticks", "progress": 0.25})
    handle = json.loads((await _call(stack, "base_machines_overview", {}))["content"][0]["text"])["job_id"]
    # bob (another token) cannot continue alice's scan; a guess fails the same way
    for who, guess in ((TOKEN_BOB, handle), (None, "AAAAAAAAAAAA")):
        r = await stack.rpc("tools/call", {"name": "base_machines_overview", "arguments": {"job_id": guess}},
                            **({"token": who} if who else {}))
        res = r.json()["result"]
        assert res["isError"] is True and "gone" in res["content"][0]["text"]


async def test_big_area_resumes_by_handle(stack, monkeypatch):
    from factorio_mcp import jobs

    monkeypatch.setattr(jobs, "SOFT_TIMEOUT", 0.1)
    await _setup(stack)
    stack.fake.responses[build_command("players")] = env({"players": [
        {"name": "aliceNick", "online": True, "position": {"x": 0, "y": 0}, "surface": "nauvis"}]})
    start = build_command("job_start", {"kind": "area", "params": {"radius": 300.0, "surface": "nauvis", "x": 0, "y": 0}})
    stack.fake.responses[start] = env({"job_id": 3, "mode": "ticks", "total_chunks": 9})
    result_cmd = build_command("job_result", {"job_id": 3, "offset": 0})
    stack.fake.responses[result_cmd] = env({"state": "running", "mode": "ticks", "progress": 0.5})
    first = json.loads((await _call(stack, "inspect_area", {"radius": 300}))["content"][0]["text"])
    assert first["status"] == "running"
    stack.fake.responses[result_cmd] = env({
        "state": "done", "totals": {"machines": 1, "working": 1, "by_status": {"working": 1}}, "groups": [],
        "stopped": [], "drills": [], "truncated": False, "center": {"surface": "nauvis", "x": 0, "y": 0}, "radius": 300})
    res = await _call(stack, "inspect_area", {"job_id": first["job_id"]})
    assert json.loads(res["content"][0]["text"])["totals"]["machines"] == 1


async def test_cancelled_call_is_audited_as_cancelled(stack, caplog):
    import asyncio
    import logging

    from factorio_mcp.app import _wrap
    from factorio_mcp.identity import reset_identity, set_identity
    from factorio_mcp.tokens import Identity
    from factorio_mcp.tools.registry import ToolSpec

    async def slow() -> dict:
        await asyncio.sleep(10)
        return {}

    marker = set_identity(Identity("alice", "AliceNick"))
    try:
        task = asyncio.create_task(_wrap(ToolSpec("slow_tool", None, "d", slow))())
        await asyncio.sleep(0.05)
        with caplog.at_level(logging.INFO, logger="factorio_mcp.audit"):
            task.cancel()
            await asyncio.gather(task, return_exceptions=True)
    finally:
        reset_identity(marker)
    assert "tool=slow_tool" in caplog.text and "outcome=cancelled" in caplog.text


def _group(i, count, working, surface="nauvis"):
    return {"surface": surface, "name": f"machine-{i:03d}", "recipe": f"r{i}", "count": count, "working": working,
            "by_status": {"working": working, "full_output": count - working} if count > working else {"working": working},
            "examples": []}


def test_compact_sorts_stuck_groups_first_and_pages():
    from factorio_mcp.tools.overview import compact

    groups = [_group(i, 10, 10) for i in range(40)] + [_group(100, 4, 1), _group(101, 9, 0, "gleba"), _group(102, 3, 2)]
    result = {"summary": {"machines": 413, "working": 403, "groups": 43, "surfaces": 2}, "groups": groups}
    out = compact(result, limit=2, offset=0, only_stopped=True)
    assert [g["name"] for g in out["groups"]] == ["machine-101", "machine-100"]  # 9 stopped, then 3 stopped
    assert out["total_groups"] == 3 and out["next"] == 2  # fully working groups are left out
    assert out["by_status"]["full_output"] == 9 + 3 + 1
    assert out["by_surface"]["gleba"] == {"machines": 9, "working": 0}
    nxt = compact(result, limit=2, offset=out["next"], only_stopped=True)
    assert [g["name"] for g in nxt["groups"]] == ["machine-102"] and nxt["next"] is None
    everything = compact(result, limit=100, offset=0, only_stopped=False)
    assert everything["total_groups"] == 43


async def test_overview_answers_compactly(stack):
    await _setup(stack)
    start = build_command("job_start", {"kind": "machines_overview", "params": {}})
    stack.fake.responses[start] = env({"job_id": 1, "mode": "idle", "total_chunks": 1})
    groups = [_group(i, 10, 10) for i in range(300)] + [_group(900, 5, 0)]
    stack.fake.responses[build_command("job_result", {"job_id": 1, "offset": 0})] = env({
        "state": "done", "summary": {"machines": 3005, "working": 3000, "groups": 301, "surfaces": 1},
        "groups": groups, "total": 301})
    text = (await _call(stack, "base_machines_overview", {}))["content"][0]["text"]
    data = json.loads(text)
    assert len(data["groups"]) == 1 and data["groups"][0]["name"] == "machine-900"
    assert data["by_status"]["full_output"] == 5 and data["total_groups"] == 1
    assert len(text) < 3000  # 300 working groups are not in the answer
