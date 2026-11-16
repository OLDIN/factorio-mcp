"""Tool specs and visibility: a tool is offered only if the installed mod knows its command."""

from __future__ import annotations

from collections.abc import Awaitable, Callable
from dataclasses import dataclass
from typing import Any

from ..bridge import Hello


@dataclass(frozen=True)
class ToolSpec:
    name: str
    requires: str | None
    description: str
    handler: Callable[..., Awaitable[Any]]


def visible(specs: list[ToolSpec], hello: Hello | None) -> list[ToolSpec]:
    if hello is None:
        return list(specs)
    return [s for s in specs if s.requires is None or s.requires in hello.commands]
