from __future__ import annotations

from typing import Any

from mcp.server.mcpserver.exceptions import ToolError

from ..bridge import ModBridge, normalize_lists, normalize_maps
from ..gps import GpsParseError, parse_gps
from ..identity import current_identity
from .registry import ToolSpec


def specs(bridge: ModBridge) -> list[ToolSpec]:
    async def inspect_defenses(
        gps: str | None = None,
        player: str | None = None,
        radius: float = 32.0,
        max_listed: int = 20,
    ) -> dict[str, Any]:
        args: dict[str, Any] = {"radius": radius, "max_listed": max_listed}
        if gps is not None:
            try:
                point = parse_gps(gps)
            except GpsParseError as err:
                raise ToolError(f"Could not read the gps tag: {err}. Expected [gps=x,y] or [gps=x,y,surface].") from None
            args.update(surface=point.surface, x=point.x, y=point.y)
        elif player is not None:
            args["player"] = player
        else:
            args["player"] = current_identity().nick

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
        )
    ]
