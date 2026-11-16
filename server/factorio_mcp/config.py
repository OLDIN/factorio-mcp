"""Service settings from environment variables. The RCON password never appears in repr."""

from __future__ import annotations

from collections.abc import Mapping
from dataclasses import dataclass, field
from pathlib import Path


@dataclass(frozen=True)
class Settings:
    host: str = "127.0.0.1"
    port: int = 8787
    rcon_host: str = "127.0.0.1"
    rcon_port: int = 27015
    rcon_password: str = field(default="", repr=False)
    tokens_file: Path = Path("tokens.toml")
    allowed_hosts: tuple[str, ...] = ()
    log_level: str = "INFO"

    def __repr__(self) -> str:
        return (
            f"Settings(host={self.host!r}, port={self.port}, rcon_host={self.rcon_host!r}, "
            f"rcon_port={self.rcon_port}, rcon_password='***', tokens_file={self.tokens_file}, "
            f"allowed_hosts={self.allowed_hosts!r}, log_level={self.log_level!r})"
        )

    @classmethod
    def from_env(cls, env: Mapping[str, str]) -> Settings:
        password = env.get("FACTORIO_MCP_RCON_PASSWORD", "")
        password_file = env.get("FACTORIO_MCP_RCON_PASSWORD_FILE")
        if not password and password_file:
            try:
                password = Path(password_file).read_text().strip()
            except OSError as err:
                raise ValueError(f"cannot read RCON password file: {err.strerror}") from None
        if not password:
            raise ValueError(
                "RCON password missing: set FACTORIO_MCP_RCON_PASSWORD or "
                "FACTORIO_MCP_RCON_PASSWORD_FILE"
            )
        tokens_file = env.get("FACTORIO_MCP_TOKENS_FILE")
        if not tokens_file:
            raise ValueError("FACTORIO_MCP_TOKENS_FILE is required (tokens file path)")
        hosts = tuple(h.strip() for h in env.get("FACTORIO_MCP_ALLOWED_HOSTS", "").split(",") if h.strip())
        return cls(
            host=env.get("FACTORIO_MCP_HOST", "127.0.0.1"),
            port=int(env.get("FACTORIO_MCP_PORT", "8787")),
            rcon_host=env.get("FACTORIO_MCP_RCON_HOST", "127.0.0.1"),
            rcon_port=int(env.get("FACTORIO_MCP_RCON_PORT", "27015")),
            rcon_password=password,
            tokens_file=Path(tokens_file),
            allowed_hosts=hosts,
            log_level=env.get("FACTORIO_MCP_LOG_LEVEL", "INFO").upper(),
        )
