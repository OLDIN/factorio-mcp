from __future__ import annotations

from typing import Any

from ..bridge import ModBridge, normalize_lists, normalize_maps
from ..jobs import JobRunner
from .common import caller_args, page, point_args, run_job
from .registry import ToolSpec


def specs(bridge: ModBridge) -> list[ToolSpec]:
    runner = JobRunner(bridge)

    async def base_defenses_overview(job_id: str | None = None, limit: int = 25, offset: int = 0) -> dict[str, Any]:
        result = await run_job(runner, "defenses_overview", caller_args(), job_id)
        if result.get("status") == "running":
            return result
        normalize_lists(result, ["problems", "groups"])
        normalize_maps(result, ["summary.issues", "by_surface", "groups.*.ammo", "groups.*.fluids"])
        problems, nxt = page(result.get("problems", []), limit, offset)
        return {
            "summary": result.get("summary", {}),
            "by_surface": result.get("by_surface", {}),
            "groups": result.get("groups", []),
            "problems": problems,
            "problems_total": result.get("problems_total", len(result.get("problems", []))),
            "offset": max(0, offset),
            "next": nxt,
        }
    async def inspect_defenses(
        gps: str | None = None,
        player: str | None = None,
        radius: float = 32.0,
        max_listed: int = 20,
    ) -> dict[str, Any]:
        args: dict[str, Any] = {"radius": radius, "max_listed": max_listed}
        args.update(point_args(gps, player))

        result = await bridge.call("defenses", args)
        return normalize(result)

    def normalize(result: dict[str, Any]) -> dict[str, Any]:
        normalize_lists(result, ["groups", "problems"])
        normalize_maps(
            result,
            [
                "summary.issues",
                "groups.*.ammo",
                "groups.*.fluids",
            ],
        )
        return result

    return [
        ToolSpec(
            "inspect_defenses",
            "defenses",
            "Inspect military defenses, turrets, and walls around a point: returns counts of gun, laser, "
            "flamethrower, rocket and tesla turrets, ammo and fuel/fluid readiness, power state, wall health, "
            "and a prioritized list of compromised or unsupplied defense structures (no ammo, no power, "
            "no fluid, or damaged). Enemy worms and neutral entities are not counted. Radius up to 64 tiles "
            "(default 32), max_listed up to 50. Give a [gps=x,y,surface] tag, or a player's name, or nothing "
            "to use your own position.",
            inspect_defenses,
        ),
        ToolSpec(
            "base_defenses_overview",
            "threats",  # the defenses_overview job kind ships with mod 0.4.0, as does `threats`
            "Defenses of your force on the whole base: turrets, walls, mines and radars per surface, issue counts, "
            "and the worst problems first with [gps] (turrets without ammo, power or fluid, then damaged ones). "
            "Scans in small steps over game ticks; if the answer is status \"running\", call again with the "
            "returned job_id. Pages with offset/limit.",
            base_defenses_overview,
        ),
    ]
