-- Mining drills: how much ore is left in each drill's reach, which drills are depleted or running low.
-- Records are plain tables {name, resource, remaining, depleted, low, infinite, x, y}; `remaining` is the
-- ore (amount) in the drill's square mining area, or, for an infinite resource such as crude oil, the
-- yield in percent of the starting amount. The accumulator is plain data (a job keeps it in storage).
local geo = require("scripts.logic.geo")

local M = {}

M.LOW_REMAINING = 5000 -- ore left in reach below which a drill counts as running low
M.LOW_YIELD = 20 -- yield percent below which an infinite resource counts as running low

local function read(entity, surface)
  if not entity.valid then return nil end
  local target = entity.mining_target
  if target ~= nil and not target.valid then target = nil end
  local pos = entity.position
  local depleted = target == nil or entity.status == defines.entity_status.no_minable_resources
  local record = {
    name = entity.name, resource = target and target.name or nil, remaining = 0, depleted = depleted,
    infinite = false, x = pos.x, y = pos.y,
  }
  if target ~= nil then
    local proto = target.prototype
    if proto.infinite_resource then
      record.infinite = true
      local normal = proto.normal_resource_amount
      record.remaining = normal > 0 and math.floor(target.amount / normal * 100 + 0.5) or 0
    else
      local r = entity.prototype.mining_drill_radius
      local sum = 0
      for _, resource in ipairs(surface.find_entities_filtered({
        name = target.name, area = { { pos.x - r, pos.y - r }, { pos.x + r, pos.y + r } } })) do
        sum = sum + resource.amount
      end
      record.remaining = sum
    end
  end
  if record.infinite then
    record.low = depleted or record.remaining < M.LOW_YIELD
  else
    record.low = depleted or record.remaining < M.LOW_REMAINING
  end
  return record
end

-- One drill as a record, or nil when it cannot be read (invalid, or a field raised).
function M.record(entity, surface)
  local ok, record = pcall(read, entity, surface)
  if ok then return record end
  return nil
end

function M.new_acc(keep)
  return { keep = keep, drills = 0, depleted = 0, low = 0, groups = {}, candidates = {} }
end

-- depleted first, then finite drills by ore left, then infinite ones by yield
local function worse(a, b)
  if a.depleted ~= b.depleted then return a.depleted end
  if a.infinite ~= b.infinite then return not a.infinite end
  if a.remaining ~= b.remaining then return a.remaining < b.remaining end
  if a.x ~= b.x then return a.x < b.x end
  return a.y < b.y
end

local function trim(acc)
  table.sort(acc.candidates, worse)
  for i = #acc.candidates, acc.keep + 1, -1 do acc.candidates[i] = nil end
end

function M.add(acc, record, surface_name)
  acc.drills = acc.drills + 1
  local resource = record.resource or "unknown"
  local key = surface_name .. "|" .. resource
  local g = acc.groups[key]
  if not g then
    g = { surface = surface_name, resource = resource, drills = 0, depleted = 0, low = 0, ore_in_reach = 0,
      infinite = record.infinite }
    acc.groups[key] = g
  end
  g.drills = g.drills + 1
  if not record.infinite then g.ore_in_reach = g.ore_in_reach + record.remaining end
  if record.depleted then
    acc.depleted = acc.depleted + 1
    g.depleted = g.depleted + 1
  end
  if record.low then
    acc.low = acc.low + 1
    g.low = g.low + 1
    local c = {}
    for k, v in pairs(record) do c[k] = v end
    c.surface = surface_name
    acc.candidates[#acc.candidates + 1] = c
    -- a big base: keep the candidate list bounded between trims
    if #acc.candidates > 4 * acc.keep + 16 then trim(acc) end
  end
end

function M.finish(acc)
  trim(acc)
  local worst = {}
  for i, c in ipairs(acc.candidates) do
    worst[i] = {
      surface = c.surface, name = c.name, resource = c.resource or "unknown", remaining = c.remaining,
      depleted = c.depleted, infinite = c.infinite, gps = geo.gps(c.surface, c.x, c.y),
    }
  end
  local groups = {}
  for _, g in pairs(acc.groups) do
    if g.infinite then g.ore_in_reach = nil end
    groups[#groups + 1] = g
  end
  table.sort(groups, function(a, b)
    if a.depleted ~= b.depleted then return a.depleted > b.depleted end
    if a.low ~= b.low then return a.low > b.low end
    if a.drills ~= b.drills then return a.drills > b.drills end
    if a.surface ~= b.surface then return a.surface < b.surface end
    return a.resource < b.resource
  end)
  return { summary = { drills = acc.drills, depleted = acc.depleted, low = acc.low }, groups = groups, worst = worst }
end

return M
