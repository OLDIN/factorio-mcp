-- Military and defensive structures: turrets (ammo, electric, fluid, artillery), walls, gates,
-- land mines, radars. Checks supply (ammo, energy, fluid) and damage.
--
-- Two ways in: `M.scan` for an area around a point (one tick), and `M.record`/`M.new_acc`/
-- `M.add`/`M.finish` for the whole-base job, which feeds entities block by block. The accumulator
-- holds plain data only, so it can live in a job in `storage`.
local geo = require("scripts.logic.geo")

local M = {}

M.DEFENSE_TYPES = {
  "ammo-turret",
  "electric-turret",
  "fluid-turret",
  "turret",
  "artillery-turret",
  "wall",
  "gate",
  "land-mine",
  "radar",
}

local function read(obj, field)
  local ok, val = pcall(function() return obj[field] end)
  if ok then return val end
  return nil
end

local function is_turret_type(etype)
  return etype == "ammo-turret" or etype == "electric-turret" or etype == "fluid-turret"
    or etype == "turret" or etype == "artillery-turret"
end

local function is_wall_type(etype)
  return etype == "wall" or etype == "gate"
end

-- Worms are type "turret" on the enemy force; neutral entities are map decoration.
-- Neither is part of anyone's defense, so they are skipped.
local function is_hostile_or_neutral(entity)
  local force = read(entity, "force")
  if not force then return false end
  local fname = read(force, "name")
  return fname == "enemy" or fname == "neutral"
end

local function ammo_of(entity, etype)
  local inv_id = defines.inventory.turret_ammo
  if etype == "artillery-turret" and defines.inventory.artillery_turret_ammo then
    inv_id = defines.inventory.artillery_turret_ammo
  end
  local ok, inv = pcall(function() return entity.get_inventory(inv_id) end)
  local count, dict = 0, nil
  if ok and inv and inv.valid then
    local ok_c, cont = pcall(function() return inv.get_contents() end)
    if ok_c and type(cont) == "table" then
      dict = {}
      for _, item in ipairs(cont) do
        count = count + item.count
        dict[item.name] = (dict[item.name] or 0) + item.count
      end
    end
  end
  return count, dict
end

local function fluid_of(entity)
  local ok, cont = pcall(function() return entity.get_fluid_contents() end)
  local amount, dict = 0, nil
  if ok and type(cont) == "table" then
    dict = {}
    for fname, amt in pairs(cont) do
      amount = amount + amt
      dict[fname] = (dict[fname] or 0) + amt
    end
  end
  return amount, dict
end

-- One entity -> plain record, or nil when it is invalid or not part of anyone's defense.
function M.record(entity)
  if not entity.valid or is_hostile_or_neutral(entity) then return nil end
  local etype = entity.type
  local pos = entity.position
  local health = read(entity, "health") or 0
  local max_health = read(entity, "max_health") or 0
  local r = {
    name = entity.name, type = etype, x = pos.x, y = pos.y, health = health, max_health = max_health,
    damaged = max_health > 0 and health < max_health,
    is_turret = is_turret_type(etype), is_wall = is_wall_type(etype),
  }
  if etype == "ammo-turret" or etype == "artillery-turret" or etype == "turret" then
    r.ammo, r.ammo_dict = ammo_of(entity, etype)
    if r.ammo == 0 then r.issue = "no_ammo" end
  elseif etype == "electric-turret" or etype == "radar" then
    if (read(entity, "energy") or 0) <= 0 then r.issue = "no_power" end
  elseif etype == "fluid-turret" then
    r.fluid, r.fluid_dict = fluid_of(entity)
    if r.fluid <= 0 then r.issue = "no_fluid" end
  end
  return r
end

-- keep: how many problems to list in the end
function M.new_acc(keep)
  return {
    keep = keep, total = 0, turrets = 0, walls = 0, other = 0,
    issues = { no_ammo = 0, no_power = 0, no_fluid = 0, damaged = 0 },
    groups = {}, candidates = {}, problems_total = 0, by_surface = {},
  }
end

local function priority(r)
  if r.is_turret and r.issue then return 1 end
  if r.is_turret and r.damaged then return 2 end
  if r.is_wall and r.damaged then return 3 end
  return 4
end

local function worse(a, b)
  if a.priority ~= b.priority then return a.priority < b.priority end
  return a.health < b.health
end

local function trim(acc)
  table.sort(acc.candidates, worse)
  for i = #acc.candidates, acc.keep + 1, -1 do acc.candidates[i] = nil end
end

-- `surface_name` (optional) adds per-surface counts and a gps tag to listed problems.
function M.add(acc, r, surface_name)
  if not r then return end
  acc.total = acc.total + 1
  if r.is_turret then acc.turrets = acc.turrets + 1
  elseif r.is_wall then acc.walls = acc.walls + 1
  else acc.other = acc.other + 1 end
  if r.issue then acc.issues[r.issue] = acc.issues[r.issue] + 1 end
  if r.damaged then acc.issues.damaged = acc.issues.damaged + 1 end

  local g = acc.groups[r.name]
  if not g then
    g = { name = r.name, type = r.type, count = 0, ready = 0, damaged = 0 }
    acc.groups[r.name] = g
  end
  g.count = g.count + 1
  if r.damaged then g.damaged = g.damaged + 1 end
  if not r.issue then g.ready = g.ready + 1 end
  if r.ammo_dict then
    g.ammo = g.ammo or {}
    for k, v in pairs(r.ammo_dict) do g.ammo[k] = (g.ammo[k] or 0) + v end
  end
  if r.fluid_dict then
    g.fluids = g.fluids or {}
    for k, v in pairs(r.fluid_dict) do g.fluids[k] = (g.fluids[k] or 0) + v end
  end

  local bs = nil
  if surface_name then
    bs = acc.by_surface[surface_name] or { total = 0, problems = 0 }
    acc.by_surface[surface_name] = bs
    bs.total = bs.total + 1
  end
  if r.issue or r.damaged then
    acc.problems_total = acc.problems_total + 1
    if bs then bs.problems = bs.problems + 1 end
    local item = {
      priority = priority(r), name = r.name, type = r.type, x = r.x, y = r.y,
      issue = r.issue or "damaged", health = math.floor(r.health), max_health = math.floor(r.max_health),
      ammo = r.ammo, fluid = r.fluid and math.floor(r.fluid) or nil,
    }
    if surface_name then
      item.surface = surface_name
      item.gps = geo.gps(surface_name, r.x, r.y)
    end
    acc.candidates[#acc.candidates + 1] = item
    if #acc.candidates > acc.keep * 4 + 16 then trim(acc) end
  end
end

function M.finish(acc)
  local groups = {}
  for _, g in pairs(acc.groups) do groups[#groups + 1] = g end
  table.sort(groups, function(a, b)
    if a.count ~= b.count then return a.count > b.count end
    return a.name < b.name
  end)
  trim(acc)
  local problems = {}
  for i, item in ipairs(acc.candidates) do
    item.priority = nil -- internal
    problems[i] = item
  end
  return {
    summary = {
      total = acc.total, turrets = acc.turrets, walls = acc.walls, other = acc.other, issues = acc.issues,
    },
    groups = groups,
    problems = problems,
    problems_total = acc.problems_total,
    by_surface = acc.by_surface,
  }
end

function M.scan(surface, center, radius, max_listed)
  local entities = surface.find_entities_filtered({
    position = { x = center.x, y = center.y },
    radius = radius,
    type = M.DEFENSE_TYPES,
  })
  local acc = M.new_acc(max_listed)
  for _, entity in ipairs(entities) do
    M.add(acc, M.record(entity))
  end
  local out = M.finish(acc)
  out.by_surface = nil
  return out
end

return M
