"""Live tests talk to a local dev Factorio server (scripts/live.sh starts one on 127.0.0.1:27015)."""

from __future__ import annotations

import asyncio
import os
from pathlib import Path

import pytest
import pytest_asyncio

from factorio_mcp.rcon import RconLink

REPO = Path(__file__).resolve().parents[3]
GAME_LOG = REPO / "dev" / "write" / "factorio-current.log"


def pytest_collection_modifyitems(config, items):
    if os.environ.get("FACTORIO_MCP_LIVE"):
        return
    skip = pytest.mark.skip(reason="set FACTORIO_MCP_LIVE=1 (or use scripts/live.sh) to run live tests")
    for item in items:
        if "live" in item.keywords:
            item.add_marker(skip)


@pytest_asyncio.fixture
async def rcon():
    link = RconLink("127.0.0.1", 27015, "dev", retry_delay=0.2)
    task = asyncio.create_task(link.run())
    for _ in range(100):
        if link.alive:
            break
        await asyncio.sleep(0.1)
    assert link.alive, "could not connect to the dev server over RCON"
    try:
        yield link
    finally:
        task.cancel()


@pytest.fixture
def game_log_errors():
    """Callable returning how many 'Error' lines the game log has right now."""

    def count() -> int:
        if not GAME_LOG.exists():
            return 0
        return sum(1 for line in GAME_LOG.read_text(errors="replace").splitlines() if "Error" in line)

    return count


async def _sc(link: RconLink, code: str) -> str:
    return await link.exec("/sc " + code.replace("\n", " "), timeout=20)


@pytest_asyncio.fixture
async def armed(rcon):
    """The RCON link after the first /sc (which only asks to disable achievements) is spent."""
    await rcon.exec("/sc rcon.print('ready')", timeout=10)
    await rcon.exec("/sc rcon.print('ready')", timeout=10)
    return rcon


@pytest_asyncio.fixture
async def caller_nick(armed) -> str:
    """The first player record in the dev save, used as `caller`; skips when the save has none.

    The name is read at runtime so no real nick is written into the repo. A save gets a player
    record once someone has joined the dev server.
    """
    name = (await _sc(armed, "local p = game.players[1]; rcon.print(p and p.name or '')")).strip()
    if not name:
        pytest.skip("the dev save has no player record (join the dev server once); caller-based check skipped")
    return name
