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

-- the accumulator (what the command and the job use): per-chunk sums while reading, no per-tile records,
-- plain data only (it is kept in storage between ticks); same answer as patches(records)
local acc = resources_logic.new_acc()
for _, r in ipairs(join(apart, across, oil)) do resources_logic.add(acc, r.name, r.x, r.y, r.amount, r.fluid) end
local via_acc = resources_logic.finish(acc, "nauvis")
local via_records = resources_logic.patches(join(apart, across, oil), "nauvis")
assert(#via_acc == #via_records and #via_acc == 3, "iron (apart and across merge) + oil")
for i = 1, #via_acc do
  for _, k in ipairs({ "name", "amount", "tiles", "wells", "gps", "fluid" }) do
    assert(via_acc[i][k] == via_records[i][k], "field " .. k .. " of patch " .. i)
  end
end
for _, chunks in pairs(acc.chunks) do
  for key, c in pairs(chunks) do
    assert(type(key) == "number" and type(c) == "table" and c.n > 0, "numeric chunk keys")
  end
end

-- negative coordinates: chunks -1 and 0 touch, -2 and 0 do not
local neg = resources_logic.new_acc()
resources_logic.add(neg, "stone", -0.5, -0.5, 5, false)
resources_logic.add(neg, "stone", 0.5, 0.5, 5, false)
resources_logic.add(neg, "coal", -40.5, 3.5, 5, false)
resources_logic.add(neg, "coal", 33.5, 3.5, 5, false)
local np = resources_logic.finish(neg, "nauvis")
assert(#np == 3 and np[1].name == "stone" and np[1].tiles == 2, "stone merges across 0, coal stays two")

-- fluid detection from the prototype's first mining product
assert(resources_logic.is_fluid({ mineable_properties = { products = { { type = "fluid", name = "crude-oil" } } } }))
assert(not resources_logic.is_fluid({ mineable_properties = { products = { { type = "item", name = "iron-ore" } } } }))
assert(not resources_logic.is_fluid({}), "no mineable properties is not a fluid")

print("resources_logic_test ok")
