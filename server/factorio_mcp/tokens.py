"""Bearer-token store: a TOML file holding only sha256 hashes of tokens.

A missing file revokes everyone. A file that exists but does not parse keeps the last good state
(a typo mid-edit must not lock people out), so revocation needs a valid file.
"""

from __future__ import annotations

import hashlib
import hmac
import logging
import tomllib
from dataclasses import dataclass
from pathlib import Path

_LOGGER = logging.getLogger(__name__)


@dataclass(frozen=True)
class Identity:
    name: str
    nick: str


class TokenStore:
    def __init__(self, path: Path) -> None:
        self._path = Path(path)
        self._mtime_ns: int | None = None
        self._entries: list[tuple[bytes, Identity]] = []
        self._reload(force=True)

    def _reload(self, force: bool = False) -> None:
        try:
            mtime_ns = self._path.stat().st_mtime_ns
        except OSError:
            # Fail closed: a deleted or unreadable file revokes everyone.
            if force or self._mtime_ns is not None:
                _LOGGER.warning("tokens file is not readable; rejecting all tokens")
            self._mtime_ns = None
            self._entries = []
            return
        if not force and mtime_ns == self._mtime_ns:
            return
        self._mtime_ns = mtime_ns  # do not re-warn about the same bad file on every request
        try:
            data = tomllib.loads(self._path.read_text())
            entries = [
                (
                    bytes.fromhex(str(row["sha256"])),
                    Identity(name=str(row["name"]), nick=str(row["nick"])),
                )
                for row in data.get("token", [])
            ]
        except (OSError, ValueError, KeyError, TypeError):
            # No file content in the message: it holds secrets' hashes.
            _LOGGER.warning("tokens file is invalid; keeping last good state")
            return
        self._entries = entries

    def authenticate(self, token: str) -> Identity | None:
        self._reload()
        if not token:
            return None
        digest = hashlib.sha256(token.encode()).digest()
        found: Identity | None = None
        for stored, identity in self._entries:  # no early exit
            if hmac.compare_digest(stored, digest):
                found = identity
        return found
