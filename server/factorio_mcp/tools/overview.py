from __future__ import annotations

from typing import Any

from mcp.server.mcpserver.exceptions import ToolError

from .. import jobs
from ..bridge import ModBridge, ModError, normalize_lists, normalize_maps
from ..identity import current_identity
from ..jobs import JobRunner, user_message
from .registry import ToolSpec


MAX_SURFACES = 32


def specs(bridge: ModBridge) -> list[ToolSpec]:
    runner = JobRunner(bridge)

    async def base_machines_overview(
        surfaces: list[str] | None = None, job_id: str | None = None
    ) -> dict[str, Any]:
        params: dict[str, Any] = {}
        if surfaces is not None:
            params["surfaces"] = list(dict.fromkeys(surfaces))[:MAX_SURFACES]  # each surface once
        try:
            result = await runner.run(
                "machines_overview", params, owner=current_identity().name, wait=jobs.SOFT_TIMEOUT, handle=job_id
            )
        except ModError as err:
            message = user_message(err)
            if message:
                raise ToolError(message) from None
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
