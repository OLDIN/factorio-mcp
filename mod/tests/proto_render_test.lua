-- Pure-Lua tests for scripts/logic/proto_render.lua (fake prototype objects)
package.path = "factorio-mcp/?.lua;tests/?.lua;" .. package.path
local env = require("support.env")
env.fresh()
local r = require("scripts.logic.proto_render")

-- recipe: scalar-only copies, ingredient/product shapes kept
local recipe = r.recipe({
  name = "iron-gear-wheel", categories = { "crafting" }, energy = 0.5, enabled = true, hidden = false,
  ingredients = { { type = "item", name = "iron-plate", amount = 2 } },
  products = { { type = "item", name = "iron-gear-wheel", amount = 1, probability = 1, quality_min = {} } },
  surface_conditions = {}, maximum_productivity = 3,
})
assert(recipe.name == "iron-gear-wheel" and recipe.categories[1] == "crafting")
assert(recipe.ingredients[1].name == "iron-plate" and recipe.ingredients[1].amount == 2)
assert(recipe.products[1].quality_min == nil, "non-scalar fields are dropped")

-- machine: only keys whose value is true; methods called safely
local machine = r.machine({
  name = "assembling-machine-3", type = "assembling-machine",
  crafting_categories = { crafting = true, ["advanced-crafting"] = true },
  allowed_effects = { speed = true, pollution = false },
  module_inventory_size = 4, energy_usage = 375000,
  get_crafting_speed = function(q) assert(q == "normal"); return 1.25 end,
  get_max_health = function() error("boom") end,
})
assert(machine.crafting_categories[1] == "advanced-crafting" and machine.crafting_categories[2] == "crafting")
assert(#machine.allowed_effects == 1 and machine.allowed_effects[1] == "speed")
assert(machine.crafting_speed == 1.25 and machine.max_health == nil)
assert(r.is_machine({ crafting_categories = { crafting = true } }))
assert(not r.is_machine({ crafting_categories = {} }))
assert(r.is_machine({ resource_categories = { ["basic-solid"] = true } }))
assert(not r.is_machine({ type = "wall" }))

-- attribute read errors (a type without the field) are tolerated
local raising = setmetatable({ name = "x" }, { __index = function() error("no such attribute") end })
assert(r.item(raising).name == "x")

-- planet: own values override defaults, missing ones get the global default
local planet = r.planet({ name = "nauvis", type = "planet", surface_properties = { gravity = 10 } }, { gravity = 1, pressure = 1000 })
assert(planet.surface_properties.gravity == 10 and planet.surface_properties.pressure == 1000)

-- names: sorted and filtered
local names = r.names({ b = { ok = true }, a = { ok = true }, c = { ok = false } }, function(p) return p.ok end)
assert(#names == 2 and names[1] == "a" and names[2] == "b")

print("proto_render_test ok")
