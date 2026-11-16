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
print("area_scan_test ok")
