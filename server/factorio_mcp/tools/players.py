from __future__ import annotations

from typing import Any

from ..bridge import ModBridge
from .registry import ToolSpec


def specs(bridge: ModBridge) -> list[ToolSpec]:
    async def list_players() -> dict[str, Any]:
        return await bridge.call("players")

    return [
        ToolSpec(
            "list_players",
            "players",
            "Players online and offline with positions (online players only), surface, AFK and play time.",
            list_players,
        )
    ]
