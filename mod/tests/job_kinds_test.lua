package.path = "factorio-mcp/?.lua;tests/?.lua;" .. package.path
local env = require("support.env")
env.fresh()
_G.defines = { entity_status = { working = 1, no_ingredients = 2, no_power = 3 }, inventory = {} }
local engine = require("scripts.logic.job_engine")
local kinds = require("scripts.logic.job_kinds")
local area_scan = require("scripts.logic.area_scan")

local function machine(name, x, y, status, recipe)
  return {
    name = name, type = "assembling-machine", position = { x = x, y = y }, status = status, valid = true,
    get_recipe = function() return { name = recipe } end,
  }
end

-- a fake surface that answers count/find like the game: anything whose position is within a
-- one-tile margin of the area (so entities on a border can come back for two areas)
local function make_surface(entities, chunks)
  local queries = { count = 0, find = 0 }
  local function inside(entity, a)
    local p = entity.position
    return p.x >= a[1][1] - 1 and p.x <= a[2][1] and p.y >= a[1][2] - 1 and p.y <= a[2][2]
  end
  local function select(filter)
    assert(type(filter.type) == "table" and filter.area and not filter.position, "allowlisted types, by area")
    local types = {}
    for _, t in ipairs(filter.type) do types[t] = true end
    local out = {}
    for _, e in ipairs(entities) do
      local fname = e.force and e.force.name or "player"
      local force_ok = filter.force == nil
      if type(filter.force) == "string" then force_ok = fname == filter.force end
      if type(filter.force) == "table" then
        for _, f in ipairs(filter.force) do if f == fname then force_ok = true end end
      end
      if inside(e, filter.area) and types[e.type] and force_ok then out[#out + 1] = e end
    end
    return out
  end
  return {
    valid = true, name = "nauvis", queries = queries,
    get_chunks = function()
      local i = 0
      return function() i = i + 1; return chunks[i] end
    end,
    count_entities_filtered = function(filter) queries.count = queries.count + 1; return #select(filter) end,
    find_entities_filtered = function(filter) queries.find = queries.find + 1; return select(filter) end,
  }
end

local function run(kind, params, surface)
  _G.game = {
    surfaces = { nauvis = surface }, get_surface = function(name) return name == "nauvis" and surface or nil end,
    get_player = function(name) if name == "alice" then return { name = "alice", force = { name = "player" } } end end,
  }
  local plan = kinds.plan(kind, params)
  plan.mode = "idle"
  plan.initial_items = math.floor(#plan.work / 4)  -- the work list is consumed by the run
  local state = engine.new()
  local id = engine.start(state, kind, plan.params or params, 1, plan)
  assert(engine.step(state, id, 1e9, kinds.stepper(kind)))
  return engine.take_page(state, id, 0, 1000, 1e6), plan
end

-- overview: every machine is counted exactly once, even one on a border between areas
local entities = {
  machine("asm", 5, 5, 1, "gear"), machine("asm", 31.9, 5, 2, "gear"), machine("asm", 32, 5, 2, "gear"),
  machine("asm", 40, 40, 2, "plate"),
}
local surface = make_surface(entities, { { x = 0, y = 0 }, { x = 1, y = 0 }, { x = 1, y = 1 } })
local page, plan = run("machines_overview", {}, surface)
assert(page.summary.machines == 4 and page.summary.working == 1, "got " .. page.summary.machines)
assert(#page.groups == 2 and page.groups[1].recipe == "gear" and page.groups[1].count == 3)
assert(#page.groups[1].examples == 2)
assert(plan.initial_items == 1, "chunks 0..1 fit one 512-tile block")

-- a crowded block is split until the pieces are small, and nothing is lost or counted twice
local crowd = {}
for i = 1, 150 do crowd[i] = machine("asm", 3 + (i % 10) * 40, 3 + math.floor(i / 10) * 20, 1 + (i % 2), "gear") end
local crowded = make_surface(crowd, { { x = 0, y = 0 }, { x = 15, y = 15 } })
page = run("machines_overview", {}, crowded)
assert(page.summary.machines == 150, "got " .. page.summary.machines)
assert(crowded.queries.count > 1, "the crowded block was split and recounted")

-- an empty map costs one count per block and no reads at all
local empty = make_surface({}, { { x = -3, y = -3 }, { x = 40, y = 40 } })
page = run("machines_overview", {}, empty)
assert(page.summary.machines == 0 and empty.queries.find == 0)

-- area job: only machines inside the radius
page = run("area", { surface = "nauvis", x = 5, y = 5, radius = 26.95 }, surface)
assert(page.totals.machines == 2 and page.radius == 26.95 and page.center.surface == "nauvis")

-- the entity types are always the allowlist
local seen_types = {}
local probe = make_surface(entities, { { x = 0, y = 0 } })
local original = probe.count_entities_filtered
probe.count_entities_filtered = function(filter)
  for _, t in ipairs(filter.type) do seen_types[t] = true end
  return original(filter)
end
run("machines_overview", {}, probe)
local allowed = {}
for _, t in ipairs(area_scan.AREA_TYPES) do allowed[t] = true end
for t in pairs(seen_types) do assert(allowed[t], "non-allowlisted type queried: " .. t) end

-- bad input
_G.game = { surfaces = { nauvis = surface }, get_surface = function(name) return name == "nauvis" and surface or nil end }
for _, bad in ipairs({
  { "area", { surface = "nauvis", x = 0, y = 0, radius = 5000 } },
  { "area", { surface = "nauvis", x = 0, y = 0, radius = -1 } },
  { "area", { surface = "nope", x = 0, y = 0, radius = 5 } },
  { "machines_overview", { surfaces = { "nope" } } },
  { "machines_overview", { surfaces = "nauvis" } },
  { "no-such-kind", {} },
}) do
  local ok, err = pcall(kinds.plan, bad[1], bad[2])
  assert(not ok and type(err) == "table" and err.code, "expected a coded error for " .. bad[1])
end

-- a repeated surface name must not multiply the work
local once = kinds.plan("machines_overview", { surfaces = { "nauvis" } })
local many = kinds.plan("machines_overview", { surfaces = { "nauvis", "nauvis", "nauvis", "nauvis" } })
assert(#many.work == #once.work and #many.surfaces == 1)

-- a map larger than the limit is refused
local limits = require("scripts.limits")
local saved = limits.MAX_JOB_CHUNKS
limits.MAX_JOB_CHUNKS = 2
local ok, err = pcall(kinds.plan, "machines_overview", {})
limits.MAX_JOB_CHUNKS = saved
assert(not ok and err.code == "bad_params", "the size limit must be enforced")

-- power_overview: the caller's force is resolved at planning; other forces' poles are not read
_G.defines.flow_precision_index = { five_seconds = 0 }
local function stats() return { output_counts = {}, input_counts = { lamp = 1 }, get_flow_count = function() return 10 end } end
local power_entities = {
  { name = "small-electric-pole", type = "electric-pole", position = { x = 3, y = 3 }, valid = true,
    electric_network_id = 1, electric_network_statistics = stats() },
  { name = "small-electric-pole", type = "electric-pole", position = { x = 6, y = 3 }, valid = true,
    electric_network_id = 2, electric_network_statistics = stats(), force = { name = "enemy" } },
  machine("asm", 4, 4, 3, "gear"),
}
power_entities[3].electric_network_id = 1
local power_surface = make_surface(power_entities, { { x = 0, y = 0 } })
local power_page, power_plan = run("power_overview", { caller = "alice" }, power_surface)
assert(power_plan.params.force == "player", "force from the caller")
assert(power_page.summary.networks == 1, "the enemy pole is filtered out")
assert(power_page.networks[1].starved.no_power == 1)
local bad_ok, bad_err = pcall(kinds.plan, "power_overview", { caller = "nobody" })
assert(not bad_ok and bad_err.code == "not_found", "unknown caller")

-- threats job: enemy spawners within the radius, nearest first; player-force entities never counted
local enemy = { name = "enemy" }
local function spawner(x, y, force)
  return { name = "biter-spawner", type = "unit-spawner", position = { x = x, y = y }, valid = true, force = force }
end
local threat_surface = make_surface({ spawner(100, 0, enemy), spawner(400, 0, enemy), spawner(900, 0, enemy), spawner(480, 300, enemy),
  spawner(50, 0, { name = "player" }) }, { { x = 0, y = 0 } })
threat_surface.get_pollution = function() return 3 end
threat_surface.get_segmented_units = function() return {} end
local alice_force = { name = "player", is_enemy = function(other) return other.name == "enemy" end }
local function run_threats(params)
  _G.game = {
    surfaces = { nauvis = threat_surface }, forces = { player = alice_force, enemy = enemy },
    get_surface = function(name) return name == "nauvis" and threat_surface or nil end,
    get_player = function(name) if name == "alice" then return { name = "alice", force = alice_force } end end,
  }
  local plan = kinds.plan("threats", params)
  plan.mode = "idle"
  local state = engine.new()
  local id = engine.start(state, "threats", plan.params, 1, plan)
  assert(engine.step(state, id, 1e9, kinds.stepper("threats")))
  return engine.take_page(state, id, 0, 1000, 1e6)
end
local threats_page = run_threats({ caller = "alice", surface = "nauvis", x = 0, y = 0, radius = 500, limit = 5 })
assert(threats_page.total == 2, "two enemy spawners within 500 tiles, got " .. tostring(threats_page.total))
assert(threats_page.nearest[1].distance == 100 and threats_page.nearest[1].direction == "E")
assert(threats_page.nearest[1].pollution == 3)
assert(threats_page.radius == 500 and threats_page.center.surface == "nauvis")
local tb_ok, tb_err = pcall(kinds.plan, "threats", { caller = "alice", surface = "nauvis", x = 0, y = 0, radius = 2000 })
assert(not tb_ok and tb_err.code == "bad_params", "radius above the job bound")

-- defenses_overview: dry turrets of the caller's force over the whole surface, with gps
_G.defines.inventory.turret_ammo = 1
local function dry(x, force)
  return { name = "gun-turret", type = "ammo-turret", position = { x = x, y = 1 }, valid = true, force = force,
    health = 400, max_health = 400,
    get_inventory = function() return { valid = true, get_contents = function() return {} end } end }
end
local def_surface = make_surface({ dry(2), dry(40), dry(70, { name = "enemy" }) }, { { x = 0, y = 0 }, { x = 1, y = 0 }, { x = 2, y = 0 } })
local def_page = run("defenses_overview", { caller = "alice" }, def_surface)
assert(def_page.summary.issues.no_ammo == 2, "two own dry turrets, the enemy one filtered by force")
assert(def_page.by_surface.nauvis.problems == 2)
assert(def_page.problems[1].gps:match("nauvis%]$"))

-- resources: a dense ore field is cut into small areas (no single read of a whole chunk of ore), every
-- tile counted once, patches as in the synchronous command; resources_overview sums per surface
local function ore(name, x, y, amount)
  return { name = name, type = "resource", position = { x = x, y = y }, valid = true, amount = amount,
    prototype = { mineable_properties = { products = { { type = name == "crude-oil" and "fluid" or "item" } } } } }
end
local field = {}
for x = 0, 63 do for y = 0, 31 do field[#field + 1] = ore("iron-ore", x + 0.5, y + 0.5, 10) end end
field[#field + 1] = ore("crude-oil", 300.5, 300.5, 50000)
local reads = {}
local ore_surface = make_surface(field, { { x = 0, y = 0 }, { x = 9, y = 9 } })
-- counting a rich block costs time per entity: every count stops just past the split threshold
local plain_count = ore_surface.count_entities_filtered
ore_surface.count_entities_filtered = function(filter)
  assert(filter.limit and filter.limit <= 301, "count without a limit")
  return math.min(plain_count(filter), filter.limit)
end
local plain_find = ore_surface.find_entities_filtered
ore_surface.find_entities_filtered = function(filter)
  local found = plain_find(filter)
  reads[#reads + 1] = #found
  return found
end
local rp = run("resources", { caller = "alice", surface = "nauvis", x = 32, y = 16, radius = 128, limit = 5 }, ore_surface)
assert(rp.patches_total == 1 and rp.patches[1].name == "iron-ore" and rp.patches[1].tiles == 2048, "every tile once")
assert(rp.patches[1].amount == 20480 and rp.radius == 128 and rp.center.surface == "nauvis")
local biggest = 0
for _, n in ipairs(reads) do if n > biggest then biggest = n end end
assert(biggest <= 300, "no area read holds more than a few hundred tiles, got " .. biggest)
local op = run("resources_overview", { caller = "alice" }, make_surface(field, { { x = 0, y = 0 }, { x = 9, y = 9 } }))
assert(op.summary.resources == 2 and op.total == 2)
assert(op.resources[1].name == "iron-ore" and op.resources[1].tiles == 2048 and op.resources[1].amount == 20480)
assert(op.resources[2].name == "crude-oil" and op.resources[2].wells == 1 and op.resources[2].fluid == true)
for _, bad in ipairs({
  { "resources", { caller = "alice", surface = "nauvis", x = 0, y = 0, radius = 500 } },
  { "resources", { caller = "nobody", surface = "nauvis", x = 0, y = 0, radius = 50 } },
  { "resources_overview", { caller = "nobody" } },
}) do
  local ok, err = pcall(kinds.plan, bad[1], bad[2])
  assert(not ok and type(err) == "table" and err.code, "expected a coded error for " .. bad[1])
end

-- planning takes the chunk bounds from storage when they are known: no walk over every chunk
local walked = false
local known = make_surface(entities, { { x = 0, y = 0 } })
known.index = 1
known.get_chunks = function() walked = true; return function() return nil end end
_G.storage = { mcp_bounds = { [1] = { minx = 0, miny = 0, maxx = 1, maxy = 1 } } }
local _, kplan = run("machines_overview", {}, known)
assert(not walked and kplan.initial_items == 1, "bounds from storage, one block")
_G.storage = {}

print("job_kinds_test ok")
