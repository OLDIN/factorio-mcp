from __future__ import annotations

from typing import Any

from mcp.server.mcpserver.exceptions import ToolError

from ..bridge import ModBridge, normalize_lists, normalize_maps
from ..gps import GpsParseError, parse_gps
from ..identity import current_identity
from ..jobs import JobRunner
from .registry import ToolSpec


SYNC_MAX_RADIUS = 64.0  # larger areas run as a tick-split job in the game


def specs(bridge: ModBridge) -> list[ToolSpec]:
    runner = JobRunner(bridge)

    async def locate(nick: str) -> dict[str, Any]:
        for entry in normalize_lists(await bridge.call("players"), ["players"])["players"]:
            if entry.get("name") == nick:
                if not entry.get("online") or entry.get("position") is None:
                    raise ToolError(f"Player {nick} is offline, so there is no position to inspect.")
                return {"surface": entry["surface"], "x": entry["position"]["x"], "y": entry["position"]["y"]}
        raise ToolError(f"No such player: {nick}.")
    async def inspect_area(
        gps: str | None = None, player: str | None = None, radius: float = 32.0
    ) -> dict[str, Any]:
        args: dict[str, Any] = {"radius": radius}
        if gps is not None:
            try:
                point = parse_gps(gps)
            except GpsParseError as err:
                raise ToolError(f"Could not read the gps tag: {err}. Expected [gps=x,y] or [gps=x,y,surface].") from None
            args.update(surface=point.surface, x=point.x, y=point.y)
        elif player is not None:
            args["player"] = player  # any player's position is public
        else:
            args["player"] = current_identity().nick  # from the token, never from arguments
        if radius > SYNC_MAX_RADIUS:
            if "player" in args:  # a job needs a point: look the player up (positions are public)
                args.update(await locate(args.pop("player")))
            result = await runner.run("area", args)
        else:
            result = await bridge.call("area", args)
        normalize_lists(result, ["groups", "stopped", "drills"])
        normalize_maps(
            result,
            ["totals.by_status", "groups.*.by_status", "stopped.*.modules", "stopped.*.input", "stopped.*.output"],
        )
        return result

    return [
        ToolSpec(
            "inspect_area",
            "area",
            "Diagnose machines and mining drills around a point: how many work, how many stand and why "
            "(status), which recipes, what is stuck in their inputs/outputs, drills about to run dry. "
            "Give a [gps=x,y,surface] tag, or a player's name, or nothing to use your own position. "
            "Only production machines are read, never vehicles, corpses or inventories of players. "
            "Radii above 64 tiles are scanned in small steps over several game ticks (a few seconds).",
            inspect_area,
        )
    ]
