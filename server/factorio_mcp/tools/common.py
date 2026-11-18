"""Helpers shared by the tools: where to look, who is asking, and calling the mod."""

from __future__ import annotations

from typing import Any

from mcp.server.mcpserver.exceptions import ToolError

from .. import jobs
from ..bridge import ModBridge, ModError, normalize_lists
from ..gps import GpsParseError, parse_gps
from ..identity import current_identity
from ..jobs import JobRunner, user_message

# Mod errors the person asking can act on; their messages are plain and safe to show.
USER_ERRORS = ("not_found", "bad_params")
OFFLINE = "player is offline: position unknown"


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
        if err.message == OFFLINE:
            raise ToolError("That player is offline, so there is no position: give a [gps=x,y,surface] tag.") from None
        if err.code in USER_ERRORS:
            raise ToolError(err.message) from None
        raise


async def locate(bridge: ModBridge, nick: str) -> dict[str, Any]:
    """A player's position as {surface, x, y} (positions are public); a job needs a point."""
    for entry in normalize_lists(await bridge.call("players"), ["players"])["players"]:
        if entry.get("name") == nick:
            if not entry.get("online") or entry.get("position") is None:
                raise ToolError("That player is offline, so there is no position: give a [gps=x,y,surface] tag.")
            return {"surface": entry["surface"], "x": entry["position"]["x"], "y": entry["position"]["y"]}
    raise ToolError(f"No such player: {nick}.")


async def run_job(runner: JobRunner, kind: str, params: dict[str, Any], job_id: str | None) -> dict[str, Any]:
    """Start (or resume with job_id) a tick-split job; errors the person can act on become ToolError."""
    try:
        return await runner.run(kind, params, owner=current_identity().name, wait=jobs.SOFT_TIMEOUT, handle=job_id)
    except ModError as err:
        message = user_message(err) or (err.message if err.code in USER_ERRORS else None)
        if message:
            raise ToolError(message) from None
        raise
