from __future__ import annotations

from typing import Any

from .. import reference as ref
from ..bridge import ModBridge
from .registry import ToolSpec


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

    async def reference_recipes(
        name: str | None = None,
        produces: str | None = None,
        consumes: str | None = None,
        machine: str | None = None,
        search: str | None = None,
        limit: int = 25,
        offset: int = 0,
        include_hidden: bool = False,
        details: bool = False,
    ) -> dict[str, Any]:
        recipes = await cache.get("recipes")
        if name is not None:
            found = ref.lookup(recipes, name)
            return ref.paginate([found] if found else [], limit, 0)
        machines = await cache.get("machines") if machine is not None else []
        found_all = ref.find_recipes(
            visible_only(recipes, include_hidden),
            machines,
            produces=produces,
            consumes=consumes,
            machine=machine,
            search=search,
        )
        return rows("recipes", ref.paginate(found_all, limit, offset), details)

    async def reference_machines(
        name: str | None = None,
        category: str | None = None,
        search: str | None = None,
        limit: int = 25,
        offset: int = 0,
        details: bool = False,
    ) -> dict[str, Any]:
        machines = await cache.get("machines")
        if name is not None:
            found = ref.lookup(machines, name)
            return ref.paginate([found] if found else [], limit, 0)
        found_all = ref.find_machines(machines, category=category, search=search)
        return rows("machines", ref.paginate(found_all, limit, offset), details)

    async def reference_items(
        name: str | None = None, search: str | None = None, limit: int = 25, offset: int = 0,
        include_hidden: bool = False, details: bool = False,
    ) -> dict[str, Any]:
        return await listing("items", name, search, limit, offset, include_hidden, details)

    async def reference_fluids(
        name: str | None = None, search: str | None = None, limit: int = 25, offset: int = 0,
        include_hidden: bool = False, details: bool = False,
    ) -> dict[str, Any]:
        return await listing("fluids", name, search, limit, offset, include_hidden, details)

    async def reference_modules(
        name: str | None = None, search: str | None = None, limit: int = 25, offset: int = 0
    ) -> dict[str, Any]:
        return await listing("modules", name, search, limit, offset, True)

    async def reference_qualities(name: str | None = None) -> dict[str, Any]:
        return await listing("qualities", name, None, 50, 0, False)

    async def reference_technologies(
        name: str | None = None, search: str | None = None, limit: int = 25, offset: int = 0,
        include_hidden: bool = False, details: bool = False,
    ) -> dict[str, Any]:
        return await listing("technologies", name, search, limit, offset, include_hidden, details)

    async def reference_planets(name: str | None = None, details: bool = False) -> dict[str, Any]:
        return await listing("planets", name, None, 200, 0, True, details)

    def spec(fn, requires: str, description: str) -> ToolSpec:
        return ToolSpec(fn.__name__, requires, description, fn)

    return [
        spec(reference_recipes, "proto_recipes",
             "Game recipes (this server's mods included): ingredients, products, time, categories, "
             "surface conditions. Filter by name, produced item, consumed item, a machine that can "
             "craft it, or a name search. Lists are short rows; pass name=<recipe> (or details=true) for the "
             "full record. Hidden recipes (e.g. recycling) are skipped unless include_hidden."),
        spec(reference_machines, "proto_machines",
             "Crafting machines, mining drills and labs: crafting speed, module slots, allowed effects, "
             "energy use, categories, health."),
        spec(reference_items, "proto_items", "Items: stack size, fuel value, place result, spoil result."),
        spec(reference_fluids, "proto_fluids", "Fluids: temperatures, fuel value, heat capacity."),
        spec(reference_modules, "proto_modules", "Modules: category, tier and effects."),
        spec(reference_qualities, "proto_qualities", "Quality levels and their multipliers."),
        spec(reference_technologies, "proto_technologies",
             "Technologies: prerequisites, science pack cost, unit count, effects."),
        spec(reference_planets, "proto_planets",
             "Planets and space locations of this server, including modded ones, with surface properties "
             "(gravity, pressure, solar power...)."),
    ]
