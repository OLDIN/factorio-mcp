# Measurements

## Environment

Tool versions on the development machine (macOS).

| Tool | Version | Notes |
|---|---|---|
| Factorio (game and API docs) | 2.1.24 | runtime API reference: `runtime-api.json` shipped with the game |
| Lua | 5.5.1 | local interpreter; Factorio embeds Lua 5.2, so tests stay 5.2-compatible and CI runs `lua5.2` |
| luacheck | not installed locally | runs in CI (`lua-check` package) |
| uv | 0.10.0 | `/opt/homebrew/bin/uv` |
| Python | 3.13.5 | service requires >= 3.13 |
| ruff | 0.14.13 | same version as CI |
| Docker | 27.5.1 | |
