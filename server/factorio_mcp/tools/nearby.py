"""Local details around a point: resource patches, and belts, inserters and pipes."""

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

    async def inspect_transport(
        gps: str | None = None, player: str | None = None, radius: float = 16.0, limit: int = 15
    ) -> dict[str, Any]:
        args = {**caller_args(), **point_args(gps, player), "radius": radius, "limit": limit}
        result = await call_mod(bridge, "transport", args)
        normalize_lists(result, ["inserters.stuck", "belts.items", "fluids"])
        return normalize_maps(result, ["counts", "inserters.by_status"])

    return [
        ToolSpec(
            "inspect_resources",
            "resources",
            "Resource patches around a [gps] point, a player, or yourself (radius up to 128 tiles, default 64): "
            "each patch with its resource, amount, tiles (or wells for crude oil, raw amount), centre [gps], "
            "most tiles first; plus the totals for the whole surface.",
            inspect_resources,
        ),
        ToolSpec(
            "inspect_transport",
            "transport",
            "Belts, inserters and pipes of your force around a [gps] point, a player, or yourself (radius up to "
            "32 tiles, default 16): counts, inserters by status with the stuck ones first (no power, output "
            "blocked, waiting for items) with [gps], the items on the belts, and the fluids in pipes and tanks.",
            inspect_transport,
        ),
    ]
