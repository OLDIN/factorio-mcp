-- Tests for defenses_scan: verifies detection of turrets, ammo, fluids, power, and damage.
package.path = "factorio-mcp/?.lua;tests/?.lua;" .. package.path
local env = require("support.env")
env.fresh()
_G.defines = {
  inventory = {
    turret_ammo = 1,
    artillery_turret_ammo = 2,
  },
}
local defenses_scan = require("scripts.logic.defenses_scan")

local gun_empty = {
  valid = true,
  name = "gun-turret",
  type = "ammo-turret",
  position = { x = 10, y = 10 },
  health = 400,
  max_health = 400,
  get_inventory = function()
    return {
      valid = true,
      get_contents = function() return {} end,
    }
  end,
}

local gun_ready = {
  valid = true,
  name = "gun-turret",
  type = "ammo-turret",
  position = { x = 12, y = 10 },
  health = 350,
  max_health = 400,
  get_inventory = function()
    return {
      valid = true,
      get_contents = function() return { { name = "firearm-magazine", count = 30 } } end,
    }
  end,
}

local laser_unpowered = {
  valid = true,
  name = "laser-turret",
  type = "electric-turret",
  position = { x = 14, y = 10 },
  health = 1000,
  max_health = 1000,
  energy = 0,
}

local flame_ready = {
  valid = true,
  name = "flamethrower-turret",
  type = "fluid-turret",
  position = { x = 16, y = 10 },
  health = 1400,
  max_health = 1400,
  get_fluid_contents = function()
    return { ["light-oil"] = 50.0 }
  end,
}

local wall_damaged = {
  valid = true,
  name = "stone-wall",
  type = "wall",
  position = { x = 20, y = 20 },
  health = 150,
  max_health = 350,
}

-- Enemy worms are type "turret" with no ammo inventory: they must not count as dry turrets.
local enemy_worm = {
  valid = true,
  name = "medium-worm-turret",
  type = "turret",
  force = { name = "enemy" },
  position = { x = 40, y = 40 },
  health = 100,
  max_health = 500,
}

local neutral_wall = {
  valid = true,
  name = "stone-wall",
  type = "wall",
  force = { name = "neutral" },
  position = { x = 30, y = 30 },
  health = 10,
  max_health = 350,
}

local entities_mock = {
  gun_empty, gun_ready, laser_unpowered, flame_ready, wall_damaged, enemy_worm, neutral_wall,
}

local surface = {
  name = "nauvis",
  find_entities_filtered = function(filter)
    local allowed = {}
    for _, t in ipairs(filter.type) do allowed[t] = true end
    local out = {}
    for _, e in ipairs(entities_mock) do
      if allowed[e.type] then out[#out + 1] = e end
    end
    return out
  end,
}

local res = defenses_scan.scan(surface, { x = 0, y = 0 }, 64, 20)

assert(res.summary.total == 5, "expected 5 total entities")
assert(res.summary.turrets == 4, "expected 4 turrets")
assert(res.summary.walls == 1, "expected 1 wall")
assert(res.summary.issues.no_ammo == 1, "expected 1 no_ammo")
assert(res.summary.issues.no_power == 1, "expected 1 no_power")
assert(res.summary.issues.no_fluid == 0, "expected 0 no_fluid")
assert(res.summary.issues.damaged == 2, "expected 2 damaged entities")

assert(#res.problems == 4, "expected 4 problem entities")
-- Highest priority should be unsupplied turrets (gun_empty, laser_unpowered)
assert(res.problems[1].issue == "no_ammo" or res.problems[1].issue == "no_power")
for _, p in ipairs(res.problems) do
  assert(p.name ~= "medium-worm-turret", "enemy worm must be skipped")
  assert(not (p.x == 30 and p.y == 30), "neutral wall must be skipped")
end
for _, g in ipairs(res.groups) do
  assert(g.type ~= "turret", "no enemy turret group expected")
end

-- max_listed trims the list but keeps the full count
local trimmed = defenses_scan.scan(surface, { x = 0, y = 0 }, 64, 2)
assert(#trimmed.problems == 2, "expected problems trimmed to 2")
assert(trimmed.problems_total == 4, "expected problems_total 4")

-- Speed (a wall-heavy spot has ~1,400 walls in 64 tiles): a healthy wall's position is never read,
-- and with game.forces at hand the force is filtered in the search, not read per entity.
local function strict(fields)
  return setmetatable({}, { __index = function(_, k)
    local v = fields[k]
    if v == nil then error("read of " .. k) end
    return v
  end })
end
local healthy = strict({ valid = true, name = "stone-wall", type = "wall", health = 350, max_health = 350,
  force = { name = "player" } })
local hr = defenses_scan.record(healthy)
assert(hr and not hr.damaged and hr.x == nil, "healthy wall: no position read")
local strict_damaged = strict({ valid = true, name = "stone-wall", type = "wall", health = 10, max_health = 350,
  position = { x = 5, y = 6 } })
local acc_fast = defenses_scan.new_acc(5)
_G.game = { forces = { player = { name = "player" }, enemy = { name = "enemy" }, neutral = { name = "neutral" },
  ["player-2"] = { name = "player-2" } } }
local seen_force
local fast_surface = {
  name = "nauvis",
  find_entities_filtered = function(filter)
    seen_force = filter.force
    return { healthy, strict_damaged }
  end,
}
local fast = defenses_scan.scan(fast_surface, { x = 0, y = 0 }, 64, 5)
table.sort(seen_force)
assert(seen_force and #seen_force == 2 and seen_force[1] == "player" and seen_force[2] == "player-2",
  "enemy and neutral filtered in the search")
assert(fast.summary.walls == 2 and fast.problems_total == 1 and fast.problems[1].x == 5, "damaged wall listed with its position")
_G.game = nil

print("defenses_scan_test ok")
