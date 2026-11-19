-- Privacy: only allowlisted entity types are ever requested from the surface.
package.path = "factorio-mcp/?.lua;tests/?.lua;" .. package.path
local env = require("support.env")
env.fresh()
_G.defines = { entity_status = { working = 1 }, inventory = { crafter_input = 1 } }
local area_scan = require("scripts.logic.area_scan")

local queries = {}
local car = { name = "car", type = "car", position = { x = 0, y = 0 }, get_inventory = function() error("touched car") end }
local corpse = { name = "character-corpse", type = "character-corpse", position = { x = 0, y = 0 } }
local machine = {
  name = "assembling-machine-2", type = "assembling-machine", position = { x = 3, y = 4 }, status = 1,
  get_recipe = function() return { name = "iron-gear-wheel" } end,
}
local surface = {
  find_entities_filtered = function(filter)
    queries[#queries + 1] = filter
    local out = {}
    local allowed = {}
    for _, t in ipairs(filter.type) do allowed[t] = true end
    for _, e in ipairs({ machine, car, corpse }) do
      if allowed[e.type] then out[#out + 1] = e end
    end
    return out
  end,
}
local res = area_scan.scan(surface, { x = 0, y = 0 }, 32, 20, 100000)
assert(#queries == 1 and type(queries[1].type) == "table", "type filter must always be set")
local allowed = {}
for _, t in ipairs(area_scan.AREA_TYPES) do allowed[t] = true end
for _, t in ipairs(queries[1].type) do assert(allowed[t], "non-allowlisted type queried: " .. t) end
for _, forbidden in ipairs({ "car", "character-corpse", "character", "spider-vehicle" }) do
  assert(not allowed[forbidden], forbidden .. " must not be in the allowlist")
end
local json = helpers.table_to_json(res)
assert(not json:find("car") and not json:find("corpse"), "no data from non-allowlisted entities")
assert(res.totals.machines == 1 and res.totals.working == 1)
-- enrichment of listed (stopped) machines: progress, modules, inputs and outputs; only the inventories a
-- machine of that type has are asked for (each lookup costs time, ~50 listed machines per answer)
_G.defines = { entity_status = { working = 1, no_ingredients = 2 }, inventory = {
  crafter_input = 1, crafter_output = 2, fuel = 3, lab_input = 4, agricultural_tower_input = 5,
  agricultural_tower_output = 6 } }
local function inv(list) return { valid = true, get_contents = function() return list end } end
local asked = {}
local stopped = {
  name = "assembling-machine-2", type = "assembling-machine", position = { x = 1, y = 1 }, status = 2,
  crafting_progress = 0.25, get_recipe = function() return { name = "iron-gear-wheel" } end,
  get_module_inventory = function() return inv({ { name = "speed-module", count = 2 } }) end,
  get_inventory = function(id)
    asked[#asked + 1] = id
    if id == 1 then return inv({ { name = "iron-plate", count = 7 } }) end
    if id == 2 then return inv({ { name = "iron-gear-wheel", count = 3 } }) end
    return nil
  end,
}
local lab = {
  name = "lab", type = "lab", position = { x = 2, y = 2 }, status = 2,
  get_module_inventory = function() return inv({}) end,
  get_inventory = function(id)
    asked[#asked + 1] = id
    if id == 4 then return inv({ { name = "automation-science-pack", count = 5 } }) end
    return nil
  end,
}
local listed = area_scan.scan({ find_entities_filtered = function() return { stopped, lab } end },
  { x = 0, y = 0 }, 32, 20, 100000)
local by_name = {}
for _, r in ipairs(listed.stopped) do by_name[r.name] = r end
local a = by_name["assembling-machine-2"]
assert(a.crafting_progress == 0.25 and a.modules["speed-module"] == 2, "progress and modules")
assert(a.input["iron-plate"] == 7 and a.output["iron-gear-wheel"] == 3, "inputs and outputs")
assert(by_name.lab.input["automation-science-pack"] == 5 and by_name.lab.output == nil, "lab inputs")
table.sort(asked)
assert(table.concat(asked, ",") == "1,2,3,4", "asked only own inventories, got " .. table.concat(asked, ","))

print("area_scan_test ok")
