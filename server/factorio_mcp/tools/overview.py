from __future__ import annotations

from typing import Any

from mcp.server.mcpserver.exceptions import ToolError

from .. import jobs
from ..bridge import ModBridge, ModError, normalize_lists, normalize_maps
from ..identity import current_identity
from ..jobs import JobRunner, user_message
from .registry import ToolSpec


MAX_SURFACES = 32


def compact(result: dict[str, Any], limit: int, offset: int, only_stopped: bool) -> dict[str, Any]:
    """A whole base has hundreds of groups: answer with totals and the most stuck groups first.

    Returns the summary, machines by status and by surface, and one page of groups sorted by how
    many machines in them are not working (groups where everything works are left out unless
    `only_stopped` is false). `next` is the offset of the following page.
    """
    groups = result.get("groups", [])
    by_status: dict[str, int] = {}
    by_surface: dict[str, dict[str, int]] = {}
    for group in groups:
        group["stopped"] = group["count"] - group["working"]
        for status, n in group.get("by_status", {}).items():
            by_status[status] = by_status.get(status, 0) + n
        surface = by_surface.setdefault(group["surface"], {"machines": 0, "working": 0})
        surface["machines"] += group["count"]
        surface["working"] += group["working"]
    listed = [g for g in groups if g["stopped"] > 0] if only_stopped else list(groups)
    listed.sort(key=lambda g: (-g["stopped"], -g["count"], g["surface"], g["name"], g.get("recipe") or ""))
    limit = max(1, min(limit, 100))
    offset = max(0, offset)
    page = listed[offset : offset + limit]
    more = offset + limit < len(listed)
    return {
        "summary": result.get("summary", {}),
        "by_status": dict(sorted(by_status.items(), key=lambda kv: -kv[1])),
        "by_surface": by_surface,
        "groups": page,
        "total_groups": len(listed),
        "offset": offset,
        "next": offset + limit if more else None,
    }


def specs(bridge: ModBridge) -> list[ToolSpec]:
    runner = JobRunner(bridge)

    async def base_machines_overview(
        surfaces: list[str] | None = None,
        job_id: str | None = None,
        limit: int = 25,
        offset: int = 0,
        only_stopped: bool = True,
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
        return compact(result, limit, offset, only_stopped)

    return [
        ToolSpec(
            "base_machines_overview",
            "job_start",
            "Every production machine, lab and drill on the whole base: totals by status and surface, then "
            "groups per surface and recipe, the most stuck first, with why they stand and up to 3 positions. "
            "only_stopped=false also lists fully working groups; surfaces= limits the scan.",
            base_machines_overview,
        )
    ]
