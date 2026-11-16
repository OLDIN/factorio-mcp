from __future__ import annotations

from typing import Any

from ..bridge import ModBridge, normalize_lists, normalize_maps
from ..jobs import JobRunner
from .registry import ToolSpec


def specs(bridge: ModBridge) -> list[ToolSpec]:
    runner = JobRunner(bridge)

    async def base_machines_overview(surfaces: list[str] | None = None) -> dict[str, Any]:
        params: dict[str, Any] = {}
        if surfaces is not None:
            params["surfaces"] = surfaces
        result = await runner.run("machines_overview", params)
        normalize_lists(result, ["groups"])
        normalize_lists(result, ["groups.*.examples"])
        normalize_maps(result, ["groups.*.by_status"])
        return result

    return [
        ToolSpec(
            "base_machines_overview",
            "job_start",
            "Overview of every production machine, lab and drill on the whole base, per surface and recipe: "
            "how many exist, how many work, why the rest stand (status), and up to 3 example positions of "
            "stopped ones. Scans the whole map in small steps spread over game ticks, so it takes a few "
            "seconds on a big base and the players do not notice it. Optionally limit it to some surfaces.",
            base_machines_overview,
        )
    ]
