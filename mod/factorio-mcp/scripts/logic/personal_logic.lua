-- The caller's own inventory and alerts. Callers pass the player named by the service's token;
-- nothing here takes a player from the person's words.
local geo = require("scripts.logic.geo")

local M = {}

local function items_of(inv)
  if not inv or not inv.valid then return {} end
  local list = {}
  for _, it in ipairs(inv.get_contents()) do list[#list + 1] = { name = it.name, quality = it.quality, count = it.count } end
  table.sort(list, function(a, b)
    if a.count ~= b.count then return a.count > b.count end
    return a.name < b.name
  end)
  return list
end

local function safe(fn, ...)
  local ok, v = pcall(fn, ...)
  if ok then return v end
  return nil
end

local function armor_of(player)
  local inv = safe(player.get_inventory, defines.inventory.character_armor)
  if not inv or not inv.valid then return nil end
  local stack = inv[1]
  if not stack or not stack.valid_for_read then return nil end
  local equipment = {}
  if stack.grid then
    for _, e in ipairs(stack.grid.get_contents()) do equipment[#equipment + 1] = { name = e.name, count = e.count } end
  end
  return { name = stack.name, equipment = equipment }
end

function M.inventory(player)
  local online = player.connected
  local main = safe(player.get_main_inventory)
  if not main or not main.valid then return { online = online, readable = false } end
  local guns = {}
  for i, g in ipairs(items_of(safe(player.get_inventory, defines.inventory.character_guns))) do guns[i] = g.name end
  return {
    online = online, readable = true,
    main = items_of(main),
    armor = armor_of(player),
    guns = guns,
    ammo = items_of(safe(player.get_inventory, defines.inventory.character_ammo)),
    crafting_queue_size = player.crafting_queue_size,
  }
end

local function type_names()
  local out = {}
  for name, v in pairs(defines.alert_type) do out[v] = name end
  return out
end

-- `alerts` = player.get_alerts{} (surface index -> alert type -> [Alert]); `surfaces` = game.surfaces
function M.alerts(alerts, surfaces, limit)
  local names = type_names()
  local by_type = {}
  for surface_index, per_type in pairs(alerts) do
    local surface = surfaces[surface_index]
    local surface_name = surface and surface.name or tostring(surface_index)
    for t, list in pairs(per_type) do
      local name = names[t] or tostring(t)
      local g = by_type[name]
      if not g then
        g = { type = name, count = 0, examples = {} }
        by_type[name] = g
      end
      for _, alert in ipairs(list) do
        g.count = g.count + 1
        if #g.examples < limit then
          local target = alert.target
          local pos = alert.position or (target and target.position)
          g.examples[#g.examples + 1] = {
            name = (target and target.name) or (alert.prototype and alert.prototype.name) or nil,
            gps = pos and geo.gps(surface_name, pos.x, pos.y) or nil,
          }
        end
      end
    end
  end
  local out = {}
  for _, g in pairs(by_type) do out[#out + 1] = g end
  table.sort(out, function(a, b)
    if a.count ~= b.count then return a.count > b.count end
    return a.type < b.type
  end)
  return { by_type = out }
end

return M
