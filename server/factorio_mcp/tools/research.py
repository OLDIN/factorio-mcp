from __future__ import annotations

from typing import Any

from ..bridge import ModBridge, normalize_lists
from .common import call_mod, caller_args
from .registry import ToolSpec


def specs(bridge: ModBridge) -> list[ToolSpec]:
    async def research_status(name: str | None = None, offset: int = 0, limit: int = 20) -> dict[str, Any]:
        args: dict[str, Any] = {**caller_args(), "offset": offset, "limit": limit}
        if name is not None:
            args["name"] = name
        result = await call_mod(bridge, "research", args)
        if name is not None:
            return normalize_lists(result, ["ingredients", "missing_prerequisites"])
        result.setdefault("current", None)
        normalize_lists(result, ["queue", "available.items"])
        result.get("available", {}).setdefault("next", None)
        return result

    return [
        ToolSpec(
            "research_status",
            "research",
            "Your force's research: what is being researched now and how far, the queue, how many technologies "
            "are done, and which can be researched right now (paged with offset/limit). Give name= for one "
            "technology: level, cost, progress and which prerequisites are still missing.",
            research_status,
        )
    ]
