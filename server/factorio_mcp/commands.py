"""Builds the only RCON command line the service ever sends: /factorio-mcp <sub> <json>."""

from __future__ import annotations

import json
from collections.abc import Mapping
from typing import Any

ALLOWED_SUBS: frozenset[str] = frozenset(
    {
        "hello",
        "server_info",
        "players",
        "proto_recipes",
        "proto_machines",
        "proto_items",
        "proto_fluids",
        "proto_modules",
        "proto_qualities",
        "proto_technologies",
        "proto_planets",
        "area",
        "defenses",
        "production",
        "power",
        "research",
        "job_start",
        "job_result",
        "job_cancel",
        "job_status",
    }
)

MAX_ARGS_BYTES = 1000


def build_command(sub: str, args: Mapping[str, Any] | None = None) -> str:
    if sub not in ALLOWED_SUBS:
        raise ValueError(f"subcommand not allowed: {sub!r}")
    body = json.dumps(args or {}, ensure_ascii=True, separators=(",", ":"))
    if len(body.encode()) > MAX_ARGS_BYTES:
        raise ValueError(f"arguments exceed {MAX_ARGS_BYTES} bytes")
    return f"/factorio-mcp {sub} {body}"
