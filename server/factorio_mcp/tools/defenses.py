from __future__ import annotations

from typing import Any

from ..bridge import ModBridge, normalize_lists, normalize_maps
from .common import point_args
from .registry import ToolSpec


def specs(bridge: ModBridge) -> list[ToolSpec]:
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
        )
    ]
