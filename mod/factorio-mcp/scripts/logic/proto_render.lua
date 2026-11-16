-- Pure rendering of prototype objects into plain JSON-able tables, plus the per-kind name lists.
-- Every attribute read goes through `read`, which tolerates attributes a prototype type lacks.
local M = {}

local function read(obj, field)
  local ok, value = pcall(function() return obj[field] end)
  if ok then return value end
  return nil
end

-- Method call that tolerates failure. Quality is required in practice (2.1.24 rejects a missing
-- one with "Invalid QualityID"), so callers pass "normal": values are for normal quality.
local function call(obj, method, ...)
  -- Factorio methods are bound: call them as obj.method(args), without passing obj again.
  local ok, value = pcall(function(...) return obj[method](...) end, ...)
  if ok then return value end
  return nil
end

local function sorted_keys(dict, only_true)
  local out = {}
  if type(dict) == "table" then
    for k, v in pairs(dict) do
      if not only_true or v == true then out[#out + 1] = tostring(k) end
    end
  end
  table.sort(out)
  return out
end

-- copy only scalar fields (strings, numbers, booleans) of a table
local function scalars(t)
  local out = {}
  if type(t) == "table" then
    for k, v in pairs(t) do
      local tv = type(v)
      if tv == "string" or tv == "number" or tv == "boolean" then out[k] = v end
    end
  end
  return out
end

local function array_of_scalars(list)
  local out = {}
  if type(list) == "table" then
    for i = 1, #list do out[i] = scalars(list[i]) end
  end
  return out
end

local function name_of(obj)
  if obj == nil then return nil end
  return read(obj, "name")
end

local function nonempty(dict)
  return type(dict) == "table" and next(dict) ~= nil
end

function M.recipe(p)
  return {
    name = p.name,
    categories = read(p, "categories") or {},
    energy = read(p, "energy"),
    enabled = read(p, "enabled"),
    hidden = read(p, "hidden"),
    ingredients = array_of_scalars(read(p, "ingredients")),
    products = array_of_scalars(read(p, "products")),
    surface_conditions = array_of_scalars(read(p, "surface_conditions")),
    maximum_productivity = read(p, "maximum_productivity"),
  }
end

function M.is_machine(p)
  return nonempty(read(p, "crafting_categories")) or nonempty(read(p, "resource_categories"))
    or nonempty(read(p, "lab_inputs"))
end

function M.machine(p)
  return {
    name = p.name,
    type = read(p, "type"),
    crafting_categories = sorted_keys(read(p, "crafting_categories"), true),
    crafting_speed = call(p, "get_crafting_speed", "normal"),
    module_slots = read(p, "module_inventory_size"),
    allowed_effects = sorted_keys(read(p, "allowed_effects"), true),
    energy_usage = read(p, "energy_usage"),
    ingredient_count = read(p, "ingredient_count"),
    mining_speed = read(p, "mining_speed"),
    resource_categories = sorted_keys(read(p, "resource_categories"), true),
    lab_inputs = read(p, "lab_inputs") or {},
    max_health = call(p, "get_max_health", "normal"),
  }
end

function M.item(p)
  return {
    name = p.name,
    type = read(p, "type"),
    stack_size = read(p, "stack_size"),
    fuel_value = read(p, "fuel_value"),
    fuel_categories = sorted_keys(read(p, "fuel_categories"), true),
    place_result = name_of(read(p, "place_result")),
    spoil_result = name_of(read(p, "spoil_result")),
    hidden = read(p, "hidden"),
  }
end

function M.is_module(p)
  return read(p, "type") == "module"
end

function M.module(p)
  return {
    name = p.name,
    category = read(p, "category"),
    tier = read(p, "tier"),
    effects = scalars(read(p, "module_effects")),
    stack_size = read(p, "stack_size"),
    hidden = read(p, "hidden"),
  }
end

function M.fluid(p)
  return {
    name = p.name,
    default_temperature = read(p, "default_temperature"),
    max_temperature = read(p, "max_temperature"),
    fuel_value = read(p, "fuel_value"),
    heat_capacity = read(p, "heat_capacity"),
    hidden = read(p, "hidden"),
  }
end

function M.quality(p)
  return {
    name = p.name,
    level = read(p, "level"),
    next = name_of(read(p, "next")),
    next_probability = read(p, "next_probability"),
    default_multiplier = read(p, "default_multiplier"),
    crafting_machine_speed_multiplier = read(p, "crafting_machine_speed_multiplier"),
    mining_drill_resource_drain_multiplier = read(p, "mining_drill_resource_drain_multiplier"),
    science_pack_drain_multiplier = read(p, "science_pack_drain_multiplier"),
    beacon_power_usage_multiplier = read(p, "beacon_power_usage_multiplier"),
    hidden = read(p, "hidden"),
  }
end

function M.technology(p)
  local prereqs = sorted_keys(read(p, "prerequisites"), false)
  return {
    name = p.name,
    enabled = read(p, "enabled"),
    hidden = read(p, "hidden"),
    upgrade = read(p, "upgrade"),
    level = read(p, "level"),
    max_level = read(p, "max_level"),
    prerequisites = prereqs,
    ingredients = array_of_scalars(read(p, "research_unit_ingredients")),
    unit_count = read(p, "research_unit_count"),
    unit_energy = read(p, "research_unit_energy"),
    research_trigger = scalars(read(p, "research_trigger")),
    effects = array_of_scalars(read(p, "effects")),
  }
end

-- surface_property_defaults: name -> default value (from prototypes.surface_property)
function M.planet(p, surface_property_defaults)
  local props = {}
  for k, v in pairs(surface_property_defaults or {}) do props[k] = v end
  local own = read(p, "surface_properties")
  if type(own) == "table" then
    for k, v in pairs(own) do props[k] = v end
  end
  return {
    name = p.name,
    type = read(p, "type"),
    surface_properties = props,
    distance = read(p, "distance"),
    magnitude = read(p, "magnitude"),
    gravity_pull = read(p, "gravity_pull"),
    solar_power_in_space = read(p, "solar_power_in_space"),
    entities_require_heating = read(p, "entities_require_heating"),
    hidden = read(p, "hidden"),
  }
end

-- All names of a LuaCustomTable-like dictionary, optionally filtered by predicate, sorted.
function M.names(collection, predicate)
  local out = {}
  for name, p in pairs(collection) do
    if not predicate or predicate(p) then out[#out + 1] = name end
  end
  table.sort(out)
  return out
end

return M
