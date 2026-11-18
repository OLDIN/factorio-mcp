from __future__ import annotations

from typing import Any

from mcp.server.mcpserver.exceptions import ToolError

from .. import jobs
from ..bridge import ModBridge, ModError, normalize_lists, normalize_maps
from ..identity import current_identity
from ..jobs import JobRunner, user_message
from .common import point_args
from .registry import ToolSpec


SYNC_MAX_RADIUS = 64.0  # larger areas run as a tick-split job in the game


def specs(bridge: ModBridge) -> list[ToolSpec]:
    runner = JobRunner(bridge)

    async def finish(job_id: str | None, args: dict[str, Any] | None, max_groups: int = 15) -> dict[str, Any]:
        try:
            result = await runner.run(
                "area", args or {}, owner=current_identity().name, wait=jobs.SOFT_TIMEOUT, handle=job_id
            )
        except ModError as err:
            message = user_message(err)
            if message:
                raise ToolError(message) from None
            raise
        return result if result.get("status") == "running" else normalize(result, max_groups)

    async def locate(nick: str) -> dict[str, Any]:
        for entry in normalize_lists(await bridge.call("players"), ["players"])["players"]:
            if entry.get("name") == nick:
                if not entry.get("online") or entry.get("position") is None:
                    raise ToolError(f"Player {nick} is offline, so there is no position to inspect.")
                return {"surface": entry["surface"], "x": entry["position"]["x"], "y": entry["position"]["y"]}
        raise ToolError(f"No such player: {nick}.")
    async def inspect_area(
        gps: str | None = None,
        player: str | None = None,
        radius: float = 32.0,
        job_id: str | None = None,
        max_groups: int = 15,
    ) -> dict[str, Any]:
        if job_id is not None:  # continue a scan that was still running
            return await finish(job_id, None, max_groups)
        args: dict[str, Any] = {"radius": radius}
        args.update(point_args(gps, player))
        if radius > SYNC_MAX_RADIUS:
            if "player" in args:  # a job needs a point: look the player up (positions are public)
                args.update(await locate(args.pop("player")))
            return await finish(None, args, max_groups)
        result = await bridge.call("area", args)
        return normalize(result, max_groups)

    def normalize(result: dict[str, Any], max_groups: int) -> dict[str, Any]:
        normalize_lists(result, ["groups", "stopped", "drills"])
        normalize_maps(
            result,
            ["totals.by_status", "groups.*.by_status", "stopped.*.modules", "stopped.*.input", "stopped.*.output"],
        )
        groups = result.get("groups", [])
        if len(groups) > max_groups:  # a big area has hundreds of groups: the most stuck ones first
            groups.sort(key=lambda g: (-(g["count"] - g["working"]), -g["count"], g["name"]))
            result["groups_omitted"] = len(groups) - max_groups
            result["groups"] = groups[:max_groups]
        return result

    return [
        ToolSpec(
            "inspect_area",
            "area",
            "Diagnose machines and mining drills around a point: how many work, how many stand and why "
            "(status), which recipes, what is stuck in their inputs/outputs, drills about to run dry. "
            "Give a [gps=x,y,surface] tag, or a player's name, or nothing to use your own position. "
            "Only production machines are read, never vehicles, corpses or inventories of players. "
            "Radii above 64 tiles are scanned in small steps over several game ticks; if the answer is "
            "status \"running\", call the tool again with the returned job_id.",
            inspect_area,
        )
    ]
