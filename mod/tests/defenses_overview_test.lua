-- Tests for the defenses accumulator used by the whole-base overview: per-surface counts, gps in problems.
package.path = "factorio-mcp/?.lua;tests/?.lua;" .. package.path
local env = require("support.env")
env.fresh()
_G.defines = { inventory = { turret_ammo = 1, artillery_turret_ammo = 2 } }
local defenses_scan = require("scripts.logic.defenses_scan")

local function dry_turret(x)
  return { valid = true, name = "gun-turret", type = "ammo-turret", position = { x = x, y = 0 },
    health = 400, max_health = 400,
    get_inventory = function() return { valid = true, get_contents = function() return {} end } end }
end
local function wall(x, health)
  return { valid = true, name = "stone-wall", type = "wall", position = { x = x, y = 5 }, health = health, max_health = 350 }
end

local acc = defenses_scan.new_acc(10)
defenses_scan.add(acc, defenses_scan.record(dry_turret(1)), "nauvis")
defenses_scan.add(acc, defenses_scan.record(dry_turret(2)), "vulcanus")
defenses_scan.add(acc, defenses_scan.record(wall(3, 100)), "nauvis")
defenses_scan.add(acc, defenses_scan.record(wall(4, 350)), "nauvis")
-- an enemy worm gives no record
assert(defenses_scan.record({ valid = true, name = "medium-worm-turret", type = "turret", force = { name = "enemy" },
  position = { x = 0, y = 0 }, health = 1, max_health = 2 }) == nil)

local out = defenses_scan.finish(acc)
assert(out.summary.total == 4 and out.summary.issues.no_ammo == 2 and out.summary.issues.damaged == 1)
assert(out.by_surface.nauvis.total == 3 and out.by_surface.nauvis.problems == 2)
assert(out.by_surface.vulcanus.total == 1 and out.by_surface.vulcanus.problems == 1)
assert(out.problems_total == 3)
assert(out.problems[1].issue == "no_ammo" and out.problems[1].gps:match("^%[gps="), "problems carry gps")
assert(out.problems[3].issue == "damaged" and out.problems[3].surface == "nauvis")

-- a big base: the problem list stays bounded while problems_total counts all
local big = defenses_scan.new_acc(5)
for i = 1, 500 do defenses_scan.add(big, defenses_scan.record(wall(i, 10 + i % 7)), "nauvis") end
local big_out = defenses_scan.finish(big)
assert(big_out.problems_total == 500 and #big_out.problems == 5)
assert(big_out.problems[1].health <= big_out.problems[5].health, "worst health first")

print("defenses_overview_test ok")
