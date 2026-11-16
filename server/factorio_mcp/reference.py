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


# --- Brief rows -----------------------------------------------------------------------------
# Lists and searches answer with short rows (an LLM reads every character it receives); the full
# record of one thing comes with `name=`. A row keeps what is needed to pick the right thing.

_MAX_ENTRIES = 8  # ingredients/products/effects shown per row; the rest is counted


def _num(value: Any) -> str:
    return f"{value:g}" if isinstance(value, (int, float)) else str(value)


def _entry(entry: dict[str, Any]) -> str:
    """'2 iron-plate', '1-3 stone', '0.5 coal (10%)'."""
    if "amount" in entry:
        amount = _num(entry["amount"])
    else:
        amount = f"{_num(entry.get('amount_min', '?'))}-{_num(entry.get('amount_max', '?'))}"
    text = f"{amount} {entry.get('name', '?')}"
    chance = entry.get("probability", entry.get("independent_probability"))
    if isinstance(chance, (int, float)) and chance < 1:
        text += f" ({chance * 100:g}%)"
    return text


def _short(items: list[str]) -> list[str]:
    if len(items) <= _MAX_ENTRIES:
        return items
    return [*items[:_MAX_ENTRIES], f"+{len(items) - _MAX_ENTRIES} more"]


def brief_recipe(r: dict[str, Any]) -> dict[str, Any]:
    return {
        "name": r["name"],
        "categories": r.get("categories", []),
        "time": r.get("energy"),
        "in": _short([_entry(e) for e in r.get("ingredients", [])]),
        "out": _short([_entry(e) for e in r.get("products", [])]),
    }


def brief_machine(m: dict[str, Any]) -> dict[str, Any]:
    return {
        "name": m["name"],
        "categories": [*m.get("crafting_categories", []), *m.get("resource_categories", [])],
        "crafting_speed": m.get("crafting_speed"),
        "module_slots": m.get("module_slots"),
        "energy_usage": m.get("energy_usage"),
    }


def brief_item(i: dict[str, Any]) -> dict[str, Any]:
    row = {"name": i["name"], "type": i.get("type"), "stack_size": i.get("stack_size")}
    if i.get("fuel_value"):
        row["fuel_value"] = i["fuel_value"]
    return row


def brief_fluid(f: dict[str, Any]) -> dict[str, Any]:
    return {"name": f["name"], "default_temperature": f.get("default_temperature"),
            "max_temperature": f.get("max_temperature")}


def brief_technology(t: dict[str, Any]) -> dict[str, Any]:
    cost = ", ".join(_entry(e) for e in t.get("ingredients", []))
    unlocks = [e["recipe"] for e in t.get("effects", []) if e.get("type") == "unlock-recipe" and "recipe" in e]
    other = [e["type"] for e in t.get("effects", []) if e.get("type") != "unlock-recipe" and "type" in e]
    row = {
        "name": t["name"],
        "prerequisites": t.get("prerequisites", []),
        "cost": f"{_num(t.get('unit_count'))} x [{cost}]" if cost else "trigger",
        "unlocks": _short(unlocks),
    }
    if other:
        row["other_effects"] = _short(sorted(set(other)))
    if t.get("max_level") and t["max_level"] > 1:
        row["max_level"] = t["max_level"]
    return row


_KEY_PLANET_PROPERTIES = ("gravity", "pressure", "solar-power", "temperature", "magnetic-field", "day-night-cycle")


def brief_planet(p: dict[str, Any]) -> dict[str, Any]:
    props = p.get("surface_properties", {})
    return {
        "name": p["name"],
        "type": p.get("type"),
        "distance": p.get("distance"),
        **{k: props[k] for k in _KEY_PLANET_PROPERTIES if k in props},
    }


BRIEF = {
    "recipes": brief_recipe, "machines": brief_machine, "items": brief_item, "fluids": brief_fluid,
    "technologies": brief_technology, "planets": brief_planet,
}
