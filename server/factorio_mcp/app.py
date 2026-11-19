"""ASGI application: /health, bearer-protected /mcp (Streamable HTTP, stateless)."""

from __future__ import annotations

import asyncio
import functools
import json
import logging
import time
from collections.abc import Awaitable, Callable
from typing import Any
from urllib.parse import parse_qs

from mcp.server.mcpserver import MCPServer
from mcp.server.mcpserver.exceptions import ToolError
from mcp.server.transport_security import TransportSecuritySettings
from starlette.types import ASGIApp, Receive, Scope, Send

from . import audit
from .bridge import GameUnavailable, Hello, ModBridge, ModError, ModMissing
from .config import Settings
from .identity import current_identity, reset_identity, set_identity
from .instructions import INSTRUCTIONS
from .tokens import TokenStore
from .tools import area, defenses, logistics, nearby, overview, personal, players, power, production, reference, research, server, threats
from .tools.registry import ToolSpec, visible

_LOGGER = logging.getLogger(__name__)
_UNAUTHORIZED = json.dumps({"error": "unauthorized"}).encode()


async def _respond(send: Send, status: int, body: bytes, extra: list[tuple[bytes, bytes]] | None = None) -> None:
    headers = [(b"content-type", b"application/json"), (b"content-length", str(len(body)).encode())]
    await send({"type": "http.response.start", "status": status, "headers": headers + (extra or [])})
    await send({"type": "http.response.body", "body": body})


class _Gate:
    """Pure-ASGI front door: health, query-token rejection, bearer auth, identity contextvar."""

    def __init__(self, inner: ASGIApp, tokens: TokenStore) -> None:
        self._inner = inner
        self._tokens = tokens

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self._inner(scope, receive, send)  # lifespan etc.
            return
        if scope["path"] == "/health":
            await _respond(send, 200, b'{"status":"ok"}')
            return
        query = parse_qs(scope.get("query_string", b"").decode(errors="replace"), keep_blank_values=True)
        if "token" in query:
            await _respond(send, 400, b'{"error":"token must not be sent in the URL"}')
            return
        auth = dict(scope["headers"]).get(b"authorization", b"").decode(errors="replace")
        scheme, _, token = auth.partition(" ")
        identity = self._tokens.authenticate(token.strip()) if scheme.lower() == "bearer" else None
        if identity is None:
            await _respond(send, 401, _UNAUTHORIZED, [(b"www-authenticate", b"Bearer")])
            return
        marker = set_identity(identity)
        try:
            await self._inner(scope, receive, send)
        finally:
            reset_identity(marker)


def _security(settings: Settings) -> TransportSecuritySettings | None:
    if not settings.allowed_hosts:
        return None  # the SDK still protects loopback binds by default
    hosts = [h for h in settings.allowed_hosts] + [f"{h}:*" for h in settings.allowed_hosts]
    return TransportSecuritySettings(enable_dns_rebinding_protection=True, allowed_hosts=hosts, allowed_origins=[])


def _wrap(spec: ToolSpec) -> Callable[..., Awaitable[Any]]:
    @functools.wraps(spec.handler)  # the SDK derives the tool's input schema from the signature
    async def run(**kwargs: Any) -> Any:
        identity = current_identity()
        started = time.monotonic()
        outcome = "ok"
        try:
            return await spec.handler(**kwargs)
        except ModMissing:
            outcome = "error"
            raise ToolError("The factorio-mcp mod is not installed on the game server.") from None
        except GameUnavailable:
            outcome = "error"
            raise ToolError("The game server is unavailable.") from None
        except ModError as err:
            outcome = "error"
            raise ToolError(f"Mod error: {err.code}: {err.message}") from None
        except asyncio.CancelledError:
            outcome = "cancelled"  # the client gave up (timeout, disconnect)
            raise
        except Exception:
            outcome = "error"
            raise
        finally:
            audit.record(identity, spec.name, int((time.monotonic() - started) * 1000), outcome)

    return run


def _without_titles(schema: Any) -> Any:
    """A JSON schema without its `title` strings: the SDK derives one per parameter from its name, and
    tools/list is paid for in context on every conversation."""
    if isinstance(schema, dict):
        return {k: _without_titles(v) for k, v in schema.items() if not (k == "title" and isinstance(v, str))}
    if isinstance(schema, list):
        return [_without_titles(v) for v in schema]
    return schema


class _LeanServer(MCPServer):
    """Lists tools with lean input schemas (no titles)."""

    async def list_tools(self):  # type: ignore[override]
        return [t.model_copy(update={"input_schema": _without_titles(t.input_schema)}) for t in await super().list_tools()]


def create_app(settings: Settings, bridge: ModBridge, tokens: TokenStore) -> ASGIApp:
    mcp = _LeanServer("factorio-mcp", instructions=INSTRUCTIONS)
    all_specs = [
        *server.specs(bridge),
        *players.specs(bridge),
        *reference.specs(bridge),
        *area.specs(bridge),
        *defenses.specs(bridge),
        *overview.specs(bridge),
        *production.specs(bridge),
        *power.specs(bridge),
        *research.specs(bridge),
        *threats.specs(bridge),
        *logistics.specs(bridge),
        *personal.specs(bridge),
        *nearby.specs(bridge),
    ]
    registered: set[str] = set()

    def sync_tools(hello: Hello | None) -> None:
        wanted = {s.name: s for s in visible(all_specs, hello)}
        for name in registered - wanted.keys():
            mcp.remove_tool(name)
        for name, spec in wanted.items():
            if name not in registered:
                # results are JSON text: no output schema and no duplicate structured copy of each answer
                mcp.add_tool(_wrap(spec), name=name, description=spec.description, structured_output=False)
        registered.clear()
        registered.update(wanted)

    sync_tools(bridge.last_hello)
    bridge.on_hello_changed.append(sync_tools)
    inner = mcp.streamable_http_app(
        stateless_http=True,
        json_response=True,
        transport_security=_security(settings),
        host=settings.host,
    )
    return _Gate(inner, tokens)
