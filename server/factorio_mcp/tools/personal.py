"""Own-only tools: the caller's inventory and alerts. They take no player argument; the mod gets the
token's nick and nothing else, so nobody can read another player's inventory or alerts."""

from __future__ import annotations

from typing import Any

from ..bridge import ModBridge, normalize_lists
from .common import call_mod, caller_args
from .registry import ToolSpec


def specs(bridge: ModBridge) -> list[ToolSpec]:
    async def my_inventory() -> dict[str, Any]:
        result = await call_mod(bridge, "inventory", caller_args())
        return normalize_lists(result, ["main", "guns", "ammo", "armor.equipment"])

    async def my_alerts(limit: int = 5) -> dict[str, Any]:
        result = await call_mod(bridge, "alerts", {**caller_args(), "limit": limit})
        return normalize_lists(result, ["by_type", "by_type.*.examples"])

    return [
        ToolSpec(
            "my_inventory",
            "inventory",
            "Your own inventory only (never another player's): main inventory by stack size, armor and its "
            "equipment, guns and ammo, crafting queue size. Offline, it may not be readable.",
            my_inventory,
        ),
        ToolSpec(
            "my_alerts",
            "alerts",
            "Your own alerts only: grouped by type (entity destroyed, turret out of ammo, no material for "
            "construction, train without path, ...) with counts and up to `limit` examples per type with [gps].",
            my_alerts,
        ),
    ]
