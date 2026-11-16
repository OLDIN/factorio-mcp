from __future__ import annotations

import asyncio
import hashlib
import json
from dataclasses import dataclass, field

import httpx
import pytest
import uvicorn
from fake_rcon import FakeRcon

from factorio_mcp.__main__ import uvicorn_config
from factorio_mcp.app import create_app
from factorio_mcp.bridge import ModBridge
from factorio_mcp.commands import build_command
from factorio_mcp.config import Settings
from factorio_mcp.rcon import RconLink
from factorio_mcp.tokens import TokenStore

RCON_PASSWORD = "rcon-pw-9f3a"
TOKEN_ALICE = "tok-alice-7c1d"
TOKEN_BOB = "tok-bob-22ab"


def hello_reply(commands=("hello", "server_info", "players")) -> str:
    return json.dumps(
        {
            "v": 1,
            "ok": True,
            "result": {
                "mod_version": "0.1.0",
                "protocol": 1,
                "commands": list(commands),
                "fingerprint": "base=2.1.24",
                "max_response_bytes": 48000,
            },
        }
    )


@dataclass
class Stack:
    url: str
    fake: FakeRcon
    link: RconLink
    bridge: ModBridge
    client: httpx.AsyncClient
    headers: dict = field(default_factory=dict)

    def auth(self, token: str = TOKEN_ALICE) -> dict:
        return {
            "Authorization": f"Bearer {token}",
            "Accept": "application/json, text/event-stream",
            "Content-Type": "application/json",
        }

    def reply(self, sub: str, payload) -> None:
        text = payload if isinstance(payload, str) else json.dumps(payload)
        self.fake.responses[build_command(sub)] = text

    async def rpc(self, method: str, params: dict | None = None, token: str = TOKEN_ALICE):
        body = {"jsonrpc": "2.0", "id": 1, "method": method, "params": params or {}}
        return await self.client.post("/mcp", json=body, headers=self.auth(token))

    async def tool_names(self) -> list[str]:
        r = await self.rpc("tools/list")
        return [t["name"] for t in r.json()["result"]["tools"]]


@pytest.fixture
async def stack(tmp_path, monkeypatch):
    """Real uvicorn + real RconLink against FakeRcon, talking plain HTTP like a real client."""
    entries = "".join(
        f'[[token]]\nname = "{n}"\nnick = "{n}Nick"\nsha256 = "{hashlib.sha256(t.encode()).hexdigest()}"\n'
        for n, t in (("alice", TOKEN_ALICE), ("bob", TOKEN_BOB))
    )
    tokens_file = tmp_path / "tokens.toml"
    tokens_file.write_text(entries)
    fake = FakeRcon(RCON_PASSWORD)
    fake.responses[build_command("hello")] = hello_reply()
    await fake.start()
    settings = Settings.from_env(
        {
            "FACTORIO_MCP_RCON_PASSWORD": RCON_PASSWORD,
            "FACTORIO_MCP_TOKENS_FILE": str(tokens_file),
            "FACTORIO_MCP_PORT": "0",
        }
    )
    link = RconLink("127.0.0.1", fake.port, RCON_PASSWORD, retry_delay=0.05)
    bridge = ModBridge(link)
    app = create_app(settings, bridge, TokenStore(tokens_file))
    server = uvicorn.Server(uvicorn_config(app, settings))
    serve = asyncio.create_task(server.serve())
    rcon_task = asyncio.create_task(link.run())
    while not server.started:
        await asyncio.sleep(0.02)
    for _ in range(100):
        if link.alive and bridge.last_hello is not None:
            break
        await asyncio.sleep(0.02)
    port = server.servers[0].sockets[0].getsockname()[1]
    # The client-side httpx logger would print request URLs; it is not the service under test.
    import logging

    logging.getLogger("httpx").setLevel(logging.WARNING)
    async with httpx.AsyncClient(base_url=f"http://127.0.0.1:{port}") as client:
        yield Stack(f"http://127.0.0.1:{port}", fake, link, bridge, client)
    server.should_exit = True
    rcon_task.cancel()
    await asyncio.gather(serve, rcon_task, return_exceptions=True)
    await fake.stop()
