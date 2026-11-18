-- Tests for power_overview: one entry per electric network across a whole-map scan.
package.path = "factorio-mcp/?.lua;tests/?.lua;" .. package.path
local env = require("support.env")
env.fresh()
_G.defines = { entity_status = { working = 1, low_power = 2, no_power = 3 }, flow_precision_index = { five_seconds = 0 } }
local power_overview = require("scripts.logic.power_overview")

local function stats(consumed)
  return {
    output_counts = { ["steam-engine"] = 1 }, input_counts = { ["assembling-machine-2"] = 1 },
    get_flow_count = function(t) return t.category == "output" and 1000 or consumed end,
  }
end

local function pole(id, x, consumed)
  return { valid = true, type = "electric-pole", name = "medium-electric-pole", position = { x = x, y = 0 },
    electric_network_id = id, electric_network_statistics = stats(consumed) }
end

local function machine(id, status)
  return { valid = true, type = "assembling-machine", name = "assembling-machine-2", position = { x = 1, y = 1 },
    electric_network_id = id, status = status }
end

local acc = power_overview.new_acc()
for _, e in ipairs({ pole(7, 0, 500), pole(7, 5, 500), pole(7, 10, 500), pole(9, 100, 100),
  machine(9, 3), machine(9, 2), machine(7, 1) }) do
  power_overview.take(acc, e, "nauvis")
end
-- a lone pole with nothing consuming: counted as tiny, not listed
power_overview.take(acc, pole(11, 500, 0), "vulcanus")
local accu = { valid = true, type = "accumulator", position = { x = 2, y = 2 }, electric_network_id = 7,
  energy = 2.5e6, electric_buffer_size = 5e6 }
power_overview.take(acc, accu, "nauvis")

local out = power_overview.finish(acc, 5)
assert(out.summary.networks == 3, "three networks seen")
assert(out.summary.tiny == 1, "the lone idle pole is tiny")
assert(out.summary.starved_networks == 1)
assert(#out.list == 2, "tiny networks are not listed")
assert(out.list[1].id == 9, "the starved network first")
assert(out.list[1].starved.no_power == 1 and out.list[1].starved.low_power == 1)
assert(out.list[1].poles == 1 and out.list[2].poles == 3)
assert(out.list[2].accumulators.count == 1 and out.list[2].accumulators.charge == 0.5)
assert(out.list[1].surface == "nauvis" and out.list[1].gps == "[gps=100,0,nauvis]")

-- a pole that became invalid before the finish is skipped
local acc2 = power_overview.new_acc()
local gone = pole(5, 0, 10)
power_overview.take(acc2, gone, "nauvis")
gone.valid = false
assert(#power_overview.finish(acc2, 5).list == 0)

print("power_overview_test ok")
