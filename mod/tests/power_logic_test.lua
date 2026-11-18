-- Tests for power_logic: network flows in kW, accumulator charge, network ordering.
package.path = "factorio-mcp/?.lua;tests/?.lua;" .. package.path
local env = require("support.env")
env.fresh()
local power_logic = require("scripts.logic.power_logic")

-- electric statistics: output = production, input = consumption, J per tick
local function fake_stats(output, input)
  return {
    output_counts = output, input_counts = input,
    get_flow_count = function(t)
      assert(t.precision_index == 3, "window passed through")
      local src = t.category == "output" and output or input
      return src[t.name] or 0
    end,
  }
end

local stats = fake_stats({ ["solar-panel"] = 3000, ["steam-engine"] = 1000 }, { ["assembling-machine-1"] = 41.6667 })
local s = power_logic.network_summary(stats, 3, 1)
assert(s.produced_kw == 240, "4000 J/tick = 240 kW, got " .. tostring(s.produced_kw))
assert(s.consumed_kw == 2.5, "41.67 J/tick = 2.5 kW, got " .. tostring(s.consumed_kw))
assert(#s.top_producers == 1 and s.top_producers[1].name == "solar-panel" and s.top_producers[1].kw == 180)
assert(s.top_consumers[1].name == "assembling-machine-1")

-- no flow at all: zeros, not NaN
local idle = power_logic.network_summary(fake_stats({}, {}), 3, 5)
assert(idle.produced_kw == 0 and idle.consumed_kw == 0 and #idle.top_producers == 0)

-- accumulators: charge share, nil when no buffer
local acc = power_logic.accumulators({ { energy = 1e6, electric_buffer_size = 5e6 }, { energy = 4e6, electric_buffer_size = 5e6 } })
assert(acc.count == 2 and acc.charge == 0.5)
local none = power_logic.accumulators({ { energy = 0, electric_buffer_size = 0 } })
assert(none.count == 1 and none.charge == nil, "zero buffer gives no charge")
assert(power_logic.accumulators({}).count == 0)

-- ordering: most starved first, then lowest accumulator charge, nil charge last
local nets = {
  { id = 1, starved = { low_power = 0, no_power = 0 }, accumulators = { count = 1, charge = 0.9 } },
  { id = 2, starved = { low_power = 3, no_power = 1 }, accumulators = { count = 0 } },
  { id = 3, starved = { low_power = 0, no_power = 0 }, accumulators = { count = 1, charge = 0.1 } },
  { id = 4, starved = { low_power = 0, no_power = 0 }, accumulators = { count = 0 } },
}
power_logic.sort_networks(nets)
assert(nets[1].id == 2 and nets[2].id == 3 and nets[3].id == 1 and nets[4].id == 4, "order")

print("power_logic_test ok")
