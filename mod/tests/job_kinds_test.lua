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
      local force_ok = filter.force == nil or (e.force and e.force.name or "player") == filter.force
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

print("job_kinds_test ok")
