"""End-to-end: real Factorio (scripts/live.sh) -> RconLink -> mod -> service -> official MCP client."""

from __future__ import annotations

import asyncio
import hashlib
import json
import logging
import os

import httpx
import httpx2
import pytest
import uvicorn
from mcp.client import Client
from mcp.client.streamable_http import streamable_http_client

from factorio_mcp.__main__ import uvicorn_config
from factorio_mcp.app import create_app
from factorio_mcp.bridge import ModBridge
from factorio_mcp.config import Settings
from factorio_mcp.rcon import RconLink
from factorio_mcp.tokens import TokenStore

pytestmark = pytest.mark.live

TOKEN = "e2e-token-alice"


@pytest.fixture
async def service(tmp_path):
    tokens_file = tmp_path / "tokens.toml"
    digest = hashlib.sha256(TOKEN.encode()).hexdigest()
    tokens_file.write_text(f'[[token]]\nname = "alice"\nnick = "alice"\nsha256 = "{digest}"\n')
    settings = Settings.from_env(
        {
            "FACTORIO_MCP_RCON_PASSWORD": "dev",
            "FACTORIO_MCP_TOKENS_FILE": str(tokens_file),
            "FACTORIO_MCP_PORT": "0",
        }
    )
    link = RconLink("127.0.0.1", 27015, "dev", retry_delay=0.2)
    bridge = ModBridge(link)
    server = uvicorn.Server(uvicorn_config(create_app(settings, bridge, TokenStore(tokens_file)), settings))
    serve = asyncio.create_task(server.serve())
    rcon_task = asyncio.create_task(link.run())
    while not server.started:
        await asyncio.sleep(0.05)
    for _ in range(100):
        if bridge.last_hello is not None:
            break
        await asyncio.sleep(0.1)
    assert bridge.last_hello is not None, "mod did not answer hello"
    logging.getLogger("httpx").setLevel(logging.WARNING)
    yield f"http://127.0.0.1:{server.servers[0].sockets[0].getsockname()[1]}", tokens_file
    server.should_exit = True
    rcon_task.cancel()
    await asyncio.gather(serve, rcon_task, return_exceptions=True)


def _text(result) -> dict:
    return json.loads(result.content[0].text)


async def test_status_and_players_through_official_client(service):
    url, _ = service
    http = httpx2.AsyncClient(headers={"Authorization": f"Bearer {TOKEN}"})
    async with Client(streamable_http_client(f"{url}/mcp", http_client=http)) as client:
        names = {t.name for t in (await client.list_tools()).tools}
        assert {"server_status", "list_players"} <= names
        status = _text(await client.call_tool("server_status", {}))
        assert status["status"] == "ok"
        assert "base" in status["mods"] and "factorio-mcp" in status["mods"]
        players = _text(await client.call_tool("list_players", {}))
        assert isinstance(players["players"], list)


async def test_no_token_is_401_and_revocation_needs_no_restart(service):
    url, tokens_file = service
    headers = {"Authorization": f"Bearer {TOKEN}", "Accept": "application/json, text/event-stream"}
    body = {"jsonrpc": "2.0", "id": 1, "method": "tools/list"}
    async with httpx.AsyncClient() as http:
        assert (await http.post(f"{url}/mcp", json=body)).status_code == 401
        assert (await http.post(f"{url}/mcp", json=body, headers=headers)).status_code == 200
        tokens_file.write_text("")
        stat = tokens_file.stat()
        os.utime(tokens_file, ns=(stat.st_atime_ns, stat.st_mtime_ns + 5 * 10**9))
        assert (await http.post(f"{url}/mcp", json=body, headers=headers)).status_code == 401
