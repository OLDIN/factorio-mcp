"""Local details around a point: resource patches, and belts, inserters and pipes."""

from __future__ import annotations

from typing import Any

from ..bridge import ModBridge, normalize_lists, normalize_maps
from ..jobs import JobRunner
from .common import call_mod, caller_args, page, point_args, run_job
from .registry import ToolSpec

MAX_SURFACES = 32


def specs(bridge: ModBridge) -> list[ToolSpec]:
    runner = JobRunner(bridge)

    async def inspect_resources(
        gps: str | None = None,
        player: str | None = None,
        radius: float = 64.0,
        limit: int = 10,
        job_id: str | None = None,
    ) -> dict[str, Any]:
        if job_id is not None:  # continue a scan that was still running
            result = await run_job(runner, "resources", {}, job_id)
            return result if result.get("status") == "running" else normalize_lists(result, ["patches"])
        point = point_args(gps, player)
        args = {**caller_args(), **point, "radius": radius, "limit": limit}
        result = await call_mod(bridge, "resources", args)
        if result.get("job_needed"):
            # too many tiles to read in one tick: the same question as a job spread over ticks
            center = result["center"]
            params = {
                **caller_args(),
                "surface": center["surface"],
                "x": center["x"],
                "y": center["y"],
                "radius": radius,
                "limit": limit,
            }
            result = await run_job(runner, "resources", params, None)
            if result.get("status") == "running":
                return result
        return normalize_lists(result, ["patches"])

    async def base_resources_overview(
        surfaces: list[str] | None = None, job_id: str | None = None, limit: int = 30, offset: int = 0
    ) -> dict[str, Any]:
        params: dict[str, Any] = caller_args()
        if surfaces is not None:
            params["surfaces"] = list(dict.fromkeys(surfaces))[:MAX_SURFACES]  # each surface once
        result = await run_job(runner, "resources_overview", params, job_id)
        if result.get("status") == "running":
            return result
        normalize_lists(result, ["resources"])
        listed, nxt = page(result.get("resources", []), limit, offset)
        return {
            "summary": result.get("summary", {}),
            "resources": listed,
            "total_resources": len(result.get("resources", [])),
            "offset": max(0, offset),
            "next": nxt,
        }

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
            "Resource patches around a point (radius up to 128): resource, amount, tiles (wells and raw "
            "amount for crude oil), centre [gps], most tiles first. For whole surfaces use "
            "base_resources_overview.",
            inspect_resources,
        ),
        ToolSpec(
            "base_resources_overview",
            "resources",  # the resources_overview job kind ships with the resources command (mod 0.4.0+)
            "Resources left on every surface, or the listed ones: amount and tiles per resource (wells and "
            "raw amount for fluids such as crude oil), ores first, most first.",
            base_resources_overview,
        ),
        ToolSpec(
            "inspect_transport",
            "transport",
            "Belts, inserters and pipes of your force around a point (radius up to 32): counts, stuck "
            "inserters first (no power, output blocked, waiting for items) with [gps], the items on belts (a "
            "sample of 100 belts on a packed bus), fluids in pipes and tanks.",
            inspect_transport,
        ),
    ]
