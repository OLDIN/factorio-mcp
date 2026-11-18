from __future__ import annotations

from typing import Any

from ..bridge import ModBridge, normalize_lists, normalize_maps
from .common import call_mod, caller_args, point_args
from .registry import ToolSpec


def specs(bridge: ModBridge) -> list[ToolSpec]:
    async def inspect_power(
        gps: str | None = None,
        player: str | None = None,
        radius: float = 32.0,
        limit: int = 10,
    ) -> dict[str, Any]:
        args: dict[str, Any] = {**caller_args(), **point_args(gps, player), "radius": radius, "limit": limit}
        result = await call_mod(bridge, "power", args)
        normalize_lists(result, ["networks", "starved_examples", "networks.*.top_producers", "networks.*.top_consumers"])
        normalize_maps(result, ["networks.*.starved", "networks.*.accumulators"])
        return result

    return [
        ToolSpec(
            "inspect_power",
            "power",
            "Electric networks around a point (radius up to 64, default 32): power produced and consumed now "
            "(kW, last 5 s) with the biggest producers and consumers, accumulator charge, and machines short of "
            "power. Give a [gps=x,y,surface] tag, or a player's name, or nothing to use your own position.",
            inspect_power,
        )
    ]
