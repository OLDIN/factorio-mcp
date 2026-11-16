from __future__ import annotations

from typing import Any

from ..bridge import ModBridge, normalize_lists
from .registry import ToolSpec


def specs(bridge: ModBridge) -> list[ToolSpec]:
    async def list_players() -> dict[str, Any]:
        return normalize_lists(await bridge.call("players"), ["players"])

    return [
        ToolSpec(
            "list_players",
            "players",
            "Players online and offline with positions (online players only), surface, AFK and play time.",
            list_players,
        )
    ]
