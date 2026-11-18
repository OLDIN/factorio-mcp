"""Helpers shared by the tools: where to look, who is asking, and calling the mod."""

from __future__ import annotations

from typing import Any

from mcp.server.mcpserver.exceptions import ToolError

from ..bridge import ModBridge, ModError
from ..gps import GpsParseError, parse_gps
from ..identity import current_identity

# Mod errors the person asking can act on; their messages are plain and safe to show.
USER_ERRORS = ("not_found", "bad_params")


def point_args(gps: str | None, player: str | None) -> dict[str, Any]:
    """Where to look: a [gps] tag, a player's position, or (neither) the caller's own position."""
    if gps is not None:
        try:
            point = parse_gps(gps)
        except GpsParseError as err:
            raise ToolError(f"Could not read the gps tag: {err}. Expected [gps=x,y] or [gps=x,y,surface].") from None
        return {"surface": point.surface, "x": point.x, "y": point.y}
    if player is not None:
        return {"player": player}  # any player's position is public
    return {"player": current_identity().nick}  # from the token, never from arguments


def caller_args() -> dict[str, str]:
    """Who is asking (the token's nick): the mod reads only this player's force."""
    return {"caller": current_identity().nick}


async def call_mod(bridge: ModBridge, sub: str, args: dict[str, Any]) -> Any:
    try:
        return await bridge.call(sub, args)
    except ModError as err:
        if err.code in USER_ERRORS:
            raise ToolError(err.message) from None
        raise
