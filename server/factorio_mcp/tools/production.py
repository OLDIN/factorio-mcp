from __future__ import annotations

from typing import Any

from ..bridge import ModBridge, normalize_lists
from .common import call_mod, caller_args
from .registry import ToolSpec

SUMMARY_LISTS = ("top_produced", "top_consumed", "deficits")


def specs(bridge: ModBridge) -> list[ToolSpec]:
    async def production_stats(
        window: str = "1m",
        surface: str | None = None,
        name: str | None = None,
        limit: int = 15,
    ) -> dict[str, Any]:
        args: dict[str, Any] = {**caller_args(), "window": window, "limit": limit}
        if surface is not None:
            args["surface"] = surface
        if name is not None:
            args["name"] = name
        result = await call_mod(bridge, "production", args)
        return normalize(result)

    def normalize(result: dict[str, Any]) -> dict[str, Any]:
        for kind in ("items", "fluids"):
            if kind in result:
                if not isinstance(result[kind], dict):  # an empty Lua table arrives as []
                    result[kind] = {}
                for key in SUMMARY_LISTS:
                    result[kind].setdefault(key, [])
                normalize_lists(result[kind], SUMMARY_LISTS)
        normalize_lists(result, ["surfaces", "by_surface"])
        if result.get("by_quality") == []:
            result["by_quality"] = {}
        return result

    return [
        ToolSpec(
            "production_stats",
            "production",
            "Items and fluids produced and consumed per minute by your force over a window (5s, 1m, 10m, 1h, "
            "10h): top produced, top consumed, biggest deficits. name= gives one item or fluid per surface "
            "and quality; surface= one surface only.",
            production_stats,
        )
    ]
