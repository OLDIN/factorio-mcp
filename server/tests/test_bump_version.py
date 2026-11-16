from __future__ import annotations

import importlib.util
import json
import pathlib
import re

import pytest

ROOT = pathlib.Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("bump_version", ROOT / "scripts" / "bump_version.py")
bump = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bump)


def test_bump_parts():
    assert bump.bump_version("0.1.0", "patch") == "0.1.1"
    assert bump.bump_version("0.1.9", "minor") == "0.2.0"
    assert bump.bump_version("0.9.9", "major") == "1.0.0"


def test_bump_rejects_bad_input():
    with pytest.raises(ValueError):
        bump.bump_version("1.2", "patch")
    with pytest.raises(ValueError):
        bump.bump_version("1.2.3", "huge")


def test_changelog_entry_is_factorio_format():
    entry = bump.factorio_changelog_entry("0.2.0", ["feat: new tool", "fix: crash", "docs: readme"])
    lines = entry.splitlines()
    assert lines[0] == "-" * 99
    assert lines[1] == "Version: 0.2.0"
    assert re.fullmatch(r"Date: \d{4}-\d{2}-\d{2}", lines[2])
    assert "  Features:" in lines and "  Bugfixes:" in lines and "  Changes:" in lines
    assert "    - fix: crash" in lines


def test_changelog_entry_without_commits():
    assert "Maintenance release." in bump.factorio_changelog_entry("0.1.1", [])


def test_all_version_files_agree():
    mod = json.loads((ROOT / "mod/factorio-mcp/info.json").read_text())["version"]
    assert f'version = "{mod}"' in (ROOT / "server/pyproject.toml").read_text()
    assert f'__version__ = "{mod}"' in (ROOT / "server/factorio_mcp/__init__.py").read_text()
    assert f"Version: {mod}" in (ROOT / "mod/factorio-mcp/changelog.txt").read_text()
