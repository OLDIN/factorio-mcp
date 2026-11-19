from __future__ import annotations

from typing import Any

from ..bridge import ModBridge, normalize_lists
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

    return [
        ToolSpec(
            "logistic_networks",
            "logistics",
            "Your force's logistic networks per surface: logistic and construction robots (available/total), "
            "roboports, robots waiting to charge, and the biggest stocks; the busiest networks first. Give "
            "name= to count one item across networks.",
            logistic_networks,
        )
    ]
