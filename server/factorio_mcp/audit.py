"""Audit trail: who called which tool, how long it took. Tool arguments are never logged."""

from __future__ import annotations

import logging

from .tokens import Identity

_LOGGER = logging.getLogger("factorio_mcp.audit")


def record(identity: Identity, tool: str, duration_ms: int, outcome: str) -> None:
    _LOGGER.info("who=%s tool=%s ms=%d outcome=%s", identity.name, tool, duration_ms, outcome)
