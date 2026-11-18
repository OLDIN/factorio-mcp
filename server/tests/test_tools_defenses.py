from __future__ import annotations

import json

from stack_fixture import TOKEN_BOB, hello_reply

from factorio_mcp.commands import build_command

ALL = ("hello", "server_info", "players", "area", "defenses")
DEFENSES = {
    "v": 1,
    "ok": True,
    "result": {
        "center": {"surface": "nauvis", "x": 10, "y": 20},
        "radius": 64,
        "summary": {
            "total": 5,
            "turrets": 3,
            "walls": 2,
            "other": 0,
            "issues": {"no_ammo": 1, "no_power": 0, "no_fluid": 0, "damaged": 1},
        },
        "groups": [
            {
                "name": "gun-turret",
                "type": "ammo-turret",
                "count": 3,
                "ready": 2,
                "damaged": 1,
                "ammo": {"firearm-magazine": 20},
                "fluids": {},
            },
            {
                "name": "stone-wall",
                "type": "wall",
                "count": 2,
                "ready": 2,
                "damaged": 0,
                "ammo": {},
                "fluids": {},
            },
        ],
        "problems": [
            {
                "name": "gun-turret",
                "type": "ammo-turret",
                "x": 12.5,
                "y": 20.5,
                "issue": "no_ammo",
                "health": 200,
                "max_health": 400,
                "ammo": 0,
            }
        ],
        "problems_total": 1,
    },
}


async def _setup(stack):
    stack.fake.responses[build_command("hello")] = hello_reply(ALL)
    await stack.bridge.refresh_hello()


def _defenses_commands(stack) -> list[str]:
    return [c for c in stack.fake.received if "defenses" in c and not c.startswith("/factorio-mcp hello")]


async def _call(stack, arguments, token=None):
    kwargs = {"token": token} if token else {}
    r = await stack.rpc("tools/call", {"name": "inspect_defenses", "arguments": arguments}, **kwargs)
    assert r.status_code == 200, r.text
    return r.json()["result"]


async def test_defenses_no_arguments_uses_nick_from_token(stack):
    await _setup(stack)
    stack.fake.responses[build_command("defenses", {"radius": 32.0, "max_listed": 20, "player": "aliceNick"})] = (
        json.dumps(DEFENSES)
    )
    res = await _call(stack, {})
    data = json.loads(res["content"][0]["text"])
    assert data["summary"]["turrets"] == 3
    assert len(data["groups"]) == 2
    assert len(data["problems"]) == 1
    assert data["problems"][0]["issue"] == "no_ammo"


async def test_defenses_gps_is_parsed(stack):
    await _setup(stack)
    cmd = build_command(
        "defenses", {"radius": 32.0, "max_listed": 10, "surface": "gleba", "x": -50.0, "y": 25.0}
    )
    stack.fake.responses[cmd] = json.dumps(DEFENSES)
    res = await _call(stack, {"gps": "[gps=-50,25,gleba]", "radius": 32, "max_listed": 10})
    data = json.loads(res["content"][0]["text"])
    assert data["summary"]["total"] == 5
    assert _defenses_commands(stack) == [cmd]


async def test_defenses_normalizes_empty_maps(stack):
    await _setup(stack)
    empty_result = {
        "v": 1,
        "ok": True,
        "result": {
            "center": {"surface": "nauvis", "x": 0, "y": 0},
            "radius": 64,
            "summary": {"total": 0, "turrets": 0, "walls": 0, "other": 0, "issues": []},
            "groups": [],
            "problems": [],
            "problems_total": 0,
        },
    }
    cmd = build_command("defenses", {"radius": 32.0, "max_listed": 20, "player": "bobNick"})
    stack.fake.responses[cmd] = json.dumps(empty_result)
    res = await _call(stack, {}, token=TOKEN_BOB)
    data = json.loads(res["content"][0]["text"])
    assert data["summary"]["issues"] == {}
    assert data["groups"] == []
    assert data["problems"] == []


def _env(result):
    return json.dumps({"v": 1, "ok": True, "result": result})


OVERVIEW_PROBLEMS = [
    {"name": "gun-turret", "type": "ammo-turret", "x": 1, "y": 1, "issue": "no_ammo", "health": 400,
     "max_health": 400, "ammo": 0, "surface": "nauvis", "gps": "[gps=1,1,nauvis]"},
    {"name": "stone-wall", "type": "wall", "x": 5, "y": 5, "issue": "damaged", "health": 10,
     "max_health": 350, "surface": "vulcanus", "gps": "[gps=5,5,vulcanus]"},
]


async def test_base_defenses_overview_requires_threats_command(stack):
    stack.fake.responses[build_command("hello")] = hello_reply(ALL + ("job_start", "job_result"))
    await stack.bridge.refresh_hello()
    assert "base_defenses_overview" not in await stack.tool_names()  # mod 0.3.0: defenses but no overview kind
    stack.fake.responses[build_command("hello")] = hello_reply(ALL + ("job_start", "job_result", "threats"))
    await stack.bridge.refresh_hello()
    assert "base_defenses_overview" in await stack.tool_names()


async def test_base_defenses_overview_collects_and_pages(stack):
    stack.fake.responses[build_command("hello")] = hello_reply(ALL + ("job_start", "job_result", "threats"))
    await stack.bridge.refresh_hello()
    start = build_command("job_start", {"kind": "defenses_overview", "params": {"caller": "aliceNick"}})
    stack.fake.responses[start] = _env({"job_id": 6, "mode": "idle", "work_items": 3})
    stack.fake.responses[build_command("job_result", {"job_id": 6, "offset": 0})] = _env({
        "state": "done",
        "summary": {"total": 10, "turrets": 4, "walls": 6, "other": 0,
                    "issues": {"no_ammo": 1, "no_power": 0, "no_fluid": 0, "damaged": 1}},
        "by_surface": {"nauvis": {"total": 7, "problems": 1}, "vulcanus": {"total": 3, "problems": 1}},
        "groups": [], "problems_total": 2, "problems": OVERVIEW_PROBLEMS, "total": 2,
    })
    r = await stack.rpc("tools/call", {"name": "base_defenses_overview", "arguments": {"limit": 1}})
    data = json.loads(r.json()["result"]["content"][0]["text"])
    assert start in stack.fake.received
    assert data["summary"]["issues"]["no_ammo"] == 1
    assert data["by_surface"]["vulcanus"]["problems"] == 1
    assert [p["issue"] for p in data["problems"]] == ["no_ammo"]
    assert data["problems_total"] == 2 and data["next"] == 1
