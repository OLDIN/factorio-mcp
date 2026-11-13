"""Static "read-only by construction" checks.

The mod must not contain any API that writes files, sends network data or changes the world, and the
service may only talk RCON through ``bridge.py``. These are text scans, so they also catch code that
no test executes.
"""

from __future__ import annotations

import re
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
MOD_DIR = ROOT / "mod" / "factorio-mcp"
SERVER_DIR = ROOT / "server" / "factorio_mcp"

FORBIDDEN_LUA = [
    "write_file",
    "send_udp",
    "recv_udp",
    "create_entity",
    ".destroy(",
    ".teleport",
    "tick_paused =",
    "game.speed =",
    "game.print",
    ".insert{",
    "/c ",
    "/sc",
    "remote.add_interface",
]
# The one allowed chat line: the refusal shown to a player who types the command.
ALLOWED_PLAYER_PRINT = ("dispatcher.lua", 'player.print("factorio-mcp: server only")')
PRINT_CALL = re.compile(r"(?<![\w])(?:[\w.]+)[.:]print\s*\(")


def strip_lua_comment(line: str) -> str:
    return line.split("--", 1)[0]


def lua_violations(filename: str, text: str) -> list[str]:
    found = []
    for number, raw in enumerate(text.splitlines(), start=1):
        line = strip_lua_comment(raw)
        for token in FORBIDDEN_LUA:
            if token in line:
                found.append(f"{filename}:{number}: forbidden '{token}'")
        for call in PRINT_CALL.finditer(line):
            allowed = (
                call.group(0).startswith("rcon.print")
                or (filename == ALLOWED_PLAYER_PRINT[0] and ALLOWED_PLAYER_PRINT[1] in line)
            )
            if not allowed:
                found.append(f"{filename}:{number}: forbidden print call '{call.group(0)}'")
    return found


def exec_violations(filename: str, text: str) -> list[str]:
    if filename == "bridge.py":
        return []
    return [
        f"{filename}:{number}: RCON .exec( outside bridge.py"
        for number, line in enumerate(text.splitlines(), start=1)
        if ".exec(" in line.split("#", 1)[0]
    ]


def test_mod_has_no_world_changing_or_output_apis():
    violations = []
    for path in sorted(MOD_DIR.rglob("*.lua")):
        violations += lua_violations(path.name, path.read_text(encoding="utf-8"))
    assert violations == []


def test_service_executes_rcon_only_in_bridge():
    violations = []
    for path in sorted(SERVER_DIR.rglob("*.py")):
        violations += exec_violations(path.name, path.read_text(encoding="utf-8"))
    assert violations == []


# The scanners themselves must fail on forbidden code (adversarial check).
@pytest.mark.parametrize(
    "line",
    [
        'helpers.write_file("x.txt", "data")',
        "helpers.send_udp(1234, data)",
        "surface.create_entity{name = 'wooden-chest'}",
        "entity.destroy()",
        "player.teleport({0, 0})",
        "game.tick_paused = true",
        "game.speed = 5",
        "game.print('hi')",
        "inv.insert{name = 'coal'}",
        "local cmd = '/c game.speed = 5'",
        "local cmd = '/sc rcon.print(1)'",
        "remote.add_interface('x', {})",
        "other_player.print('hello')",
    ],
)
def test_lua_scanner_flags_forbidden_code(line):
    assert lua_violations("evil.lua", line), line


def test_lua_scanner_allows_only_the_known_lines():
    assert lua_violations("dispatcher.lua", '    if player then player.print("factorio-mcp: server only") end') == []
    assert lua_violations("hello.lua", "rcon.print(reply)") == []
    # the same player.print anywhere else is refused
    assert lua_violations("other.lua", 'player.print("factorio-mcp: server only")')
    # forbidden words in comments do not count
    assert lua_violations("x.lua", "-- never call helpers.write_file here") == []


def test_exec_scanner_flags_rcon_exec_outside_bridge():
    assert exec_violations("tools.py", "await link.exec(command)")
    assert exec_violations("bridge.py", "await link.exec(command)") == []
