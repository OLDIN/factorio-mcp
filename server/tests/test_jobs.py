from __future__ import annotations

import json

import pytest
from stack_fixture import hello_reply

from factorio_mcp.bridge import ModError
from factorio_mcp.commands import build_command
from factorio_mcp.jobs import JobRunner


def env(result):
    return json.dumps({"v": 1, "ok": True, "result": result})


START = build_command("job_start", {"kind": "machines_overview", "params": {}})


def result_cmd(offset=0):
    return build_command("job_result", {"job_id": 7, "offset": offset})


async def test_runner_polls_then_collects_all_pages(stack):
    stack.fake.responses[START] = env({"job_id": 7, "mode": "idle", "total_chunks": 4})
    stack.fake.sequences[result_cmd(0)] = [
        env({"state": "running", "progress": 0.3}),
        env({"state": "done", "summary": {"machines": 3}, "groups": [{"name": "a"}, {"name": "b"}], "total": 3, "next": 2}),
    ]
    stack.fake.responses[result_cmd(2)] = env({"state": "done", "summary": {"machines": 3}, "groups": [{"name": "c"}], "total": 3})
    result = await JobRunner(stack.bridge).run("machines_overview", {}, "alice", poll=0.01)
    assert [g["name"] for g in result["groups"]] == ["a", "b", "c"]
    assert result["summary"] == {"machines": 3} and "state" not in result and "next" not in result


async def test_timeout_cancels_the_job(stack):
    stack.fake.responses[START] = env({"job_id": 7, "mode": "idle", "total_chunks": 4})
    stack.fake.responses[result_cmd(0)] = env({"state": "running", "progress": 0.1})
    stack.fake.responses[build_command("job_cancel", {"job_id": 7})] = env({"cancelled": True})
    with pytest.raises(ModError) as info:
        await JobRunner(stack.bridge).run("machines_overview", {}, "alice", timeout=0.1, poll=0.02)
    assert info.value.code == "job_timeout"
    assert build_command("job_cancel", {"job_id": 7}) in stack.fake.received


async def test_bad_response_midway_is_an_error_not_a_fragment(stack):
    stack.fake.responses[START] = env({"job_id": 7, "mode": "idle", "total_chunks": 4})
    stack.fake.responses[result_cmd(0)] = env({"state": "done", "groups": [{"name": "a"}], "next": 1})
    stack.fake.responses[result_cmd(1)] = '{"v":1,"ok":true,"result":{"state":"do'
    with pytest.raises(ModError) as info:
        await JobRunner(stack.bridge).run("machines_overview", {}, "alice", poll=0.01)
    assert info.value.code == "bad_response"


async def test_error_from_mod_surfaces(stack):
    stack.fake.responses[START] = json.dumps({"v": 1, "ok": False, "error": {"code": "not_found", "message": "no such surface"}})
    with pytest.raises(ModError) as info:
        await JobRunner(stack.bridge).run("machines_overview", {}, "alice", poll=0.01)
    assert info.value.code == "not_found"


async def test_paging_that_does_not_advance_is_refused(stack):
    stack.fake.responses[START] = env({"job_id": 7, "mode": "idle", "total_chunks": 4})
    stack.fake.responses[result_cmd(0)] = env({"state": "done", "groups": [], "next": 0})
    with pytest.raises(ModError):
        await JobRunner(stack.bridge).run("machines_overview", {}, "alice", poll=0.01)


def test_hello_helper_is_available():
    assert "job_start" in hello_reply(("hello", "job_start"))


async def test_soft_wait_returns_running_without_cancelling(stack):
    stack.fake.responses[START] = env({"job_id": 7, "mode": "ticks", "total_chunks": 4})
    stack.fake.responses[result_cmd(0)] = env({"state": "running", "mode": "ticks", "progress": 0.4})
    result = await JobRunner(stack.bridge).run("machines_overview", {}, "alice", poll=0.02, wait=0.1)
    assert result["status"] == "running" and result["progress"] == 0.4
    assert isinstance(result["job_id"], str) and result["job_id"] != "7"  # an opaque handle, not the mod's id
    assert result["job_id"] in result["message"]
    assert build_command("job_cancel", {"job_id": 7}) not in stack.fake.received  # the job keeps running


async def _running_handle(stack, runner, owner="alice"):
    stack.fake.responses[START] = env({"job_id": 7, "mode": "ticks", "total_chunks": 4})
    stack.fake.responses[result_cmd(0)] = env({"state": "running", "mode": "ticks", "progress": 0.1})
    return (await runner.run("machines_overview", {}, owner, poll=0.02, wait=0.05))["job_id"]


async def test_resume_with_the_handle_does_not_start_a_new_job(stack):
    runner = JobRunner(stack.bridge)
    handle = await _running_handle(stack, runner)
    starts = sum(1 for c in stack.fake.received if "job_start" in c)
    stack.fake.responses[result_cmd(0)] = env({"state": "done", "summary": {"machines": 1}, "groups": [], "total": 0})
    result = await runner.run("machines_overview", {}, "alice", poll=0.02, wait=1.0, handle=handle)
    assert result["summary"] == {"machines": 1}
    assert sum(1 for c in stack.fake.received if "job_start" in c) == starts
    with pytest.raises(ModError):  # a finished scan's handle is spent
        await runner.run("machines_overview", {}, "alice", poll=0.02, wait=1.0, handle=handle)


async def test_someone_elses_handle_and_wrong_kind_are_refused(stack):
    runner = JobRunner(stack.bridge)
    handle = await _running_handle(stack, runner, owner="alice")
    for owner, kind in (("bob", "machines_overview"), ("alice", "area")):  # another person; another kind
        with pytest.raises(ModError) as info:
            await runner.run(kind, {}, owner, poll=0.02, wait=0.05, handle=handle)
        assert info.value.code == "job_not_found"
    with pytest.raises(ModError) as info:  # a guessed handle looks the same as an expired one
        await runner.run("machines_overview", {}, "alice", poll=0.02, wait=0.05, handle="guess")
    assert info.value.code == "job_not_found"


async def test_handles_expire_and_the_scan_is_cancelled(stack, monkeypatch):
    from factorio_mcp import jobs

    runner = JobRunner(stack.bridge)
    handle = await _running_handle(stack, runner)
    stack.fake.responses[build_command("job_cancel", {"job_id": 7})] = env({"cancelled": True})
    monkeypatch.setattr(jobs, "HANDLE_TTL", -1)
    runner._handles._items = {h: (m, k, o, 0.0) for h, (m, k, o, _) in runner._handles._items.items()}
    with pytest.raises(ModError) as info:
        await runner.run("machines_overview", {}, "alice", poll=0.02, wait=0.05, handle=handle)
    assert info.value.code == "job_not_found"
    assert build_command("job_cancel", {"job_id": 7}) in stack.fake.received


async def test_one_person_cannot_hold_unlimited_scans(stack):
    runner = JobRunner(stack.bridge)
    await _running_handle(stack, runner)
    await _running_handle(stack, runner)
    with pytest.raises(ModError) as info:
        await _running_handle(stack, runner)
    assert info.value.code == "too_many_jobs"
    await _running_handle(stack, runner, owner="bob")  # the limit is per person

