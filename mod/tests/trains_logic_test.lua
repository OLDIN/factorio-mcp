-- Tests for trains_logic: one train as a record, problem trains first, paging within the budget.
package.path = "factorio-mcp/?.lua;tests/?.lua;" .. package.path
local env = require("support.env")
local e = env.fresh()
local trains_logic = require("scripts.logic.trains_logic")

local NAMES = { [0] = "on_the_path", [1] = "no_schedule", [2] = "no_path", [3] = "wait_station", [4] = "manual_control",
  [5] = "destination_full" }

local function train(id, state, opts)
  opts = opts or {}
  return {
    id = id, state = state, group = opts.group,
    front_stock = { surface = { name = "nauvis" }, position = { x = id, y = 2 } },
    station = opts.station and { backer_name = opts.station } or nil,
    path_end_stop = opts.target and { backer_name = opts.target } or nil,
    get_schedule = function() return { ticks_in_station = opts.ticks or 0 } end,
    get_contents = function() return opts.cargo or {} end,
    get_fluid_contents = function() return opts.fluids or {} end,
  }
end

local r = trains_logic.record(train(7, 3, { station = "Iron unload", ticks = 20000,
  cargo = { { name = "iron-ore", quality = "normal", count = 1000 }, { name = "iron-ore", quality = "rare", count = 10 } } }), NAMES)
assert(r.id == 7 and r.state == "wait_station" and r.station == "Iron unload" and r.surface == "nauvis")
assert(r.problem == "long_wait", "waiting over 5 minutes")
assert(r.cargo[1].name == "iron-ore" and r.cargo[1].count == 1010, "cargo summed over qualities")
assert(r.gps == "[gps=7,2,nauvis]")

assert(trains_logic.record(train(1, 2), NAMES).problem == "no_path")
assert(trains_logic.record(train(1, 1), NAMES).problem == "no_schedule")
assert(trains_logic.record(train(1, 5), NAMES).problem == "destination_full")
assert(trains_logic.record(train(1, 4, { cargo = { { name = "coal", count = 5 } } }), NAMES).problem == "manual_with_cargo")
assert(trains_logic.record(train(1, 4), NAMES).problem == nil, "an empty train in manual is fine")
assert(trains_logic.record(train(1, 0, { target = "Mine" }), NAMES).target == "Mine")
local f = trains_logic.record(train(2, 0, { fluids = { water = 25000.4 } }), NAMES)
assert(f.fluids[1].name == "water" and f.fluids[1].amount == 25000)

-- 500 trains: problems first, one page, under the budget
local records = {}
for i = 1, 500 do records[i] = trains_logic.record(train(i, i % 50 == 0 and 2 or 0, { target = "Station " .. i }), NAMES) end
local page = trains_logic.page(records, false, 0, 15)
assert(page.total == 500 and page.problems_total == 10 and #page.trains == 15 and page.next == 15)
assert(page.trains[1].problem == "no_path" and page.trains[10].problem == "no_path" and page.trains[11].problem == nil)
assert(page.by_state.on_the_path == 490 and page.by_state.no_path == 10)
assert(#e.json.encode(page) < 48000, "page fits the response budget")
local only = trains_logic.page(records, true, 0, 50)
assert(#only.trains == 10 and only.next == nil, "problems only")

print("trains_logic_test ok")
