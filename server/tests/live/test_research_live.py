"""Research state against a real game. `/sc` is used here, in tests, on the dev server only."""

from __future__ import annotations

import pytest

from factorio_mcp.bridge import ModBridge, ModError

pytestmark = pytest.mark.live


async def test_research_current_and_available(armed, caller_nick):
    force = (await armed.exec(f"/sc rcon.print(game.get_player('{caller_nick}').force.name)", timeout=10)).strip()
    await armed.exec(
        f"/sc local f = game.forces['{force}']; if not f.technologies['automation'].researched then f.add_research('automation') end",
        timeout=10,
    )
    bridge = ModBridge(armed)
    result = await bridge.call("research", {"caller": caller_nick})
    assert result["total"] > 50
    done = await bridge.call("research", {"caller": caller_nick, "name": "automation"})
    if not done["researched"]:
        assert result["current"]["name"] == "automation"
    one = await bridge.call("research", {"caller": caller_nick, "name": "logistics-2"})
    assert one["unit_count"] > 0 and one["ingredients"]


async def test_research_unknown_caller(armed):
    with pytest.raises(ModError) as info:
        await ModBridge(armed).call("research", {"caller": "nobody-here-123"})
    assert info.value.code == "not_found"
