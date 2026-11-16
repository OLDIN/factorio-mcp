from __future__ import annotations

from typing import Any

from ..bridge import GameUnavailable, ModBridge, ModMissing
from .registry import ToolSpec


def specs(bridge: ModBridge) -> list[ToolSpec]:
    async def server_status() -> dict[str, Any]:
        try:
            info = await bridge.call("server_info")
        except ModMissing:
            return {"status": "mod not installed"}
        except GameUnavailable:
            return {"status": "game unavailable"}
        hello = bridge.last_hello
        return {
            "status": "ok",
            "mod_version": hello.mod_version if hello else None,
            "tools_available_for_commands": sorted(hello.commands) if hello else [],
            **info,
        }

    return [
        ToolSpec(
            "server_status",
            None,
            "Game server state: tick, pause, speed, players online, installed mods with versions, "
            "difficulty and map settings, surfaces.",
            server_status,
        )
    ]
