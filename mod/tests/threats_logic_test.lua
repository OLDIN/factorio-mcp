-- Tests for threats_logic: enemy structures counted by name, nearest first with distance and direction.
package.path = "factorio-mcp/?.lua;tests/?.lua;" .. package.path
local env = require("support.env")
env.fresh()
local threats_logic = require("scripts.logic.threats_logic")

local center = { x = 0, y = 0 }
local acc = threats_logic.new_acc(center, "nauvis", 2)
threats_logic.add(acc, { name = "biter-spawner", type = "unit-spawner", x = 0, y = -100, pollution = 12.5 })
threats_logic.add(acc, { name = "medium-worm-turret", type = "turret", x = 30, y = 40 })
threats_logic.add(acc, { name = "biter-spawner", type = "unit-spawner", x = 300, y = 0, pollution = 0 })

local out = threats_logic.finish(acc)
assert(out.total == 3 and out.counts["biter-spawner"] == 2 and out.counts["medium-worm-turret"] == 1)
assert(#out.nearest == 2, "limit keeps the 2 nearest")
assert(out.nearest[1].name == "medium-worm-turret" and out.nearest[1].distance == 50, "nearest first")
assert(out.nearest[1].direction == "SE" and out.nearest[1].gps == "[gps=30,40,nauvis]")
assert(out.nearest[1].pollution == nil, "pollution only for spawners")
assert(out.nearest[2].direction == "N" and out.nearest[2].distance == 100 and out.nearest[2].pollution == 12.5)

-- enemy force names: every force the caller's force treats as an enemy
local player = { name = "player" }
local forces = { player = player, enemy = { name = "enemy" }, neutral = { name = "neutral" }, pirates = { name = "pirates" } }
player.is_enemy = function(other) return other.name == "enemy" or other.name == "pirates" end
local names = threats_logic.enemy_force_names(player, forces)
table.sort(names)
assert(#names == 2 and names[1] == "enemy" and names[2] == "pirates")

-- nothing around: empty answer
local empty = threats_logic.finish(threats_logic.new_acc(center, "nauvis", 5))
assert(empty.total == 0 and #empty.nearest == 0)

-- a demolisher (segmented unit) is added by its head position
local unit = { valid = true, force = { name = "enemy" }, prototype = { name = "small-demolisher" },
  segments = { { position = { x = 0, y = 60 } } } }
local acc2 = threats_logic.new_acc(center, "vulcanus", 5)
threats_logic.add_segmented(acc2, { unit, { valid = true, force = { name = "player" }, prototype = { name = "x" }, segments = {} } },
  { enemy = true }, 100)
local out2 = threats_logic.finish(acc2)
assert(out2.total == 1 and out2.nearest[1].name == "small-demolisher" and out2.nearest[1].type == "segmented-unit")
assert(out2.nearest[1].direction == "S")

print("threats_logic_test ok")
