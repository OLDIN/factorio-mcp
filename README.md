# factorio-mcp

A read-only [MCP](https://modelcontextprotocol.io) server for Factorio 2.1. It lets an AI assistant
answer questions about a running game from live data: server and player info, prototype reference,
and machine diagnostics.

It has two parts:

- `mod/factorio-mcp/` — a Lua mod that exposes a whitelisted, read-only console command
  (`/factorio-mcp <subcommand> <json>`) and answers with a single line of JSON.
- `server/` — a Python service that keeps one persistent RCON connection to the game and serves
  MCP tools over Streamable HTTP.

The mod never changes the world, and does no work while idle.

Status: early skeleton, not usable yet.

## Development

```sh
scripts/test-mod.sh            # pure-Lua mod tests (LUA=lua5.2 to match Factorio)
luacheck mod/factorio-mcp      # lint the mod (.luacheckrc)
ruff check .                   # lint Python (.ruff.toml)
scripts/check-hygiene.sh       # public-repo hygiene gate, also run in CI
```

`scripts/check-hygiene.sh` fails if tracked files or git history contain private network details,
assistant attribution lines, or committed `*.zip` / `*.dat` files. Extra local patterns (for example
real player nicknames or host names) can be listed, one regex per line, in the untracked
`dev/hygiene-patterns.txt`.

## License

MIT
