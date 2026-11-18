-- `production` subcommand: items and fluids produced and consumed per minute by the caller's force.
-- Params: {caller, window? ("5s"|"1m"|"10m"|"1h"|"10h", default "1m"), surface?, name?, limit? (1..50, default 15)}.
local dispatcher = require("scripts.dispatcher")
local caller = require("scripts.logic.caller")
local params_lib = require("scripts.logic.params")
local production_logic = require("scripts.logic.production_logic")

local WINDOWS = { "5s", "1m", "10m", "1h", "10h" }
local WINDOW_INDEX = {
  ["5s"] = "five_seconds", ["1m"] = "one_minute", ["10m"] = "ten_minutes",
  ["1h"] = "one_hour", ["10h"] = "ten_hours",
}

local function quality_names()
  local names = {}
  for name, q in pairs(prototypes.quality) do
    if not q.hidden then names[#names + 1] = name end
  end
  table.sort(names)
  return names
end

local function surfaces_of(p)
  local name = params_lib.string(p, "surface")
  if name then
    local surface = game.get_surface(name)
    if not surface then error({ code = "not_found", message = "no such surface" }) end
    return { surface }
  end
  local list = {}
  for _, surface in pairs(game.surfaces) do list[#list + 1] = surface end
  table.sort(list, function(a, b) return a.name < b.name end)
  return list
end

local function stats_list(force, surfaces, fluids)
  local list = {}
  for _, surface in ipairs(surfaces) do
    local stats = fluids and force.get_fluid_production_statistics(surface)
      or force.get_item_production_statistics(surface)
    list[#list + 1] = { surface = surface.name, stats = stats }
  end
  return list
end

local function one_name(name, force, surfaces, window_index)
  local is_item = prototypes.item[name] ~= nil
  if not is_item and not prototypes.fluid[name] then
    error({ code = "not_found", message = "no such item or fluid" })
  end
  local per_surface = production_logic.rates(stats_list(force, surfaces, not is_item), window_index,
    is_item and quality_names() or nil)
  local by_surface, total, by_quality = {}, { produced = 0, consumed = 0 }, nil
  for _, surface in ipairs(surfaces) do
    local r = per_surface[surface.name][name]
    if r then
      by_surface[#by_surface + 1] = { surface = surface.name, produced = r.produced, consumed = r.consumed,
        net = production_logic.round2(r.produced - r.consumed) }
      total.produced = production_logic.round2(total.produced + r.produced)
      total.consumed = production_logic.round2(total.consumed + r.consumed)
      for q, v in pairs(r.by_quality or {}) do
        by_quality = by_quality or {}
        by_quality[q] = (by_quality[q] or 0) + v
      end
    end
  end
  total.net = production_logic.round2(total.produced - total.consumed)
  return { name = name, kind = is_item and "item" or "fluid", total = total, by_surface = by_surface,
    by_quality = by_quality }
end

dispatcher.register("production", function(p)
  local force = caller.force(p)
  local window = params_lib.one_of(p, "window", "1m", WINDOWS)
  local window_index = defines.flow_precision_index[WINDOW_INDEX[window]]
  local limit = params_lib.int(p, "limit", 15, 1, 50)
  local surfaces = surfaces_of(p)
  local name = params_lib.string(p, "name")
  if name then
    local result = one_name(name, force, surfaces, window_index)
    result.window = window
    return result
  end
  local names = {}
  for i, surface in ipairs(surfaces) do names[i] = surface.name end
  local items = production_logic.merge(production_logic.rates(stats_list(force, surfaces, false), window_index, quality_names()))
  local fluids = production_logic.merge(production_logic.rates(stats_list(force, surfaces, true), window_index, nil))
  return {
    window = window,
    surfaces = names,
    items = production_logic.summarize(items, limit),
    fluids = production_logic.summarize(fluids, limit),
  }
end)
