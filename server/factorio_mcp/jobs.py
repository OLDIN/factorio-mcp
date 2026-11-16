"""Runs a tick-split job in the mod: start, poll until done, collect every page."""

from __future__ import annotations

import asyncio
import logging
import secrets
import time
from typing import Any

from .bridge import GameUnavailable, ModBridge, ModError

_LOGGER = logging.getLogger(__name__)

# How long a tool call waits for a job before answering "still running" (clients give up on a
# silent HTTP call after about a minute; the job itself keeps running in the game).
SOFT_TIMEOUT = 30.0
# A scan that was left "running" is dropped (and cancelled in the game) after this long, and one
# person may have this many open at once. The mod bounds the same things on its side.
HANDLE_TTL = 600.0
MAX_HANDLES_PER_OWNER = 2


class JobHandles:
    """Opaque, unguessable handles for open scans: who started them, what kind, until when."""

    def __init__(self) -> None:
        self._items: dict[str, tuple[int, str, str, float]] = {}

    def create(self, mod_job_id: int, kind: str, owner: str) -> str:
        handle = secrets.token_urlsafe(9)
        self._items[handle] = (mod_job_id, kind, owner, time.monotonic() + HANDLE_TTL)
        return handle

    def resolve(self, handle: str, kind: str, owner: str) -> int | None:
        item = self._items.get(handle)
        if item is None or item[1] != kind or item[2] != owner or item[3] < time.monotonic():
            return None  # unknown, someone else's, another kind or expired: all look the same
        return item[0]

    def drop(self, handle: str) -> None:
        self._items.pop(handle, None)

    def open_for(self, owner: str) -> int:
        return sum(1 for item in self._items.values() if item[2] == owner)

    def take_expired(self) -> list[int]:
        now = time.monotonic()
        gone = [h for h, item in self._items.items() if item[3] < now]
        return [self._items.pop(h)[0] for h in gone]


def user_message(err: ModError) -> str | None:
    """A plain-language message for errors the person asking can act on, else None."""
    if err.code == "job_not_found":
        return "That scan is gone (already collected, expired or cancelled). Start a new one without job_id."
    if err.code == "too_many_jobs":
        return "Too many scans are open or running right now. Resume one with its job_id or wait a bit."
    return None


class JobRunner:
    def __init__(self, bridge: ModBridge) -> None:
        self._bridge = bridge
        self._handles = JobHandles()

    async def run(
        self,
        kind: str,
        params: dict[str, Any],
        owner: str,
        timeout: float = 120.0,
        poll: float = 0.5,
        wait: float | None = None,
        handle: str | None = None,
    ) -> dict[str, Any]:
        """Start a scan (or continue the one named by `handle`) and collect its result.

        With `wait`, a scan that is still running after that many seconds is not cancelled: the
        answer is {"status": "running", "job_id": <handle>, "progress"} and the caller asks again
        with that handle. Without `wait`, `timeout` is a hard limit that cancels the scan.
        A handle only works for the person who started it, for the same kind of scan.
        """
        for expired in self._handles.take_expired():
            await self._cancel(expired)
        if handle is None:
            if self._handles.open_for(owner) >= MAX_HANDLES_PER_OWNER:
                raise ModError("too_many_jobs", "too many open scans")
            started = await self._bridge.call("job_start", {"kind": kind, "params": params})
            mod_job_id = started["job_id"]
            handle = self._handles.create(mod_job_id, kind, owner)
        else:
            resolved = self._handles.resolve(handle, kind, owner)
            if resolved is None:
                raise ModError("job_not_found", "no such scan")
            mod_job_id = resolved
        now = time.monotonic()
        deadline = now + timeout
        soft_deadline = now + wait if wait is not None else None
        try:
            result = await self._collect(mod_job_id, deadline, poll, soft_deadline, handle)
        except (asyncio.CancelledError, TimeoutError):
            self._handles.drop(handle)  # the caller left: stop the scan in the game too
            await self._cancel(mod_job_id)
            raise
        except BaseException:
            self._handles.drop(handle)
            raise
        if result.get("status") != "running":
            self._handles.drop(handle)
        return result

    async def _collect(
        self,
        job_id: int,
        deadline: float,
        poll: float,
        soft_deadline: float | None = None,
        handle: str | None = None,
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
                        "job_id": handle,
                        "progress": page.get("progress"),
                        "message": f"Still scanning the map. Call this tool again with job_id={handle} for the result.",
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
