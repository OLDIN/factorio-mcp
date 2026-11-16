from __future__ import annotations

from factorio_mcp import reference as ref

MACHINES = [
    {"name": "assembling-machine-2", "crafting_categories": ["crafting", "crafting-with-fluid"], "resource_categories": []},
    {"name": "chemical-plant", "crafting_categories": ["chemistry"], "resource_categories": []},
    {"name": "electric-mining-drill", "crafting_categories": [], "resource_categories": ["basic-solid"]},
]
RECIPES = [
    {"name": "iron-gear-wheel", "categories": ["crafting"], "hidden": False,
     "ingredients": [{"type": "item", "name": "iron-plate", "amount": 2}],
     "products": [{"type": "item", "name": "iron-gear-wheel", "amount": 1}]},
    {"name": "plastic-bar", "categories": ["chemistry"], "hidden": False,
     "ingredients": [{"type": "item", "name": "coal", "amount": 1}, {"type": "fluid", "name": "petroleum-gas", "amount": 20}],
     "products": [{"type": "item", "name": "plastic-bar", "amount": 2}]},
]


def test_find_recipes_by_product_and_machine():
    assert [r["name"] for r in ref.find_recipes(RECIPES, MACHINES, produces="plastic-bar")] == ["plastic-bar"]
    assert [r["name"] for r in ref.find_recipes(RECIPES, MACHINES, machine="assembling-machine-2")] == ["iron-gear-wheel"]
    assert [r["name"] for r in ref.find_recipes(RECIPES, MACHINES, machine="chemical-plant")] == ["plastic-bar"]
    assert ref.find_recipes(RECIPES, MACHINES, machine="electric-mining-drill") == []
    assert ref.find_recipes(RECIPES, MACHINES, machine="no-such-machine") == []


def test_find_recipes_by_ingredient_and_search_is_case_insensitive():
    assert [r["name"] for r in ref.find_recipes(RECIPES, MACHINES, consumes="coal")] == ["plastic-bar"]
    assert [r["name"] for r in ref.find_recipes(RECIPES, MACHINES, search="GEAR")] == ["iron-gear-wheel"]


def test_find_machines_by_category():
    assert [m["name"] for m in ref.find_machines(MACHINES, category="basic-solid")] == ["electric-mining-drill"]
    assert [m["name"] for m in ref.find_machines(MACHINES, category="chemistry")] == ["chemical-plant"]


def test_lookup():
    assert ref.lookup(RECIPES, "plastic-bar")["name"] == "plastic-bar"
    assert ref.lookup(RECIPES, "nope") is None


def test_paginate():
    items = [{"name": str(i)} for i in range(5)]
    page = ref.paginate(items, 2, 0)
    assert page["total"] == 5 and len(page["items"]) == 2 and page["next"] == 2
    last = ref.paginate(items, 2, 4)
    assert len(last["items"]) == 1 and last["next"] is None
