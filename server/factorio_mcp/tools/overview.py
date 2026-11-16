from __future__ import annotations

from typing import Any

from mcp.server.mcpserver.exceptions import ToolError

from .. import jobs
from ..bridge import ModBridge, ModError, normalize_lists, normalize_maps
from ..jobs import JobRunner
from .registry import ToolSpec


MAX_SURFACES = 32


def specs(bridge: ModBridge) -> list[ToolSpec]:
    runner = JobRunner(bridge)

    async def base_machines_overview(
        surfaces: list[str] | None = None, job_id: int | None = None
    ) -> dict[str, Any]:
        params: dict[str, Any] = {}
        if surfaces is not None:
            params["surfaces"] = list(dict.fromkeys(surfaces))[:MAX_SURFACES]  # each surface once
        try:
            result = await runner.run("machines_overview", params, wait=jobs.SOFT_TIMEOUT, job_id=job_id)
        except ModError as err:
            if err.code == "job_not_found":
                raise ToolError(
                    "That scan is gone (already collected, expired or cancelled). Start a new one without job_id."
                ) from None
            raise
        if result.get("status") == "running":
            return result
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
            "stopped ones. Scans the whole map in small steps spread over game ticks, so players do not "
            "notice it, but a big base can take a minute or two. If the answer is status \"running\", call "
            "the tool again with the returned job_id to get the result. Optionally limit it to some surfaces.",
            base_machines_overview,
        )
    ]
