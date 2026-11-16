-- Reads machines and drills around a point. Only an allowlist of entity types is ever queried:
-- characters, corpses, cars, spiders, boats and anything modded outside the list are never touched,
-- so their contents cannot leak.
local area_group = require("scripts.logic.area_group")
local statuses = require("scripts.statuses")

local M = {}

M.AREA_TYPES = {
  "assembling-machine", "furnace", "lab", "mining-drill", "rocket-silo", "agricultural-tower",
}

local function read(obj, field)
  local ok, value = pcall(function() return obj[field] end)
  if ok then return value end
  return nil
end

-- {name = count} for an inventory (qualities summed), or nil when empty/absent
local function contents(inventory)
  if not inventory then return nil end
  local ok, list = pcall(function() return inventory.get_contents() end)
  if not ok or type(list) ~= "table" then return nil end
  local out, any = {}, false
  for _, entry in ipairs(list) do
    out[entry.name] = (out[entry.name] or 0) + entry.count
    any = true
  end
  if any then return out end
  return nil
end

local function inventory(entity, which)
  local id = defines.inventory[which]
  if id == nil then return nil end
  local ok, inv = pcall(function() return entity.get_inventory(id) end)
  if ok then return inv end
  return nil
end

local function merged(entity, names)
  local out, any = {}, false
  for _, which in ipairs(names) do
    local c = contents(inventory(entity, which))
    if c then
      for name, count in pairs(c) do out[name] = (out[name] or 0) + count end
      any = true
    end
  end
  if any then return out end
  return nil
end

local INPUTS = { "crafter_input", "lab_input", "agricultural_tower_input", "fuel" }
local OUTPUTS = { "crafter_output", "agricultural_tower_output" }

local function enrich(entity_by_unit)
  return function(record)
    local entity = entity_by_unit[record]
    if entity and record.type ~= "mining-drill" then
      record.crafting_progress = read(entity, "crafting_progress")
      local ok, modules = pcall(function() return entity.get_module_inventory() end)
      record.modules = ok and contents(modules) or nil
      record.input = merged(entity, INPUTS)
      record.output = merged(entity, OUTPUTS)
    end
    return record
  end
end

-- surface: LuaSurface-like; center: {x, y}
function M.scan(surface, center, radius, max_listed, budget_bytes)
  local entities = surface.find_entities_filtered({
    position = { x = center.x, y = center.y }, radius = radius, type = M.AREA_TYPES,
  })
  local records, entity_of = {}, {}
  for _, entity in ipairs(entities) do
    local pos = entity.position
    local dx, dy = pos.x - center.x, pos.y - center.y
    local record = {
      name = entity.name, type = entity.type, x = pos.x, y = pos.y,
      dist = math.sqrt(dx * dx + dy * dy), status = statuses.name(read(entity, "status")),
    }
    if entity.type == "mining-drill" then
      local target = read(entity, "mining_target")
      if target then
        record.resource = read(target, "name")
        record.remaining = read(target, "amount")
      end
    else
      local ok, recipe = pcall(function() return entity.get_recipe() end)
      if ok and recipe then record.recipe = recipe.name end
    end
    records[#records + 1] = record
    entity_of[record] = entity
  end
  return area_group.build(records, max_listed, budget_bytes, enrich(entity_of))
end

return M
