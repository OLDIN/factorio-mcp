package.path = "factorio-mcp/?.lua;tests/?.lua;" .. package.path
local env = require("support.env")
env.fresh()
_G.defines = { entity_status = { working = 1, no_ingredients = 2 }, inventory = {} }
local engine = require("scripts.logic.job_engine")
local kinds = require("scripts.logic.job_kinds")
local area_scan = require("scripts.logic.area_scan")

local function machine(name, x, y, status, recipe)
  return {
    name = name, type = "assembling-machine", position = { x = x, y = y }, status = status, valid = true,
    get_recipe = function() return { name = recipe } end,
  }
end
local entities = {
  machine("asm", 5, 5, 1, "gear"), machine("asm", 31.9, 5, 2, "gear"), machine("asm", 32, 5, 2, "gear"),
  machine("asm", 40, 40, 2, "plate"),
}
local queried = {}
local surface = {
  valid = true, name = "nauvis",
  get_chunks = function()
    local list = { { x = 0, y = 0 }, { x = 1, y = 0 }, { x = 1, y = 1 } }
    local i = 0
    return function() i = i + 1; return list[i] end
  end,
  is_chunk_generated = function() return true end,
  find_entities_filtered = function(filter)
    queried[#queried + 1] = filter
    -- like the game: anything overlapping the box, so border entities can come back for two chunks
    local out = {}
    local a = filter.area
    for _, e in ipairs(entities) do
      if e.position.x >= a[1][1] - 1 and e.position.x <= a[2][1] and e.position.y >= a[1][2] - 1 and e.position.y <= a[2][2] then
        out[#out + 1] = e
      end
    end
    return out
  end,
}
_G.game = { surfaces = { nauvis = surface }, get_surface = function(name) return name == "nauvis" and surface or nil end }

-- overview over all chunks: every machine is counted exactly once, even on chunk borders
local plan = kinds.plan("machines_overview", {})
plan.mode = "idle"
local state = engine.new()
local id = engine.start(state, "machines_overview", {}, 1, plan)
assert(engine.step(state, id, 100, kinds.stepper("machines_overview")))
local page = engine.take_page(state, id, 0, 100, 100000)
assert(page.summary.machines == 4 and page.summary.working == 1, "got " .. page.summary.machines)
assert(#page.groups == 2 and page.groups[1].recipe == "gear" and page.groups[1].count == 3)
assert(#page.groups[1].examples == 2)
for _, f in ipairs(queried) do
  assert(type(f.type) == "table" and f.position == nil and f.area, "allowlisted type filter on every query")
end

-- area job: only machines inside the radius
plan = kinds.plan("area", { surface = "nauvis", x = 5, y = 5, radius = 26.95 })
plan.mode = "idle"
id = engine.start(state, "area", plan.params, 1, plan)
assert(engine.step(state, id, 100, kinds.stepper("area")))
page = engine.take_page(state, id, 0, 100, 100000)
assert(page.totals.machines == 2 and page.radius == 26.95 and page.center.surface == "nauvis")

-- bad input
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

print("job_kinds_test ok")
