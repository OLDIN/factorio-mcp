from __future__ import annotations

from typing import Any

from ..bridge import ModBridge, normalize_lists, normalize_maps
from .common import call_mod, caller_args
from .registry import ToolSpec


def specs(bridge: ModBridge) -> list[ToolSpec]:
    async def logistic_networks(surface: str | None = None, name: str | None = None, limit: int = 15) -> dict[str, Any]:
        args: dict[str, Any] = {**caller_args(), "limit": limit}
        if surface is not None:
            args["surface"] = surface
        if name is not None:
            args["name"] = name
        result = await call_mod(bridge, "logistics", args)
        return normalize_lists(result, ["networks", "networks.*.top_contents", "by_network"])

    async def list_trains(
        surface: str | None = None, problems_only: bool = False, offset: int = 0, limit: int = 15
    ) -> dict[str, Any]:
        args: dict[str, Any] = {**caller_args(), "problems_only": problems_only, "offset": offset, "limit": limit}
        if surface is not None:
            args["surface"] = surface
        result = await call_mod(bridge, "trains", args)
        normalize_lists(result, ["trains", "trains.*.cargo", "trains.*.fluids"])
        normalize_maps(result, ["by_state"])
        result.setdefault("next", None)
        return result

    async def list_platforms(name: str | None = None, limit: int = 10) -> dict[str, Any]:
        args: dict[str, Any] = {**caller_args(), "limit": limit}
        if name is not None:
            args["name"] = name
        result = await call_mod(bridge, "platforms", args)
        return normalize_lists(result, ["platforms", "platforms.*.hub_contents"])

    return [
        ToolSpec(
            "list_platforms",
            "platforms",
            "Your force's space platforms: state, where each is or last was, speed, damaged tiles, the hub's "
            "biggest stocks. name= for one platform. Empty without Space Age.",
            list_platforms,
        ),
        ToolSpec(
            "list_trains",
            "trains",
            "Your force's trains: counts by state, then problem trains first (no path, destination full, no "
            "schedule, manual with cargo, over 5 minutes at a station) with station or target, cargo and "
            "[gps]. problems_only=true lists only those.",
            list_trains,
        ),
        ToolSpec(
            "logistic_networks",
            "logistics",
            "Your force's logistic networks per surface: robots available and total, roboports, robots "
            "waiting to charge, the biggest stocks; the busiest first. name= counts one item across networks.",
            logistic_networks,
        )
    ]
