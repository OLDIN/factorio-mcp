"""Runs a tick-split job in the mod: start, poll until done, collect every page."""

from __future__ import annotations

import asyncio
import logging
import time
from typing import Any

from .bridge import GameUnavailable, ModBridge, ModError

_LOGGER = logging.getLogger(__name__)


class JobRunner:
    def __init__(self, bridge: ModBridge) -> None:
        self._bridge = bridge

    async def run(
        self, kind: str, params: dict[str, Any], timeout: float = 120.0, poll: float = 0.5
    ) -> dict[str, Any]:
        started = await self._bridge.call("job_start", {"kind": kind, "params": params})
        job_id = started["job_id"]
        deadline = time.monotonic() + timeout
        try:
            return await self._collect(job_id, deadline, poll)
        except (asyncio.CancelledError, TimeoutError):
            await self._cancel(job_id)
            raise

    async def _collect(self, job_id: int, deadline: float, poll: float) -> dict[str, Any]:
        merged: dict[str, Any] | None = None
        offset = 0
        while True:
            if time.monotonic() > deadline:
                await self._cancel(job_id)
                raise ModError("job_timeout", "the game did not finish the job in time")
            page = await self._bridge.call("job_result", {"job_id": job_id, "offset": offset})
            state = page.get("state")
            if state == "running":
                await asyncio.sleep(poll)
                continue
            if state == "cancelled":
                raise ModError("job_cancelled", "the job was cancelled")
            if state != "done":
                raise ModError("bad_response", "unexpected job state")
            nxt = page.pop("next", None)
            page.pop("state", None)
            if merged is None:
                merged = page
            else:
                for key, value in page.items():
                    if isinstance(value, list) and isinstance(merged.get(key), list):
                        merged[key].extend(value)
            if nxt is None:
                return merged
            if not isinstance(nxt, int) or nxt <= offset:
                raise ModError("bad_response", "job paging did not advance")
            offset = nxt

    async def _cancel(self, job_id: int) -> None:
        try:
            await self._bridge.call("job_cancel", {"job_id": job_id})
        except (GameUnavailable, ModError):
            _LOGGER.warning("could not cancel job %s", job_id)
