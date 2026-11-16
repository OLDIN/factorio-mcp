"""Bridge to the factorio-mcp mod: one RCON command in, one parsed JSON envelope out."""

from __future__ import annotations

import hashlib
import json
import logging
from collections.abc import Callable, Iterable, Mapping
from dataclasses import dataclass
from typing import Any

from .commands import build_command
from .rcon import RconError, RconLink

_LOGGER = logging.getLogger(__name__)
PROTOCOL = 1


class ModError(Exception):
    def __init__(self, code: str, message: str = "") -> None:
        super().__init__(f"{code}: {message}")
        self.code = code
        self.message = message


class GameUnavailable(Exception):
    """RCON is down or the game does not answer."""


class ModMissing(Exception):
    """The game runs, but the factorio-mcp mod is not installed."""


@dataclass(frozen=True)
class Hello:
    mod_version: str
    protocol: int
    commands: frozenset[str]
    fingerprint: str
    max_response_bytes: int


def normalize_maps(obj: Any, map_paths: Iterable[str]) -> Any:
    """Turn `[]` (how Lua can encode an empty table) into `{}` at the given paths ('*' = any key/index)."""
    for path in map_paths:
        _normalize(obj, path.split("."), empty={}, when=[])
    return obj


def _normalize(node: Any, parts: list[str], empty: Any, when: Any) -> None:
    """Replace an empty `when` value with a fresh copy of `empty` at the path."""
    head, rest = parts[0], parts[1:]
    if head == "*":
        children = list(node.values()) if isinstance(node, dict) else node if isinstance(node, list) else []
        for child in children:
            if rest:
                _normalize(child, rest, empty, when)
        if not rest and isinstance(node, dict):
            for key, value in node.items():
                if value == when and type(value) is type(when):
                    node[key] = type(empty)()
        return
    if isinstance(node, dict) and head in node:
        if rest:
            _normalize(node[head], rest, empty, when)
        elif node[head] == when and type(node[head]) is type(when):
            node[head] = type(empty)()


def normalize_lists(obj: Any, list_paths: Iterable[str]) -> Any:
    """Turn `{}` (how Factorio 2.1 encodes an empty Lua table) into `[]` at the given paths."""
    for path in list_paths:
        _normalize(obj, path.split("."), empty=[], when={})
    return obj


class ModBridge:
    def __init__(self, rcon: RconLink) -> None:
        self._rcon = rcon
        self.last_hello: Hello | None = None
        self.on_hello_changed: list[Callable[[Hello | None], None]] = []
        rcon.on_connected = self._on_connected

    async def _on_connected(self) -> None:
        try:
            await self.refresh_hello()
        except (GameUnavailable, ModMissing, ModError) as err:
            _LOGGER.warning("hello failed: %s", type(err).__name__)
            self._set_hello(None)

    def _set_hello(self, hello: Hello | None) -> None:
        changed = hello != self.last_hello
        self.last_hello = hello
        if changed:
            for callback in self.on_hello_changed:
                callback(hello)

    async def _exec(self, sub: str, args: Mapping[str, Any] | None) -> dict[str, Any]:
        command = build_command(sub, args)
        try:
            text = await self._rcon.exec(command)
        except RconError as err:
            raise GameUnavailable(str(err)) from None
        try:
            envelope = json.loads(text)
        except ValueError:
            if "unknown command" in text.lower():
                raise ModMissing("factorio-mcp mod is not installed") from None
            raise ModError("bad_response", "reply is not valid JSON") from None
        if not isinstance(envelope, dict):
            raise ModError("bad_response", "reply is not an object")
        if envelope.get("v") != PROTOCOL:
            raise ModError("protocol_mismatch", f"mod speaks protocol {envelope.get('v')!r}")
        if envelope.get("ok") is not True:
            error = envelope.get("error")
            if not isinstance(error, dict):
                raise ModError("bad_response", "error envelope without error")
            raise ModError(str(error.get("code", "internal")), str(error.get("message", "")))
        result = envelope.get("result")
        return result if isinstance(result, dict) else {}

    async def refresh_hello(self) -> Hello:
        result = await self._exec("hello", None)
        try:
            hello = Hello(
                mod_version=str(result["mod_version"]),
                protocol=int(result["protocol"]),
                commands=frozenset(str(c) for c in result["commands"]),
                fingerprint=hashlib.sha256(str(result["fingerprint"]).encode()).hexdigest(),
                max_response_bytes=int(result["max_response_bytes"]),
            )
        except (KeyError, TypeError, ValueError):
            raise ModError("bad_response", "malformed hello") from None
        self._set_hello(hello)
        return hello

    async def call(self, sub: str, args: Mapping[str, Any] | None = None) -> dict[str, Any]:
        return await self._exec(sub, args)
