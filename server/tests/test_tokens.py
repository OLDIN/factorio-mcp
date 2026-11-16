from __future__ import annotations

import hashlib
import os

from factorio_mcp.tokens import Identity, TokenStore


def _entry(name: str, nick: str, token: str) -> str:
    digest = hashlib.sha256(token.encode()).hexdigest()
    return f'[[token]]\nname = "{name}"\nnick = "{nick}"\nsha256 = "{digest}"\n'


def _touch(path, offset: int) -> None:
    st = path.stat()
    os.utime(path, ns=(st.st_atime_ns, st.st_mtime_ns + offset * 10**9))


def test_authenticate_accepts_known_token(tmp_path):
    f = tmp_path / "tokens.toml"
    f.write_text(_entry("alice", "AliceNick", "tok-a") + _entry("bob", "BobNick", "tok-b"))
    store = TokenStore(f)
    assert store.authenticate("tok-b") == Identity("bob", "BobNick")


def test_authenticate_rejects_unknown_and_empty(tmp_path):
    f = tmp_path / "tokens.toml"
    f.write_text(_entry("alice", "AliceNick", "tok-a"))
    store = TokenStore(f)
    assert store.authenticate("nope") is None
    assert store.authenticate("") is None


def test_revoked_after_file_change(tmp_path):
    f = tmp_path / "tokens.toml"
    f.write_text(_entry("alice", "AliceNick", "tok-a"))
    store = TokenStore(f)
    assert store.authenticate("tok-a") is not None
    f.write_text("")
    _touch(f, 5)
    assert store.authenticate("tok-a") is None


def test_bad_file_keeps_last_good(tmp_path, caplog):
    f = tmp_path / "tokens.toml"
    f.write_text(_entry("alice", "AliceNick", "tok-a"))
    store = TokenStore(f)
    f.write_text("this is [not toml")
    _touch(f, 5)
    assert store.authenticate("tok-a") == Identity("alice", "AliceNick")
    assert "not toml" not in caplog.text


def test_bad_file_at_start_rejects_everyone(tmp_path):
    f = tmp_path / "tokens.toml"
    f.write_text("garbage [")
    assert TokenStore(f).authenticate("anything") is None


def test_missing_file_rejects_everyone(tmp_path):
    assert TokenStore(tmp_path / "absent.toml").authenticate("x") is None


def test_deleted_file_revokes_everyone(tmp_path):
    f = tmp_path / "tokens.toml"
    f.write_text(_entry("alice", "AliceNick", "tok-a"))
    store = TokenStore(f)
    assert store.authenticate("tok-a") is not None
    f.unlink()
    assert store.authenticate("tok-a") is None
