from __future__ import annotations

from typing import Any, Literal

from mcp.server.mcpserver.exceptions import ToolError

from .. import reference as ref
from ..bridge import ModBridge
from .registry import ToolSpec


Kind = Literal["recipes", "machines", "items", "fluids", "modules", "qualities", "technologies", "planets"]


def specs(bridge: ModBridge) -> list[ToolSpec]:
    cache = ref.ReferenceCache(bridge)

    def visible_only(items: list[dict[str, Any]], include_hidden: bool) -> list[dict[str, Any]]:
        return items if include_hidden else [i for i in items if not i.get("hidden")]

    def rows(kind: str, page: dict[str, Any], details: bool) -> dict[str, Any]:
        """Lists are brief rows; `details` (or asking for one `name`) gives the full records."""
        convert = ref.BRIEF.get(kind)
        if convert is not None and not details:
            page["items"] = [convert(i) for i in page["items"]]
        return page

    async def listing(
        kind: str, name: str | None, search: str | None, limit: int, offset: int, include_hidden: bool,
        details: bool = False,
    ) -> dict[str, Any]:
        items = await cache.get(kind)
        if name is not None:
            found = ref.lookup(items, name)
            return ref.paginate([found] if found else [], limit, 0)  # one thing: always the full record
        items = [i for i in visible_only(items, include_hidden) if ref.name_matches(i, search)]
        return rows(kind, ref.paginate(items, limit, offset), details)

    async def game_reference(
        kind: Kind,
        name: str | None = None,
        search: str | None = None,
        produces: str | None = None,
        consumes: str | None = None,
        machine: str | None = None,
        category: str | None = None,
        limit: int = 25,
        offset: int = 0,
        include_hidden: bool = False,
        details: bool = False,
    ) -> dict[str, Any]:
        hello = bridge.last_hello
        if hello is not None and f"proto_{kind}" not in hello.commands:
            raise ToolError(f"The game mod on this server does not provide {kind}.")
        if kind == "recipes":
            recipes = await cache.get("recipes")
            if name is not None:
                found = ref.lookup(recipes, name)
                return ref.paginate([found] if found else [], limit, 0)  # one thing: always the full record
            machines = await cache.get("machines") if machine is not None else []
            found_all = ref.find_recipes(
                visible_only(recipes, include_hidden), machines,
                produces=produces, consumes=consumes, machine=machine, search=search,
            )
            return rows("recipes", ref.paginate(found_all, limit, offset), details)
        if kind == "machines":
            machines = await cache.get("machines")
            if name is not None:
                found = ref.lookup(machines, name)
                return ref.paginate([found] if found else [], limit, 0)
            found_all = ref.find_machines(machines, category=category, search=search)
            return rows("machines", ref.paginate(found_all, limit, offset), details)
        if kind == "modules":
            return await listing("modules", name, search, limit, offset, True)
        if kind == "qualities":
            return await listing("qualities", name, None, 50, 0, False)
        if kind == "planets":
            return await listing("planets", name, None, 200, 0, True, details)
        return await listing(kind, name, search, limit, offset, include_hidden, details)

    return [
        ToolSpec(
            "game_reference",
            "proto_recipes",
            "Game data of this server, mods included, by kind: recipes (ingredients, products, time, "
            "categories, surface conditions; filter by produces=, consumes=, machine=), machines (crafting "
            "speed, module slots, allowed effects, energy; category=), items (stack size, fuel, spoil result), "
            "fluids, modules (effects), qualities, technologies (prerequisites, cost, effects), planets "
            "(gravity, pressure, solar power). Lists are short rows; name= (or details=true) gives full "
            "records. Hidden entries (e.g. recycling) only with include_hidden.",
            game_reference,
        )
    ]
