"""Mining overview, logistic requests and the new parameters against a real game. `/sc` is used here, in
tests, on the dev server only (the save copy from scripts/profile-save.sh gives meaningful numbers)."""

from __future__ import annotations

import asyncio

import pytest

from factorio_mcp.bridge import ModBridge, ModError

pytestmark = pytest.mark.live


async def sc(rcon, code: str, mod_state: bool = False) -> str:
    """Run Lua on the dev server; `mod_state` runs it inside the mod's own Lua state (its loaded modules)."""
    prefix = "/sc __factorio-mcp__ " if mod_state else "/sc "
    return await rcon.exec(prefix + code.replace("\n", " "), timeout=60)


async def run_job(bridge: ModBridge, kind: str, params: dict) -> dict:
    start = await bridge.call("job_start", {"kind": kind, "params": params, "mode": "idle"})
    for _ in range(1200):
        page = await bridge.call("job_result", {"job_id": start["job_id"]})
        if page["state"] == "done":
            return page
        await asyncio.sleep(0.05)
    raise AssertionError(f"{kind} job did not finish")


async def test_mining_overview_unknown_caller(armed):
    with pytest.raises(ModError) as info:
        await ModBridge(armed).call("job_start", {"kind": "mining_overview", "params": {"caller": "nobody-here-123"}})
    assert info.value.code == "not_found"


async def test_mining_overview_counts_every_drill(armed, caller_nick):
    page = await run_job(ModBridge(armed), "mining_overview", {"caller": caller_nick, "limit": 10})
    expected = int(await sc(armed, (
        "local f = game.get_player('%s').force; local n = 0; "
        "for _, s in pairs(game.surfaces) do n = n + s.count_entities_filtered{type = 'mining-drill', force = f} end; "
        "rcon.print(n)" % caller_nick)))
    assert page["summary"]["drills"] == expected
    assert page["summary"]["depleted"] <= page["summary"]["low"] <= page["summary"]["drills"]
    assert len(page["worst"]) <= 10
    for w in page["worst"]:
        assert w["gps"].startswith("[gps=")


async def test_mining_record_matches_a_direct_sum(armed, caller_nick):
    # the ore in reach computed by the mod equals an independent sum over the same square, for 5 drills
    answer = await sc(armed, """
local ml = package.loaded['__factorio-mcp__/scripts/logic/mining_logic.lua']
local f = game.get_player('%s').force
local s = game.surfaces.nauvis
local out, n = {}, 0
for _, d in ipairs(s.find_entities_filtered{type = 'mining-drill', force = f}) do
  local t = d.mining_target
  if t and t.valid and not t.prototype.infinite_resource then
    local r = d.prototype.mining_drill_radius
    local p = d.position
    local sum = 0
    for _, e in ipairs(s.find_entities_filtered{name = t.name, area = {{p.x - r, p.y - r}, {p.x + r, p.y + r}}}) do sum = sum + e.amount end
    local rec = ml.record(d, s)
    out[#out + 1] = (rec.remaining == sum and rec.resource == t.name) and 'ok' or ('BAD ' .. rec.remaining .. ' vs ' .. sum)
    n = n + 1
    if n >= 5 then break end
  end
end
rcon.print(table.concat(out, ','))
""" % caller_nick, mod_state=True)
    parts = answer.strip().split(",")
    if parts == [""]:
        pytest.skip("no finite-resource drills on nauvis in this save")
    assert all(p == "ok" for p in parts), answer
