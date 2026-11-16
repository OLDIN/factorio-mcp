from __future__ import annotations

from stack_fixture import TOKEN_ALICE


async def test_health_needs_no_token_and_no_rcon(stack):
    stack.link._drop()  # simulate RCON down
    r = await stack.client.get("/health")
    assert r.status_code == 200 and r.json() == {"status": "ok"}
    assert "rcon" not in r.text.lower()


async def test_mcp_requires_bearer(stack):
    for headers in ({}, {"Authorization": "Bearer wrong"}, {"Authorization": "Basic abc"}):
        r = await stack.client.post("/mcp", json={"jsonrpc": "2.0", "id": 1, "method": "tools/list"}, headers=headers)
        assert r.status_code == 401
    bodies = {
        (await stack.client.post("/mcp", headers=h)).text
        for h in ({}, {"Authorization": "Bearer wrong"})
    }
    assert len(bodies) == 1  # identical body for missing and wrong token


async def test_valid_token_works(stack):
    assert "server_status" in await stack.tool_names()


async def test_query_token_rejected(stack):
    r = await stack.client.post(f"/mcp?token={TOKEN_ALICE}", json={}, headers=stack.auth())
    assert r.status_code == 400


async def test_no_wildcard_cors(stack):
    r = await stack.client.get("/health", headers={"Origin": "http://evil.example"})
    assert "access-control-allow-origin" not in r.headers
    r = await stack.rpc("tools/list")
    assert r.headers.get("access-control-allow-origin") != "*"


async def test_revoked_token_stops_working_without_restart(stack, tmp_path):
    import os

    f = tmp_path / "tokens.toml"
    f.write_text("")
    st = f.stat()
    os.utime(f, ns=(st.st_atime_ns, st.st_mtime_ns + 5 * 10**9))
    assert (await stack.rpc("tools/list")).status_code == 401

