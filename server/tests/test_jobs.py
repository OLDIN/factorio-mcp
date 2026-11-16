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
    result = await JobRunner(stack.bridge).run("machines_overview", {}, poll=0.01)
    assert [g["name"] for g in result["groups"]] == ["a", "b", "c"]
    assert result["summary"] == {"machines": 3} and "state" not in result and "next" not in result


async def test_timeout_cancels_the_job(stack):
    stack.fake.responses[START] = env({"job_id": 7, "mode": "idle", "total_chunks": 4})
    stack.fake.responses[result_cmd(0)] = env({"state": "running", "progress": 0.1})
    stack.fake.responses[build_command("job_cancel", {"job_id": 7})] = env({"cancelled": True})
    with pytest.raises(ModError) as info:
        await JobRunner(stack.bridge).run("machines_overview", {}, timeout=0.1, poll=0.02)
    assert info.value.code == "job_timeout"
    assert build_command("job_cancel", {"job_id": 7}) in stack.fake.received


async def test_bad_response_midway_is_an_error_not_a_fragment(stack):
    stack.fake.responses[START] = env({"job_id": 7, "mode": "idle", "total_chunks": 4})
    stack.fake.responses[result_cmd(0)] = env({"state": "done", "groups": [{"name": "a"}], "next": 1})
    stack.fake.responses[result_cmd(1)] = '{"v":1,"ok":true,"result":{"state":"do'
    with pytest.raises(ModError) as info:
        await JobRunner(stack.bridge).run("machines_overview", {}, poll=0.01)
    assert info.value.code == "bad_response"


async def test_error_from_mod_surfaces(stack):
    stack.fake.responses[START] = json.dumps({"v": 1, "ok": False, "error": {"code": "not_found", "message": "no such surface"}})
    with pytest.raises(ModError) as info:
        await JobRunner(stack.bridge).run("machines_overview", {}, poll=0.01)
    assert info.value.code == "not_found"


async def test_paging_that_does_not_advance_is_refused(stack):
    stack.fake.responses[START] = env({"job_id": 7, "mode": "idle", "total_chunks": 4})
    stack.fake.responses[result_cmd(0)] = env({"state": "done", "groups": [], "next": 0})
    with pytest.raises(ModError):
        await JobRunner(stack.bridge).run("machines_overview", {}, poll=0.01)


def test_hello_helper_is_available():
    assert "job_start" in hello_reply(("hello", "job_start"))


async def test_soft_wait_returns_running_without_cancelling(stack):
    stack.fake.responses[START] = env({"job_id": 7, "mode": "ticks", "total_chunks": 4})
    stack.fake.responses[result_cmd(0)] = env({"state": "running", "mode": "ticks", "progress": 0.4})
    result = await JobRunner(stack.bridge).run("machines_overview", {}, poll=0.02, wait=0.1)
    assert result["status"] == "running" and result["job_id"] == 7 and result["progress"] == 0.4
    assert "job_id=7" in result["message"]
    assert build_command("job_cancel", {"job_id": 7}) not in stack.fake.received  # the job keeps running


async def test_resume_by_job_id_does_not_start_a_new_job(stack):
    stack.fake.responses[result_cmd(0)] = env({"state": "done", "summary": {"machines": 1}, "groups": [], "total": 0})
    result = await JobRunner(stack.bridge).run("machines_overview", {}, poll=0.02, wait=1.0, job_id=7)
    assert result["summary"] == {"machines": 1}
    assert not any("job_start" in c for c in stack.fake.received)
