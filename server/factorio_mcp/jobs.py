"""Runs a tick-split job in the mod: start, poll until done, collect every page."""

from __future__ import annotations

import asyncio
import logging
import time
from typing import Any

from .bridge import GameUnavailable, ModBridge, ModError

_LOGGER = logging.getLogger(__name__)

# How long a tool call waits for a job before answering "still running" (clients give up on a
# silent HTTP call after about a minute; the job itself keeps running in the game).
SOFT_TIMEOUT = 30.0


class JobRunner:
    def __init__(self, bridge: ModBridge) -> None:
        self._bridge = bridge

    async def run(
        self,
        kind: str,
        params: dict[str, Any],
        timeout: float = 120.0,
        poll: float = 0.5,
        wait: float | None = None,
        job_id: int | None = None,
    ) -> dict[str, Any]:
        """Start a job (or continue `job_id`) and collect its result.

        With `wait`, a job that is still running after that many seconds is not cancelled: the
        result is {"status": "running", "job_id", "progress"} and the caller asks again with
        `job_id`. Without `wait`, `timeout` is a hard limit that cancels the job.
        """
        if job_id is None:
            started = await self._bridge.call("job_start", {"kind": kind, "params": params})
            job_id = started["job_id"]
        now = time.monotonic()
        deadline = now + timeout
        soft_deadline = now + wait if wait is not None else None
        try:
            return await self._collect(job_id, deadline, poll, soft_deadline)
        except (asyncio.CancelledError, TimeoutError):
            await self._cancel(job_id)
            raise

    async def _collect(
        self, job_id: int, deadline: float, poll: float, soft_deadline: float | None = None
    ) -> dict[str, Any]:
        merged: dict[str, Any] | None = None
        offset = 0
        while True:
            if time.monotonic() > deadline:
                await self._cancel(job_id)
                raise ModError("job_timeout", "the game did not finish the job in time")
            page = await self._bridge.call("job_result", {"job_id": job_id, "offset": offset})
            state = page.get("state")
            if state == "running":
                if soft_deadline is not None and time.monotonic() > soft_deadline:
                    return {
                        "status": "running",
                        "job_id": job_id,
                        "progress": page.get("progress"),
                        "message": f"Still scanning the map. Call this tool again with job_id={job_id} for the result.",
                    }
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
