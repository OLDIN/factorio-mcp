-- Tests for transport_logic: the allowlist (privacy), stuck inserters first, belt items, fluids.
package.path = "factorio-mcp/?.lua;tests/?.lua;" .. package.path
local env = require("support.env")
env.fresh()
local transport_logic = require("scripts.logic.transport_logic")

-- privacy: no vehicles, characters or wagons, and area_scan's allowlist is untouched
local allowed = {}
for _, t in ipairs(transport_logic.TYPES) do allowed[t] = true end
for _, forbidden in ipairs({ "car", "character", "spider-vehicle", "cargo-wagon", "fluid-wagon", "locomotive",
  "character-corpse", "container", "logistic-container" }) do
  assert(not allowed[forbidden], forbidden .. " must not be in the transport allowlist")
end
_G.defines = { entity_status = { working = 1 }, inventory = { crafter_input = 1 } }
local area_scan = require("scripts.logic.area_scan")
for _, t in ipairs(area_scan.AREA_TYPES) do assert(t ~= "inserter" and t ~= "transport-belt", "AREA_TYPES unchanged") end

local acc = transport_logic.new_acc(2)
transport_logic.count(acc, "inserter")
transport_logic.add_inserter(acc, { name = "inserter", gps = "[gps=1,1,nauvis]", status = "working" })
transport_logic.add_inserter(acc, { name = "inserter", gps = "[gps=2,1,nauvis]", status = "waiting_for_source_items" })
transport_logic.add_inserter(acc, { name = "fast-inserter", gps = "[gps=3,1,nauvis]", status = "waiting_for_space_in_destination" })
transport_logic.add_inserter(acc, { name = "inserter", gps = "[gps=4,1,nauvis]", status = "no_power" })
transport_logic.add_belt_items(acc, { { name = "iron-plate", quality = "normal", count = 3 }, { name = "coal", count = 1 } })
transport_logic.add_belt_items(acc, { { name = "iron-plate", quality = "rare", count = 2 } })
transport_logic.add_fluid(acc, "water", 100.04)
transport_logic.add_fluid(acc, "water", 50)
transport_logic.add_fluid(acc, "crude-oil", 500)
local r = transport_logic.finish(acc)

assert(r.counts.inserter == 1)
assert(r.inserters.by_status.working == 1 and r.inserters.by_status.no_power == 1)
assert(r.inserters.stuck_total == 3, "working inserters are not stuck")
assert(#r.inserters.stuck == 2, "stuck list capped at limit")
assert(r.inserters.stuck[1].status == "no_power", "unpowered first")
assert(r.inserters.stuck[2].status == "waiting_for_space_in_destination", "then blocked outputs")
assert(r.belts.items[1].name == "iron-plate" and r.belts.items[1].count == 5, "qualities summed, most first")
assert(r.belts.items[2].name == "coal")
assert(r.fluids[1].name == "crude-oil" and r.fluids[2].amount == 150, "fluids summed and rounded")

-- fluids of one entity: Factorio 2.1 has no LuaEntity.fluidbox (reading it raises); fluids_count and
-- get_fluid(i) give the entity's own share of its segment, so summing over entities counts nothing twice
local function fluid_entity(fluids)
  return setmetatable({
    fluids_count = #fluids,
    get_fluid = function(i) return fluids[i] end,
  }, { __index = function(_, k) error("LuaEntity doesn't contain key " .. k .. ".") end })
end
local fl = transport_logic.new_acc(5)
transport_logic.add_entity_fluids(fl, fluid_entity({ { name = "water", amount = 18 } }))
transport_logic.add_entity_fluids(fl, fluid_entity({ { name = "water", amount = 4620 } }))
transport_logic.add_entity_fluids(fl, fluid_entity({ false, { name = "steam", amount = 7 } })) -- empty box first
local f = transport_logic.finish(fl).fluids
assert(f[1].name == "water" and f[1].amount == 4638 and f[2].name == "steam" and f[2].amount == 7, "per-entity shares summed")

-- top 10 belt items only
local many = transport_logic.new_acc(5)
for i = 1, 12 do transport_logic.add_belt_items(many, { { name = "item-" .. i, count = i } }) end
local items = transport_logic.finish(many).belts.items
assert(#items == 10 and items[1].name == "item-12")

print("transport_logic_test ok")
