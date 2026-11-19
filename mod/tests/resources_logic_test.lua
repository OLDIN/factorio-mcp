-- Tests for resources_logic: patches from resource entities, merged across touching chunks.
package.path = "factorio-mcp/?.lua;tests/?.lua;" .. package.path
local env = require("support.env")
env.fresh()
local resources_logic = require("scripts.logic.resources_logic")

local function field(name, x0, y0, w, h, amount, fluid)
  local out = {}
  for x = x0, x0 + w - 1 do
    for y = y0, y0 + h - 1 do out[#out + 1] = { name = name, x = x + 0.5, y = y + 0.5, amount = amount, fluid = fluid } end
  end
  return out
end

local function join(...)
  local out = {}
  for _, list in ipairs({ ... }) do for _, r in ipairs(list) do out[#out + 1] = r end end
  return out
end

-- two iron fields three chunks apart: two patches, the bigger first
local apart = join(field("iron-ore", 0, 0, 4, 4, 100), field("iron-ore", 96, 0, 2, 2, 1000))
local p = resources_logic.patches(apart, "nauvis")
assert(#p == 2, "fields 3 chunks apart are separate patches")
assert(p[1].tiles == 16 and p[1].amount == 1600 and p[2].tiles == 4 and p[2].amount == 4000, "most tiles first")
assert(p[1].fluid == false and p[1].wells == nil)
assert(p[1].gps == "[gps=2,2,nauvis]", "centre of the patch: " .. p[1].gps)

-- a field crossing a chunk border (and a diagonal neighbour chunk): one patch
local across = join(field("iron-ore", 30, 30, 4, 4, 10), field("iron-ore", 64, 64, 1, 1, 10))
local q = resources_logic.patches(across, "nauvis")
assert(#q == 1 and q[1].tiles == 17, "touching chunks merge")

-- different resources in the same chunk stay apart
local mixed = join(field("iron-ore", 0, 0, 2, 2, 10), field("copper-ore", 4, 4, 3, 3, 10))
local m = resources_logic.patches(mixed, "nauvis")
assert(#m == 2 and m[1].name == "copper-ore" and m[2].name == "iron-ore")

-- crude oil: raw amounts summed, wells instead of tiles
local oil = { { name = "crude-oil", x = 10, y = 10, amount = 300000, fluid = true },
              { name = "crude-oil", x = 20, y = 14, amount = 150000, fluid = true } }
local o = resources_logic.patches(oil, "nauvis")
assert(#o == 1 and o[1].fluid == true and o[1].wells == 2 and o[1].tiles == nil and o[1].amount == 450000)

assert(#resources_logic.patches({}, "nauvis") == 0)

-- fluid detection from the prototype's first mining product
assert(resources_logic.is_fluid({ mineable_properties = { products = { { type = "fluid", name = "crude-oil" } } } }))
assert(not resources_logic.is_fluid({ mineable_properties = { products = { { type = "item", name = "iron-ore" } } } }))
assert(not resources_logic.is_fluid({}), "no mineable properties is not a fluid")

print("resources_logic_test ok")
