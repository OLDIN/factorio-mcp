#!/usr/bin/env python3
"""Helper for scripts/live-job-reload.sh (talks to the dev server on 127.0.0.1:27015).

  job-reload-check.py start-and-save   start a tick job, save the game while it runs
  job-reload-check.py finish           after a reload: the job must continue and finish
"""

import asyncio
import logging
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "server"))

from factorio_mcp.bridge import ModBridge  # noqa: E402
from factorio_mcp.rcon import RconLink  # noqa: E402

logging.disable(logging.CRITICAL)


async def connect() -> tuple[RconLink, ModBridge, asyncio.Task]:
    link = RconLink("127.0.0.1", 27015, "dev", retry_delay=0.2)
    task = asyncio.create_task(link.run())
    for _ in range(100):
        if link.alive:
            break
        await asyncio.sleep(0.1)
    return link, ModBridge(link), task


async def start_and_save() -> int:
    link, bridge, task = await connect()
    started = await bridge.call("job_start", {"kind": "machines_overview", "mode": "ticks"})
    status = await bridge.call("job_status")
    running = [j for j in status["jobs"] if j["state"] == "running"]
    if not running or not status["tick_handler_registered"]:
        print("FAIL: job is not running with a tick handler right after start")
        return 1
    print(await link.exec("/server-save", timeout=60))
    status = await bridge.call("job_status")
    mine = next((j for j in status["jobs"] if j["id"] == started["job_id"]), None)
    progress = mine["progress"] if mine else None
    print(f"saved while running: job {started['job_id']} progress={progress}")
    if mine is None or mine["state"] != "running" or progress > 0.5:
        print("FAIL: the job is not still early in its run right after the save; nothing was tested")
        return 1
    task.cancel()
    return 0


async def finish() -> int:
    link, bridge, task = await connect()
    status = await bridge.call("job_status")
    print("after reload:", status)
    if not status["tick_handler_registered"] or not any(j["state"] == "running" for j in status["jobs"]):
        print("FAIL: the running job or its tick handler was not restored by on_load")
        return 1
    job_id = next(j["id"] for j in status["jobs"] if j["state"] == "running")
    for _ in range(3000):
        page = await bridge.call("job_result", {"job_id": job_id})
        if page["state"] != "running":
            print("done:", page.get("summary"))
            after = await bridge.call("job_status")
            if after["tick_handler_registered"]:
                print("FAIL: tick handler still registered after the job finished")
                return 1
            task.cancel()
            return 0
        await asyncio.sleep(0.3)
    print("FAIL: the job did not finish after the reload")
    return 1


if __name__ == "__main__":
    sys.exit(asyncio.run({"start-and-save": start_and_save, "finish": finish}[sys.argv[1]]()))
