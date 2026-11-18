-- Enemy structures around a point: counts by name and the nearest ones with distance, compass
-- direction, [gps] and (for spawners) the pollution of their chunk. The accumulator holds plain
-- data only, so it can live in a tick-split job in `storage`.
local geo = require("scripts.logic.geo")

local M = {}

-- worms are type "turret" on an enemy force; Gleba's egg rafts are unit spawners too
M.ENEMY_TYPES = { "unit-spawner", "turret" }

function M.enemy_force_names(force, forces)
  local out = {}
  for name, other in pairs(forces) do
    if other.name ~= force.name and force.is_enemy(other) then out[#out + 1] = name end
  end
  return out
end

-- an enemy entity -> plain record; spawners carry the pollution of their chunk
function M.record(entity, surface)
  local pos = entity.position
  local rec = { name = entity.name, type = entity.type, x = pos.x, y = pos.y }
  if entity.type == "unit-spawner" then rec.pollution = surface.get_pollution(pos) end
  return rec
end

-- add every segmented unit (demolishers) of the surface; a game without them answers nothing
function M.add_surface_units(acc, surface, enemy_list, radius)
  local set = {}
  for _, name in ipairs(enemy_list) do set[name] = true end
  local ok, units = pcall(surface.get_segmented_units)
  if ok and units then M.add_segmented(acc, units, set, radius) end
end

function M.new_acc(center, surface_name, limit)
  return { center = { x = center.x, y = center.y }, surface = surface_name, limit = limit, total = 0, counts = {}, nearest = {} }
end

-- rec = {name, type, x, y, pollution?}
function M.add(acc, rec)
  acc.total = acc.total + 1
  acc.counts[rec.name] = (acc.counts[rec.name] or 0) + 1
  local d = geo.distance(acc.center, rec)
  local list = acc.nearest
  if #list >= acc.limit and d >= list[#list].d then return end
  local item = { d = d, name = rec.name, type = rec.type, x = rec.x, y = rec.y, pollution = rec.pollution }
  local i = #list + 1
  while i > 1 and list[i - 1].d > d do
    list[i] = list[i - 1]
    i = i - 1
  end
  list[i] = item
  if #list > acc.limit then list[#list] = nil end
end

-- demolishers and other segmented units of the enemy forces within `radius`, by their head
function M.add_segmented(acc, units, enemy_names, radius)
  for _, u in ipairs(units) do
    if u.valid and enemy_names[u.force.name] then
      local head = u.segments[1]
      if head then
        local pos = head.position
        if geo.distance(acc.center, pos) <= radius then
          M.add(acc, { name = u.prototype.name, type = "segmented-unit", x = pos.x, y = pos.y })
        end
      end
    end
  end
end

function M.finish(acc)
  local nearest = {}
  for i, n in ipairs(acc.nearest) do
    nearest[i] = {
      name = n.name, type = n.type,
      distance = math.floor(n.d + 0.5),
      direction = geo.direction(acc.center, n),
      gps = geo.gps(acc.surface, n.x, n.y),
      pollution = n.pollution and math.floor(n.pollution * 10 + 0.5) / 10 or nil,
    }
  end
  return { total = acc.total, counts = acc.counts, nearest = nearest }
end

return M
