from __future__ import annotations

from typing import Any

from ..bridge import ModBridge, normalize_lists, normalize_maps
from ..jobs import JobRunner
from .common import call_mod, caller_args, page, point_args, run_job
from .registry import ToolSpec

NETWORK_LISTS = ["networks.*.top_producers", "networks.*.top_consumers"]
NETWORK_MAPS = ["networks.*.starved", "networks.*.accumulators"]


def specs(bridge: ModBridge) -> list[ToolSpec]:
    runner = JobRunner(bridge)
    async def inspect_power(
        gps: str | None = None,
        player: str | None = None,
        radius: float = 32.0,
        limit: int = 10,
    ) -> dict[str, Any]:
        args: dict[str, Any] = {**caller_args(), **point_args(gps, player), "radius": radius, "limit": limit}
        result = await call_mod(bridge, "power", args)
        normalize_lists(result, ["networks", "starved_examples", *NETWORK_LISTS])
        normalize_maps(result, NETWORK_MAPS)
        return result

    async def base_power_overview(job_id: str | None = None, limit: int = 15, offset: int = 0) -> dict[str, Any]:
        result = await run_job(runner, "power_overview", caller_args(), job_id)
        if result.get("status") == "running":
            return result
        normalize_lists(result, ["networks", *NETWORK_LISTS])
        normalize_maps(result, NETWORK_MAPS)
        networks, nxt = page(result.get("networks", []), limit, offset)
        return {
            "summary": result.get("summary", {}),
            "networks": networks,
            "total_networks": len(result.get("networks", [])),
            "offset": max(0, offset),
            "next": nxt,
        }

    return [
        ToolSpec(
            "inspect_power",
            "power",
            "Electric networks around a point (radius up to 64): power produced and consumed now (kW), the "
            "biggest producers and consumers, accumulators, and machines short of power.",
            inspect_power,
        ),
        ToolSpec(
            "base_power_overview",
            "power",  # the power_overview job kind ships with the power command (mod 0.4.0+)
            "Every electric network of your force, those with machines short of power first: kW produced and "
            "consumed, the biggest producers and consumers, accumulators, a pole's [gps]. Lone idle poles are "
            "only counted.",
            base_power_overview,
        ),
    ]
