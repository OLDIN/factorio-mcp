-- Tests for platforms_logic: one space platform as a record.
package.path = "factorio-mcp/?.lua;tests/?.lua;" .. package.path
local env = require("support.env")
env.fresh()
_G.defines = { inventory = { hub_main = 1 }, space_platform_state = { on_the_path = 3, waiting_at_station = 5, paused = 7 } }
local platforms_logic = require("scripts.logic.platforms_logic")

local names = platforms_logic.state_names()
assert(names[3] == "on_the_path" and names[5] == "waiting_at_station")

local hub = { valid = true, get_inventory = function(id)
  assert(id == 1, "hub main inventory")
  return { valid = true, get_contents = function()
    return { { name = "iron-plate", quality = "normal", count = 50 }, { name = "space-science-pack", quality = "normal", count = 400 } }
  end }
end }

local moving = { valid = true, name = "Alpha", state = 3, speed = 0.5, distance = 0.25,
  space_location = nil, last_visited_space_location = { name = "nauvis" },
  damaged_tiles = { {}, {} }, hub = hub, scheduled_for_deletion = 0 }
local r = platforms_logic.record(moving, names, 1)
assert(r.name == "Alpha" and r.state == "on_the_path" and r.location == nil and r.last_location == "nauvis")
assert(r.damaged_tiles == 2 and r.speed == 0.5 and r.distance == 0.25)
assert(#r.hub_contents == 1 and r.hub_contents[1].name == "space-science-pack", "biggest stock first, capped")

local parked = { valid = true, name = "Beta", state = 5, speed = 0, distance = 0, space_location = { name = "vulcanus" },
  damaged_tiles = {}, hub = nil, scheduled_for_deletion = 0 }
local b = platforms_logic.record(parked, names, 10)
assert(b.location == "vulcanus" and #b.hub_contents == 0, "no hub (not built yet) is fine")

print("platforms_logic_test ok")
