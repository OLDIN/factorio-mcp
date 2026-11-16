from __future__ import annotations

import pytest

from factorio_mcp.config import Settings


def test_settings_from_env_defaults(tmp_path):
    tokens_file = tmp_path / "tokens.toml"
    tokens_file.write_text("")
    env = {
        "FACTORIO_MCP_RCON_PASSWORD": "supersecretpassword",
        "FACTORIO_MCP_TOKENS_FILE": str(tokens_file),
    }
    settings = Settings.from_env(env)
    assert settings.host == "127.0.0.1"
    assert settings.port == 8787
    assert settings.rcon_host == "127.0.0.1"
    assert settings.rcon_port == 27015
    assert settings.rcon_password == "supersecretpassword"
    assert settings.tokens_file == tokens_file
    assert settings.log_level == "INFO"


def test_settings_password_from_file(tmp_path):
    pw_file = tmp_path / "rconpw"
    pw_file.write_text("filepassword\n")
    tokens_file = tmp_path / "tokens.toml"
    tokens_file.write_text("")
    env = {
        "FACTORIO_MCP_RCON_PASSWORD_FILE": str(pw_file),
        "FACTORIO_MCP_TOKENS_FILE": str(tokens_file),
    }
    settings = Settings.from_env(env)
    assert settings.rcon_password == "filepassword"


def test_missing_password_raises(tmp_path):
    tokens_file = tmp_path / "tokens.toml"
    tokens_file.write_text("")
    env = {"FACTORIO_MCP_TOKENS_FILE": str(tokens_file)}
    with pytest.raises(ValueError, match="password"):
        Settings.from_env(env)


def test_missing_tokens_file_raises():
    env = {"FACTORIO_MCP_RCON_PASSWORD": "dev"}
    with pytest.raises(ValueError, match="tokens"):
        Settings.from_env(env)


def test_settings_repr_hides_password(tmp_path):
    tokens_file = tmp_path / "tokens.toml"
    tokens_file.write_text("")
    env = {
        "FACTORIO_MCP_RCON_PASSWORD": "topsecretpassword",
        "FACTORIO_MCP_TOKENS_FILE": str(tokens_file),
    }
    settings = Settings.from_env(env)
    r = repr(settings)
    assert "topsecretpassword" not in r
    assert "***" in r


def test_allowed_hosts_parsing(tmp_path):
    tokens_file = tmp_path / "tokens.toml"
    tokens_file.write_text("")
    env = {
        "FACTORIO_MCP_RCON_PASSWORD": "dev",
        "FACTORIO_MCP_TOKENS_FILE": str(tokens_file),
        "FACTORIO_MCP_ALLOWED_HOSTS": "127.0.0.1, localhost, example.org",
    }
    settings = Settings.from_env(env)
    assert settings.allowed_hosts == ("127.0.0.1", "localhost", "example.org")
