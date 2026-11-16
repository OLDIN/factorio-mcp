"""The caller's identity, set by the auth middleware and read by tools. Never taken from tool arguments."""

from __future__ import annotations

from contextvars import ContextVar

from .tokens import Identity

_current: ContextVar[Identity | None] = ContextVar("factorio_mcp_identity", default=None)


def set_identity(identity: Identity | None):
    return _current.set(identity)


def reset_identity(token) -> None:
    _current.reset(token)


def current_identity() -> Identity:
    identity = _current.get()
    if identity is None:
        raise RuntimeError("no authenticated identity in this context")
    return identity
