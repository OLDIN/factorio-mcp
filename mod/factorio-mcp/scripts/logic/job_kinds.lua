-- The kinds of tick-split job: how to plan the first areas and how to work one area.
-- Only allowlisted entity types are ever queried (see area_scan.AREA_TYPES).
--
-- Method: cut the map into 512-tile blocks, count the allowlisted entities in a block (cheap), skip
-- empty ones, split crowded ones into quarters, and read the entities only of small areas. An empty
-- map costs almost nothing, so a whole base takes seconds instead of minutes.
local area_group = require("scripts.logic.area_group")
local area_scan = require("scripts.logic.area_scan")
local caller = require("scripts.logic.caller")
local power_overview = require("scripts.logic.power_overview")
local engine = require("scripts.logic.job_engine")
local limits = require("scripts.limits")

local M = {}

local CHUNK = 32
local BLOCK = 512 -- first-level area, in tiles

-- Cost model, in work units (about 10 microseconds each, measured on a real base): counting an
-- area costs about as much as the chunks in it (blocks count faster per chunk), reading one entity
-- costs a few units. A crowded area is split until it holds at most SPLIT_COUNT entities.
local COUNT_COST = { [512] = 28, [256] = 7, [128] = 2, [64] = 1, [32] = 0.5 }
local ENTITY_COST = 3
local SPLIT_COUNT = 40

local function bad(message) error({ code = "bad_params", message = message }) end
local function not_found(message) error({ code = "not_found", message = message }) end

-- first-level blocks covering the chunk box [cx0..cx1] x [cy0..cy1] of surface `si`
local function add_blocks(work, si, cx0, cy0, cx1, cy1, keep)
  local per_block = BLOCK / CHUNK
  for bx = math.floor(cx0 / per_block), math.floor(cx1 / per_block) do
    for by = math.floor(cy0 / per_block), math.floor(cy1 / per_block) do
      if not keep or keep(bx * BLOCK, by * BLOCK) then
        work[#work + 1], work[#work + 2], work[#work + 3], work[#work + 4] = si, bx * BLOCK, by * BLOCK, BLOCK
      end
    end
  end
end

local function sorted_surface_names()
  local names = {}
  for name in pairs(game.surfaces) do names[#names + 1] = name end
  table.sort(names)
  return names
end

-- bounding box of a surface's generated chunks, or nil when it has none
local function chunk_bounds(surface)
  local minx, miny, maxx, maxy
  for chunk in surface.get_chunks() do
    local x, y = chunk.x, chunk.y
    if not minx then
      minx, miny, maxx, maxy = x, y, x, y
    else
      if x < minx then minx = x elseif x > maxx then maxx = x end
      if y < miny then miny = y elseif y > maxy then maxy = y end
    end
  end
  return minx, miny, maxx, maxy
end

-- Surfaces to scan (all, or the listed ones each once) and their first-level blocks.
local function plan_surfaces(params)
  local names = params.surfaces
  if names == nil then
    names = sorted_surface_names()
  else
    if type(names) ~= "table" then bad("surfaces must be a list of names") end
    local seen, unique = {}, {}
    for _, name in ipairs(names) do
      if type(name) ~= "string" then bad("surfaces must be a list of names") end
      if not game.get_surface(name) then not_found("no such surface: " .. name) end
      -- a repeated name would multiply the work: count every surface once
      if not seen[name] then
        seen[name] = true
        unique[#unique + 1] = name
      end
    end
    names = unique
  end
  local work, covered = {}, 0
  for index, name in ipairs(names) do
    local surface = game.get_surface(name)
    if surface then
      local minx, miny, maxx, maxy = chunk_bounds(surface)
      if minx then
        covered = covered + (maxx - minx + 1) * (maxy - miny + 1)
        if covered > limits.MAX_JOB_CHUNKS then
          bad("map too large for one job (limit " .. limits.MAX_JOB_CHUNKS .. " chunks): ask for fewer surfaces")
        end
        add_blocks(work, index, minx, miny, maxx, maxy)
      end
    end
  end
  return names, work
end

local function plan_overview(params)
  local names, work = plan_surfaces(params)
  return { surfaces = names, work = work, acc = { machines = 0, working = 0, groups = {} } }
end

local POWER_TYPES = { "electric-pole", "accumulator" }
for _, t in ipairs(area_scan.AREA_TYPES) do POWER_TYPES[#POWER_TYPES + 1] = t end

local function plan_power_overview(params)
  local force = caller.force(params)
  local names, work = plan_surfaces(params)
  return {
    surfaces = names, work = work, acc = power_overview.new_acc(),
    params = { force = force.name, limit = params.limit or 5 },
  }
end

local function number(params, key)
  local v = params[key]
  if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then
    bad(key .. " must be a finite number")
  end
  return v
end

local function plan_area(params)
  if type(params.surface) ~= "string" then bad("surface is required") end
  local surface = game.get_surface(params.surface)
  if not surface then not_found("no such surface") end
  local x, y, radius = number(params, "x"), number(params, "y"), number(params, "radius")
  if radius <= 0 or radius > limits.MAX_JOB_AREA_RADIUS then
    bad("radius must be between 0 and " .. limits.MAX_JOB_AREA_RADIUS)
  end
  local max_listed = params.max_listed or 20
  if type(max_listed) ~= "number" or max_listed < 1 or max_listed ~= math.floor(max_listed) then
    bad("max_listed must be a positive integer")
  end
  local work = {}
  add_blocks(work, 1, math.floor((x - radius) / CHUNK), math.floor((y - radius) / CHUNK),
    math.floor((x + radius) / CHUNK), math.floor((y + radius) / CHUNK),
    function(bx, by)
      -- skip blocks whose square cannot touch the circle
      local nx = math.max(bx, math.min(x, bx + BLOCK))
      local ny = math.max(by, math.min(y, by + BLOCK))
      return (nx - x) ^ 2 + (ny - y) ^ 2 <= radius ^ 2
    end)
  return {
    surfaces = { params.surface }, work = work, acc = area_group.new(max_listed),
    params = { surface = params.surface, x = x, y = y, radius = radius },
  }
end

local planners = { machines_overview = plan_overview, area = plan_area, power_overview = plan_power_overview }

function M.known(kind)
  return planners[kind] ~= nil
end

-- Returns {surfaces, work, acc, params?}; raises {code, message} for bad input.
function M.plan(kind, params)
  local planner = planners[kind]
  if not planner then bad("unknown job kind: " .. tostring(kind)) end
  return planner(params or {})
end

-- Work one square area. `take(job, entity)` handles an entity found in it. Returns cost, split.
-- An entity belongs to the area its position lies in (half-open square), so it is read once even
-- when its collision box touches a neighbour.
-- `filter` holds the allowlisted `type` list and, optionally, a `force` name.
local function scan_area(job, si, x0, y0, size, take, filter)
  local surface = game.get_surface(job.surfaces[si])
  if not surface or not surface.valid then return 1, false end
  local query = { area = { { x0, y0 }, { x0 + size, y0 + size } }, type = filter.type, force = filter.force }
  local cost = COUNT_COST[size] or 1
  local count = surface.count_entities_filtered(query)
  if count == 0 then return cost, false end
  if count > SPLIT_COUNT and size > engine.TILE then
    engine.split(job, si, x0, y0, size)
    return cost, true
  end
  local found = surface.find_entities_filtered(query)
  local x1, y1 = x0 + size, y0 + size
  for _, entity in ipairs(found) do
    if entity.valid then
      local pos = entity.position
      if pos.x >= x0 and pos.x < x1 and pos.y >= y0 and pos.y < y1 then take(job, entity) end
    end
  end
  return cost + 1 + #found * ENTITY_COST, false
end

local EXAMPLES = 3
local MACHINES = { type = area_scan.AREA_TYPES }

local overview = {}

local function overview_take(job, entity)
  local ok, r = pcall(area_scan.record_of, entity, nil)
  if not ok then return end
  local acc = job.acc
  local surface_name = job.current_surface
  local key = surface_name .. "|" .. r.name .. "|" .. (r.recipe or "")
  local g = acc.groups[key]
  if not g then
    g = { surface = surface_name, name = r.name, recipe = r.recipe, count = 0, working = 0, by_status = {}, examples = {} }
    acc.groups[key] = g
  end
  acc.machines = acc.machines + 1
  g.count = g.count + 1
  g.by_status[r.status] = (g.by_status[r.status] or 0) + 1
  if r.status == "working" then
    acc.working = acc.working + 1
    g.working = g.working + 1
  elseif #g.examples < EXAMPLES then
    g.examples[#g.examples + 1] = { x = r.x, y = r.y, status = r.status }
  end
end

function overview.work(job, si, x0, y0, size)
  job.current_surface = job.surfaces[si]
  return scan_area(job, si, x0, y0, size, overview_take, MACHINES)
end

function overview.finish(job)
  job.current_surface = nil
  local list = {}
  for _, g in pairs(job.acc.groups) do list[#list + 1] = g end
  table.sort(list, function(a, b)
    if a.count ~= b.count then return a.count > b.count end
    if a.surface ~= b.surface then return a.surface < b.surface end
    if a.name ~= b.name then return a.name < b.name end
    return (a.recipe or "") < (b.recipe or "")
  end)
  return {
    fields = { summary = { machines = job.acc.machines, working = job.acc.working, groups = #list, surfaces = #job.surfaces } },
    list_name = "groups", list = list,
  }
end

local area = {}

local function area_take(job, entity)
  local p = job.params
  local pos = entity.position
  if (pos.x - p.x) ^ 2 + (pos.y - p.y) ^ 2 <= p.radius ^ 2 then
    local ok, record = pcall(area_scan.record_of, entity, p)
    if ok then area_group.add(job.acc, record) end
  end
end

function area.work(job, si, x0, y0, size)
  return scan_area(job, si, x0, y0, size, area_take, MACHINES)
end

function area.finish(job)
  local p = job.params
  local surface = game.get_surface(p.surface)
  local enrich = surface and area_scan.enricher_by_position(surface) or nil
  local result = area_group.finish(job.acc, limits.RESPONSE_BUDGET_BYTES - 500, enrich)
  result.center = { surface = p.surface, x = p.x, y = p.y }
  result.radius = p.radius
  return { fields = result }
end

local power = {}

function power.work(job, si, x0, y0, size)
  local surface_name = job.surfaces[si]
  return scan_area(job, si, x0, y0, size, function(j, entity) power_overview.take(j.acc, entity, surface_name) end,
    { type = POWER_TYPES, force = job.params.force })
end

function power.finish(job)
  local out = power_overview.finish(job.acc, job.params.limit)
  return { fields = { summary = out.summary }, list_name = "networks", list = out.list }
end

local steppers = { machines_overview = overview, area = area, power_overview = power }

function M.stepper(kind)
  return steppers[kind]
end

return M
