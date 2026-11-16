from __future__ import annotations

import pytest

from factorio_mcp.commands import ALLOWED_SUBS, build_command


def test_build_command_never_starts_with_c():
    for sub in ALLOWED_SUBS:
        cmd = build_command(sub)
        assert cmd.startswith(f"/factorio-mcp {sub} ")
        assert not cmd.startswith("/c")
        assert not cmd.startswith("/sc")


def test_disallowed_subcommands_raise_value_error():
    for invalid in ("c", "sc", "eval", "x\n/c", "hello\n/c", "unknown"):
        with pytest.raises(ValueError):
            build_command(invalid)


def test_surface_with_newline_stays_one_line():
    cmd = build_command("server_info", {"surface": "a\nb/c"})
    assert "\n" not in cmd
    assert r"\n" in cmd  # JSON escaped


def test_args_exceeding_1000_bytes_raise():
    large_args = {"data": "x" * 1050}
    with pytest.raises(ValueError, match="1000 bytes"):
        build_command("hello", large_args)
