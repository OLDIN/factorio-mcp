-- Tests for mining_logic: remaining ore under a drill, depleted and low drills, groups and the worst list.
package.path = "factorio-mcp/?.lua;tests/?.lua;" .. package.path
local env = require("support.env")
env.fresh()
_G.defines = { entity_status = { working = 1, no_minable_resources = 9 } }
local mining_logic = require("scripts.logic.mining_logic")

-- a surface that answers find like the game: resources of one name inside the area
local function surface_with(resources)
  return {
    find_entities_filtered = function(filter)
      assert(filter.name and filter.area and not filter.radius, "one resource name, by the square mining area")
      local a = filter.area
      local out = {}
      for _, r in ipairs(resources) do
        if r.name == filter.name and r.position.x >= a[1][1] and r.position.x <= a[2][1]
          and r.position.y >= a[1][2] and r.position.y <= a[2][2] then
          out[#out + 1] = r
        end
      end
      return out
    end,
  }
end

local function ore(name, x, y, amount)
  return { valid = true, name = name, position = { x = x, y = y }, amount = amount,
    prototype = { infinite_resource = false, normal_resource_amount = 0 } }
end
local function oil(x, y, amount)
  return { valid = true, name = "crude-oil", position = { x = x, y = y }, amount = amount,
    prototype = { infinite_resource = true, normal_resource_amount = 300000 } }
end

local function drill(x, y, target, opts)
  opts = opts or {}
  return { valid = true, name = opts.name or "electric-mining-drill", type = "mining-drill", position = { x = x, y = y },
    prototype = { mining_drill_radius = opts.radius or 2.49 }, mining_target = target,
    status = opts.status or defines.entity_status.working }
end

-- remaining ore: only the target's resource inside the drill's square area
local a, b, far = ore("iron-ore", 10, 10, 100), ore("iron-ore", 11, 11, 200), ore("iron-ore", 40, 40, 999)
local copper = ore("copper-ore", 10, 11, 777)
local s = surface_with({ a, b, far, copper })
local r = mining_logic.record(drill(10, 10, a), s)
assert(r.resource == "iron-ore" and r.remaining == 300, "sum of the same resource in reach, got " .. tostring(r.remaining))
assert(r.depleted == false and r.low == true and r.infinite == false and r.x == 10 and r.y == 10)

-- plenty left: not low
local rich = surface_with({ ore("iron-ore", 0, 0, 90000) })
local rr = mining_logic.record(drill(0, 0, rich.find_entities_filtered({ name = "iron-ore", area = { { -3, -3 }, { 3, 3 } } })[1]), rich)
assert(rr.low == false and rr.remaining == 90000)

-- no target (or the game says no minable resources): depleted
local d1 = mining_logic.record(drill(5, 5, nil), s)
assert(d1.depleted == true and d1.remaining == 0 and d1.resource == nil)
local d2 = mining_logic.record(drill(10, 10, a, { status = defines.entity_status.no_minable_resources }), s)
assert(d2.depleted == true and d2.resource == "iron-ore")

-- a pumpjack on oil: yield percent of the start amount, never "remaining ore"
local well = oil(0, 0, 150000)
local oil_r = mining_logic.record(drill(0, 0, well, { name = "pumpjack", radius = 0.49 }), surface_with({ well }))
assert(oil_r.infinite == true and oil_r.remaining == 50 and oil_r.low == false, "50% yield, got " .. tostring(oil_r.remaining))
local weak = oil(0, 0, 30000)
local weak_r = mining_logic.record(drill(0, 0, weak, { name = "pumpjack", radius = 0.49 }), surface_with({ weak }))
assert(weak_r.remaining == 10 and weak_r.low == true)

-- a drill whose fields raise gives no record (never an error)
local broken = drill(1, 1, a)
broken.prototype = setmetatable({}, { __index = function() error("invalid") end })
assert(mining_logic.record(broken, s) == nil)
assert(mining_logic.record({ valid = false }, s) == nil)

-- groups and the worst list
local acc = mining_logic.new_acc(3)
local function add(rec, surface) mining_logic.add(acc, rec, surface or "nauvis") end
add({ name = "electric-mining-drill", resource = "iron-ore", remaining = 100000, depleted = false, low = false, infinite = false, x = 1, y = 1 })
add({ name = "electric-mining-drill", resource = "iron-ore", remaining = 300, depleted = false, low = true, infinite = false, x = 2, y = 2 })
add({ name = "electric-mining-drill", resource = "iron-ore", remaining = 0, depleted = true, low = true, infinite = false, x = 3, y = 3 })
add({ name = "electric-mining-drill", resource = "copper-ore", remaining = 4000, depleted = false, low = true, infinite = false, x = 4, y = 4 })
add({ name = "pumpjack", resource = "crude-oil", remaining = 10, depleted = false, low = true, infinite = true, x = 5, y = 5 }, "vulcanus")
add({ name = "electric-mining-drill", resource = nil, remaining = 0, depleted = true, low = true, infinite = false, x = 6, y = 6 })
local out = mining_logic.finish(acc)
assert(out.summary.drills == 6 and out.summary.depleted == 2 and out.summary.low == 5, "summary counts every drill")
assert(#out.worst == 3, "worst list is capped at keep")
assert(out.worst[1].depleted and out.worst[2].depleted, "depleted first")
assert(out.worst[3].remaining == 300 and out.worst[3].gps == "[gps=2,2,nauvis]", "then the least remaining ore")
local iron
for _, g in ipairs(out.groups) do if g.surface == "nauvis" and g.resource == "iron-ore" then iron = g end end
assert(iron.drills == 3 and iron.depleted == 1 and iron.low == 2 and iron.ore_in_reach == 100300)
local unknown
for _, g in ipairs(out.groups) do if g.resource == "unknown" then unknown = g end end
assert(unknown and unknown.depleted == 1, "a depleted drill without a target is grouped as unknown")
assert(out.groups[1].depleted >= out.groups[#out.groups].depleted, "most depleted groups first")

-- a big base: the candidate list stays bounded while the counts stay complete
local big = mining_logic.new_acc(5)
for i = 1, 2000 do
  mining_logic.add(big, { name = "d", resource = "iron-ore", remaining = i, depleted = false, low = true, infinite = false, x = i, y = 0 }, "nauvis")
end
assert(#big.candidates <= 4 * 5 + 16, "bounded candidates, got " .. #big.candidates)
local bo = mining_logic.finish(big)
assert(bo.summary.drills == 2000 and #bo.worst == 5 and bo.worst[1].remaining == 1)

print("mining_logic_test ok")
