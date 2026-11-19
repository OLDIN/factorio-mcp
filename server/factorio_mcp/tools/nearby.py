"""Local details around a point: resource patches."""

from __future__ import annotations

from typing import Any

from ..bridge import ModBridge, normalize_lists, normalize_maps
from .common import call_mod, caller_args, point_args
from .registry import ToolSpec


def specs(bridge: ModBridge) -> list[ToolSpec]:
    async def inspect_resources(
        gps: str | None = None, player: str | None = None, radius: float = 64.0, limit: int = 10
    ) -> dict[str, Any]:
        args = {**caller_args(), **point_args(gps, player), "radius": radius, "limit": limit}
        result = await call_mod(bridge, "resources", args)
        normalize_lists(result, ["patches"])
        return normalize_maps(result, ["surface_totals"])

    return [
        ToolSpec(
            "inspect_resources",
            "resources",
            "Resource patches around a [gps] point, a player, or yourself (radius up to 128 tiles, default 64): "
            "each patch with its resource, amount, tiles (or wells for crude oil, raw amount), centre [gps], "
            "most tiles first; plus the totals for the whole surface.",
            inspect_resources,
        ),
    ]
