from __future__ import annotations

import json

from stack_fixture import hello_reply

from factorio_mcp import reference as ref
from factorio_mcp.commands import build_command

SCRAP = {"name": "spaceship-scrap-recycling", "categories": ["recycling"], "energy": 0.2, "enabled": False,
         "hidden": False, "maximum_productivity": 3, "surface_conditions": [],
         "ingredients": [{"type": "item", "name": "spaceship-scrap", "amount": 1}],
         "products": [{"type": "item", "name": f"thing-{i}", "amount": 1, "independent_probability": 0.01 * (i + 1),
                       "affected_by_quality": True} for i in range(30)]}
GEAR = {"name": "iron-gear-wheel", "categories": ["crafting"], "energy": 0.5, "hidden": False,
        "ingredients": [{"type": "item", "name": "iron-plate", "amount": 2}],
        "products": [{"type": "item", "name": "iron-gear-wheel", "amount": 1, "independent_probability": 1}]}
TECH = {"name": "advanced-asteroid-processing", "enabled": True, "hidden": False, "upgrade": False, "level": 1,
        "max_level": 1, "prerequisites": ["a", "b"], "unit_count": 2000, "unit_energy": 3600, "research_trigger": {},
        "ingredients": [{"name": "automation-science-pack", "amount": 1}, {"name": "logistic-science-pack", "amount": 1}],
        "effects": [{"hidden": False, "type": "unlock-recipe", "recipe": "crusher"},
                    {"hidden": False, "type": "ammo-damage", "ammo_category": "x", "modifier": 0.1}]}


def test_recipe_row_is_short_and_readable():
    row = ref.brief_recipe(GEAR)
    assert row == {"name": "iron-gear-wheel", "categories": ["crafting"], "time": 0.5,
                   "in": ["2 iron-plate"], "out": ["1 iron-gear-wheel"]}


def test_recipe_row_caps_long_lists_and_shows_chances():
    row = ref.brief_recipe(SCRAP)
    assert len(row["out"]) == 9 and row["out"][-1] == "+22 more"
    assert row["out"][0] == "1 thing-0 (1%)"
    assert len(json.dumps(row)) < len(json.dumps(SCRAP)) / 3


def test_technology_row_has_cost_unlocks_and_other_effects():
    row = ref.brief_technology(TECH)
    assert row["cost"] == "2000 x [1 automation-science-pack, 1 logistic-science-pack]"
    assert row["unlocks"] == ["crusher"] and row["other_effects"] == ["ammo-damage"]
    assert "enabled" not in row and "research_trigger" not in row


def test_planet_row_keeps_the_key_properties_only():
    planet = {"name": "vulcanus", "type": "planet", "distance": 10,
              "surface_properties": {"gravity": 40, "pressure": 4000, "solar-power": 400, "rubia-wind-speed": 80}}
    assert ref.brief_planet(planet) == {"name": "vulcanus", "type": "planet", "distance": 10,
                                        "gravity": 40, "pressure": 4000, "solar-power": 400}


async def _setup(stack):
    stack.fake.responses[build_command("hello")] = hello_reply(("hello", "server_info", "players", "proto_recipes"))
    await stack.bridge.refresh_hello()
    stack.fake.responses[build_command("proto_recipes", {"offset": 0})] = json.dumps(
        {"v": 1, "ok": True, "result": {"kind": "recipes", "total": 2, "offset": 0, "items": [GEAR, SCRAP]}})


async def _call(stack, arguments):
    r = await stack.rpc("tools/call", {"name": "reference_recipes", "arguments": arguments})
    return json.loads(r.json()["result"]["content"][0]["text"])


async def test_lists_are_brief_and_one_name_is_full(stack):
    await _setup(stack)
    listed = await _call(stack, {"include_hidden": True})
    assert listed["items"][0]["in"] == ["2 iron-plate"] and "ingredients" not in listed["items"][0]
    one = await _call(stack, {"name": "iron-gear-wheel"})
    assert one["items"][0]["ingredients"] == GEAR["ingredients"]  # the full record
    full = await _call(stack, {"details": True})
    assert "ingredients" in full["items"][0]


async def test_a_page_of_recipes_stays_small(stack):
    await _setup(stack)
    text = json.dumps(await _call(stack, {"search": "recycling"}))
    assert len(text) < 1500  # the recycling recipe with 30 products was ~3 KB before
