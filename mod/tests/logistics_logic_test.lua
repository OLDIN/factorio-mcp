-- Tests for logistics_logic: one logistic network summarized, ordering, counting one item.
package.path = "factorio-mcp/?.lua;tests/?.lua;" .. package.path
local env = require("support.env")
env.fresh()
local logistics_logic = require("scripts.logic.logistics_logic")

local function cell(x, to_charge)
  return { owner = { position = { x = x, y = 0 } }, to_charge_robot_count = to_charge }
end

local function net(id, avail, total, contents, cells)
  return {
    network_id = id, available_logistic_robots = avail, all_logistic_robots = total,
    available_construction_robots = 1, all_construction_robots = 2,
    cells = cells or { cell(10, 2), cell(20, 1) },
    get_contents = function() return contents end,
  }
end

local busy = net(1, 1, 10, {
  { name = "iron-plate", quality = "normal", count = 500 },
  { name = "iron-plate", quality = "rare", count = 5 },
  { name = "copper-plate", quality = "normal", count = 900 },
})
local s = logistics_logic.network(busy, "nauvis", 2)
assert(s.id == 1 and s.surface == "nauvis" and s.roboports == 2 and s.charging == 3)
assert(s.logistic_robots.available == 1 and s.logistic_robots.total == 10)
assert(s.gps == "[gps=10,0,nauvis]")
assert(#s.top_contents == 2 and s.top_contents[1].name == "copper-plate", "largest stacks first, capped")

-- no robots and no cells: no division by zero, no gps
local empty = logistics_logic.network(net(2, 0, 0, {}, {}), "nauvis", 5)
assert(empty.roboports == 0 and empty.gps == nil and #empty.top_contents == 0)

-- ordering: the least available share of logistic robots first; networks without robots last
local list = { s, empty, logistics_logic.network(net(3, 9, 10, {}), "nauvis", 5) }
logistics_logic.sort_networks(list)
assert(list[1].id == 1 and list[2].id == 3 and list[3].id == 2)

-- one item across networks, qualities summed
assert(logistics_logic.count_item(busy.get_contents(), "iron-plate") == 505)
assert(logistics_logic.count_item({}, "iron-plate") == 0)

print("logistics_logic_test ok")
