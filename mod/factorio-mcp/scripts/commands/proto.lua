-- `proto_<kind>` subcommands: paged reference data from the game's prototypes (read-only).
-- Params: {offset?, limit?}. Reply: {kind, total, offset, items, next}.
local dispatcher = require("scripts.dispatcher")
local limits = require("scripts.limits")
local paging = require("scripts.logic.paging")
local render = require("scripts.logic.proto_render")

local DEFAULT_LIMIT = 200
local MAX_LIMIT = 1000

local function int_param(params, key, default, min, max)
  local value = params[key]
  if value == nil then return default end
  if type(value) ~= "number" or value ~= math.floor(value) or value < min or value > max then
    error({ code = "bad_params", message = key .. " must be an integer between " .. min .. " and " .. max })
  end
  return value
end

local function surface_property_defaults()
  local out = {}
  for name, p in pairs(prototypes.surface_property) do out[name] = p.default_value end
  return out
end

-- kind -> {collection(), predicate, render}
local kinds = {
  recipes = { collection = function() return prototypes.recipe end, render = render.recipe },
  machines = { collection = function() return prototypes.entity end, predicate = render.is_machine, render = render.machine },
  items = { collection = function() return prototypes.item end, render = render.item },
  fluids = { collection = function() return prototypes.fluid end, render = render.fluid },
  modules = { collection = function() return prototypes.item end, predicate = render.is_module, render = render.module },
  qualities = { collection = function() return prototypes.quality end, render = render.quality },
  technologies = { collection = function() return prototypes.technology end, render = render.technology },
  planets = { collection = function() return prototypes.space_location end, render = nil },
}

-- Sorted names per kind. Walking and sorting a whole prototype collection took ~4-5 ms per page
-- (thousands of entity prototypes); prototypes never change while the game runs, so it is done once per
-- kind. Module-local (not storage): it only shapes replies, never game state.
local names_cache = {}

for kind, spec in pairs(kinds) do
  dispatcher.register("proto_" .. kind, function(params)
    local offset = int_param(params, "offset", 0, 0, 10000000)
    local limit = int_param(params, "limit", DEFAULT_LIMIT, 1, MAX_LIMIT)
    local collection = spec.collection()
    local names = names_cache[kind]
    if not names then
      names = render.names(collection, spec.predicate)
      names_cache[kind] = names
    end
    local draw
    if kind == "planets" then
      local defaults = surface_property_defaults()
      draw = function(name) return render.planet(collection[name], defaults) end
    else
      draw = function(name) return spec.render(collection[name]) end
    end
    local items, nxt = paging.page(names, offset, limit, draw, limits.PROTO_PAGE_BUDGET_BYTES)
    return { kind = kind, total = #names, offset = offset, items = items, next = nxt }
  end)
end
