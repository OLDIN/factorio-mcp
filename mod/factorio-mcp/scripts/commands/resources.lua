-- `resources` subcommand: resource patches around a point or a player, and the surface's totals.
-- Params: {caller, player?} or {caller, surface, x, y}; radius? (default 64, at most 128), limit? (1..30, default 10).
local dispatcher = require("scripts.dispatcher")
local caller = require("scripts.logic.caller")
local params_lib = require("scripts.logic.params")
local resources_logic = require("scripts.logic.resources_logic")

local MAX_RADIUS = 128

dispatcher.register("resources", function(p)
  caller.player(p) -- a known caller only
  local radius = params_lib.number(p, "radius", 64)
  if radius <= 0 or radius > MAX_RADIUS then
    error({ code = "bad_params", message = "radius must be above 0 and at most " .. MAX_RADIUS })
  end
  local limit = params_lib.int(p, "limit", 10, 1, 30)
  local surface, center = caller.center(p)
  local found = surface.find_entities_filtered({ position = { x = center.x, y = center.y }, radius = radius, type = "resource" })
  local fluid_of, records = {}, {}
  for _, e in ipairs(found) do
    if e.valid then
      local name = e.name
      if fluid_of[name] == nil then fluid_of[name] = resources_logic.is_fluid(e.prototype) end
      local pos = e.position
      records[#records + 1] = { name = name, x = pos.x, y = pos.y, amount = e.amount, fluid = fluid_of[name] }
    end
  end
  local all = resources_logic.patches(records, surface.name)
  local patches = {}
  for i = 1, math.min(limit, #all) do patches[i] = all[i] end
  local ok, totals = pcall(surface.get_resource_counts)
  return {
    center = { surface = surface.name, x = center.x, y = center.y }, radius = radius,
    patches = patches, patches_total = #all, surface_totals = ok and totals or {},
  }
end)
