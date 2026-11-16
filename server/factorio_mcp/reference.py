"""Reference data (prototypes) from the game: fetched once per mod-set fingerprint, queried locally."""

from __future__ import annotations

import asyncio
from typing import Any

from .bridge import ModBridge, ModError, normalize_lists, normalize_maps

# Fields whose empty value Factorio encodes as `{}`: they are lists.
_LIST_FIELDS = {
    "recipes": ["categories", "ingredients", "products", "surface_conditions"],
    "machines": ["crafting_categories", "allowed_effects", "resource_categories", "lab_inputs"],
    "items": ["fuel_categories"],
    "technologies": ["prerequisites", "ingredients", "effects"],
}
# Fields that are maps (an empty one may arrive as `[]`).
_MAP_FIELDS = {
    "modules": ["effects"],
    "technologies": ["research_trigger"],
    "planets": ["surface_properties"],
}
KINDS = ("recipes", "machines", "items", "fluids", "modules", "qualities", "technologies", "planets")


class ReferenceCache:
    def __init__(self, bridge: ModBridge) -> None:
        self._bridge = bridge
        self._fingerprint: str | None = None
        self._data: dict[str, list[dict[str, Any]]] = {}
        self._lock = asyncio.Lock()

    async def get(self, kind: str) -> list[dict[str, Any]]:
        if kind not in KINDS:
            raise ValueError(f"unknown reference kind: {kind}")
        async with self._lock:
            hello = self._bridge.last_hello or await self._bridge.refresh_hello()
            if hello.fingerprint != self._fingerprint:
                self._fingerprint = hello.fingerprint
                self._data = {}
            if kind not in self._data:
                self._data[kind] = await self._fetch(kind)
            return self._data[kind]

    async def _fetch(self, kind: str) -> list[dict[str, Any]]:
        items: list[dict[str, Any]] = []
        offset = 0
        while True:
            page = await self._bridge.call(f"proto_{kind}", {"offset": offset})
            normalize_lists(page, [f"items.*.{f}" for f in _LIST_FIELDS.get(kind, [])])
            normalize_maps(page, [f"items.*.{f}" for f in _MAP_FIELDS.get(kind, [])])
            items.extend(page.get("items", []))
            nxt = page.get("next")
            if nxt is None:
                return items
            if not isinstance(nxt, int) or nxt <= offset:
                raise ModError("bad_response", "reference paging did not advance")
            offset = nxt


def lookup(items: list[dict[str, Any]], name: str) -> dict[str, Any] | None:
    return next((i for i in items if i.get("name") == name), None)


def name_matches(item: dict[str, Any], search: str | None) -> bool:
    return search is None or search.lower() in str(item.get("name", "")).lower()


def find_recipes(
    recipes: list[dict[str, Any]],
    machines: list[dict[str, Any]],
    *,
    produces: str | None = None,
    consumes: str | None = None,
    machine: str | None = None,
    search: str | None = None,
) -> list[dict[str, Any]]:
    """Recipes filtered by product, ingredient, a machine that can craft them, and a name search."""
    machine_categories: set[str] | None = None
    if machine is not None:
        found = lookup(machines, machine)
        machine_categories = set(found.get("crafting_categories", [])) if found else set()
    out = []
    for recipe in recipes:
        if produces is not None and not any(p.get("name") == produces for p in recipe.get("products", [])):
            continue
        if consumes is not None and not any(i.get("name") == consumes for i in recipe.get("ingredients", [])):
            continue
        if machine_categories is not None and not machine_categories & set(recipe.get("categories", [])):
            continue
        if not name_matches(recipe, search):
            continue
        out.append(recipe)
    return out


def find_machines(
    machines: list[dict[str, Any]], *, category: str | None = None, search: str | None = None
) -> list[dict[str, Any]]:
    return [
        m
        for m in machines
        if name_matches(m, search)
        and (
            category is None
            or category in m.get("crafting_categories", [])
            or category in m.get("resource_categories", [])
        )
    ]


def paginate(items: list[dict[str, Any]], limit: int, offset: int) -> dict[str, Any]:
    limit = max(1, min(limit, 200))
    offset = max(0, offset)
    chunk = items[offset : offset + limit]
    more = offset + limit < len(items)
    return {"total": len(items), "offset": offset, "items": chunk, "next": offset + limit if more else None}
