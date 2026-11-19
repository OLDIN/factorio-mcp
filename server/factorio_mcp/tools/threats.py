from __future__ import annotations

from typing import Any

from ..bridge import ModBridge, normalize_lists, normalize_maps
from ..jobs import JobRunner
from .common import call_mod, caller_args, locate, point_args, run_job
from .registry import ToolSpec

SYNC_MAX_RADIUS = 256.0  # larger radii run as a tick-split job in the game


def normalize_threats(result: dict[str, Any]) -> dict[str, Any]:
    normalize_lists(result, ["nearest"])
    normalize_maps(result, ["counts"])
    return result


def specs(bridge: ModBridge) -> list[ToolSpec]:
    runner = JobRunner(bridge)

    async def inspect_threats(
        gps: str | None = None,
        player: str | None = None,
        radius: float = 128.0,
        limit: int = 10,
        job_id: str | None = None,
    ) -> dict[str, Any]:
        if job_id is not None:  # continue a scan that was still running
            result = await run_job(runner, "threats", {}, job_id)
            return result if result.get("status") == "running" else normalize_threats(result)
        point = point_args(gps, player)
        if radius > SYNC_MAX_RADIUS:
            if "player" in point:  # a job needs a point: look the player up
                point = await locate(bridge, point["player"])
            params = {**caller_args(), **point, "radius": radius, "limit": limit}
            result = await run_job(runner, "threats", params, None)
            return result if result.get("status") == "running" else normalize_threats(result)
        args = {**caller_args(), **point, "radius": radius, "limit": limit}
        return normalize_threats(await call_mod(bridge, "threats", args))

    async def inspect_pollution(
        gps: str | None = None, player: str | None = None, grid: int = 9, limit: int = 10
    ) -> dict[str, Any]:
        args = {**caller_args(), **point_args(gps, player), "grid": grid, "limit": limit}
        result = await call_mod(bridge, "pollution", args)
        return normalize_lists(result, ["top_cells", "sources", "fed_spawners"])

    return [
        ToolSpec(
            "inspect_threats",
            "threats",
            "Enemy nests, worms and demolishers around a point (radius up to 1000; above 256 it runs as a "
            "job): counts by name and the nearest ones with distance, direction, [gps] and the pollution "
            "reaching each nest.",
            inspect_threats,
        ),
        ToolSpec(
            "inspect_pollution",
            "pollution",
            "Pollution around a point: the surface's pollutant (spores on Gleba) and total, the most polluted "
            "chunks of a grid (odd, default 9 chunks), the biggest polluters per minute, and the nests the "
            "pollution reaches (fed nests attack).",
            inspect_pollution,
        ),
    ]
