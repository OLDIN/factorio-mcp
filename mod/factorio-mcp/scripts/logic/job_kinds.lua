-- The kinds of tick-split job: how to plan the chunk list and how to process one chunk.
-- Only allowlisted entity types are ever queried (see area_scan.AREA_TYPES).
local area_group = require("scripts.logic.area_group")
local area_scan = require("scripts.logic.area_scan")
local limits = require("scripts.limits")

local M = {}

local CHUNK = 32

local function bad(message) error({ code = "bad_params", message = message }) end
local function not_found(message) error({ code = "not_found", message = message }) end

local function add_all_chunks(surface, index, out)
  for chunk in surface.get_chunks() do
    out[#out + 1] = index
    out[#out + 1] = chunk.x
    out[#out + 1] = chunk.y
  end
end

local function sorted_surface_names()
  local names = {}
  for name in pairs(game.surfaces) do names[#names + 1] = name end
  table.sort(names)
  return names
end

local function plan_overview(params)
  local names = params.surfaces
  if names == nil then
    names = sorted_surface_names()
  else
    if type(names) ~= "table" then bad("surfaces must be a list of names") end
    for _, name in ipairs(names) do
      if type(name) ~= "string" then bad("surfaces must be a list of names") end
      if not game.get_surface(name) then not_found("no such surface: " .. name) end
    end
  end
  local chunks = {}
  for index, name in ipairs(names) do
    local surface = game.get_surface(name)
    if surface then add_all_chunks(surface, index, chunks) end
  end
  return { surfaces = names, chunks = chunks, acc = { machines = 0, working = 0, groups = {} } }
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
  local chunks = {}
  for cx = math.floor((x - radius) / CHUNK), math.floor((x + radius) / CHUNK) do
    for cy = math.floor((y - radius) / CHUNK), math.floor((y + radius) / CHUNK) do
      -- skip chunks whose square cannot touch the circle
      local nx = math.max(cx * CHUNK, math.min(x, cx * CHUNK + CHUNK))
      local ny = math.max(cy * CHUNK, math.min(y, cy * CHUNK + CHUNK))
      local ok, generated = pcall(function() return surface.is_chunk_generated({ cx, cy }) end)
      if (nx - x) ^ 2 + (ny - y) ^ 2 <= radius ^ 2 and (not ok or generated) then
        chunks[#chunks + 1] = 1
        chunks[#chunks + 1] = cx
        chunks[#chunks + 1] = cy
      end
    end
  end
  return {
    surfaces = { params.surface }, chunks = chunks, acc = area_group.new(max_listed),
    params = { surface = params.surface, x = x, y = y, radius = radius },
  }
end

local planners = { machines_overview = plan_overview, area = plan_area }

function M.known(kind)
  return planners[kind] ~= nil
end

-- Returns {surfaces, chunks, acc, params?}; raises {code, message} for bad input.
function M.plan(kind, params)
  local planner = planners[kind]
  if not planner then bad("unknown job kind: " .. tostring(kind)) end
  return planner(params or {})
end

-- Allowlisted entities of one chunk whose position lies in the chunk's half-open square, so an
-- entity on a border is counted exactly once.
local function each_entity_in_chunk(job, si, cx, cy, fn)
  local surface = game.get_surface(job.surfaces[si])
  if not surface or not surface.valid then return end
  local x0, y0 = cx * CHUNK, cy * CHUNK
  local found = surface.find_entities_filtered({
    area = { { x0, y0 }, { x0 + CHUNK, y0 + CHUNK } }, type = area_scan.AREA_TYPES,
  })
  for _, entity in ipairs(found) do
    if entity.valid then
      local pos = entity.position
      if pos.x >= x0 and pos.x < x0 + CHUNK and pos.y >= y0 and pos.y < y0 + CHUNK then fn(entity) end
    end
  end
end

local EXAMPLES = 3

local overview = {}

function overview.chunk(job, si, cx, cy)
  local acc, surface_name = job.acc, job.surfaces[si]
  each_entity_in_chunk(job, si, cx, cy, function(entity)
    local r = area_scan.record_of(entity, nil)
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
  end)
end

function overview.finish(job)
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

function area.chunk(job, si, cx, cy)
  local p = job.params
  each_entity_in_chunk(job, si, cx, cy, function(entity)
    local pos = entity.position
    if (pos.x - p.x) ^ 2 + (pos.y - p.y) ^ 2 <= p.radius ^ 2 then
      area_group.add(job.acc, area_scan.record_of(entity, p))
    end
  end)
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

local steppers = { machines_overview = overview, area = area }

function M.stepper(kind)
  return steppers[kind]
end

return M
