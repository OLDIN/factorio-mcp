from __future__ import annotations

import asyncio
import logging
import os

import uvicorn

from .app import create_app
from .bridge import ModBridge
from .config import Settings
from .rcon import RconLink
from .tokens import TokenStore


def uvicorn_config(app, settings: Settings) -> uvicorn.Config:
    # Access log off: request lines can carry a mistaken ?token=...; our audit log replaces it.
    # `access_log=False` alone is not enough (uvicorn decides per connection via hasHandlers()),
    # so the logger is disabled outright as well.
    config = uvicorn.Config(
        app, host=settings.host, port=settings.port, log_level=settings.log_level.lower(), access_log=False
    )
    # After construction: uvicorn's dictConfig re-enables its loggers.
    logging.getLogger("uvicorn.access").disabled = True
    return config


async def main() -> None:
    settings = Settings.from_env(os.environ)
    logging.basicConfig(level=settings.log_level, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
    link = RconLink(settings.rcon_host, settings.rcon_port, settings.rcon_password)
    bridge = ModBridge(link)
    app = create_app(settings, bridge, TokenStore(settings.tokens_file))
    rcon_task = asyncio.create_task(link.run())
    try:
        await uvicorn.Server(uvicorn_config(app, settings)).serve()
    finally:
        rcon_task.cancel()


if __name__ == "__main__":
    asyncio.run(main())
