-- `resources` subcommand: resource patches around a point or a player.
-- Params: {caller, player?} or {caller, surface, x, y}; radius? (default 64, at most 128), limit? (1..30, default 10).
-- The tiles in the circle are counted first (cheap); above SYNC_MAX_TILES nothing is read and the answer
-- is {job_needed = true, center, radius}: the service then runs job kind `resources`, so a rich
-- patch never costs more than a couple of milliseconds in one tick.
local dispatcher = require("scripts.dispatcher")
local caller = require("scripts.logic.caller")
local params_lib = require("scripts.logic.params")
local resources_logic = require("scripts.logic.resources_logic")
local limits = require("scripts.limits")

dispatcher.register("resources", function(p)
  caller.player(p) -- a known caller only
  local radius = params_lib.number(p, "radius", 64)
  if radius <= 0 or radius > limits.MAX_RESOURCES_RADIUS then
    error({ code = "bad_params", message = "radius must be above 0 and at most " .. limits.MAX_RESOURCES_RADIUS })
  end
  local limit = params_lib.int(p, "limit", 10, 1, 30)
  local surface, center = caller.center(p)
  local query = { position = { x = center.x, y = center.y }, radius = radius, type = "resource" }
  local where = { surface = surface.name, x = center.x, y = center.y }
  -- counting stops just past the threshold: a rich r=128 circle (51k tiles) costs ~2.4 ms to count in full
  local over = surface.count_entities_filtered({ position = query.position, radius = radius, type = "resource",
    limit = limits.SYNC_MAX_RESOURCE_TILES + 1 })
  if over > limits.SYNC_MAX_RESOURCE_TILES then
    return { job_needed = true, center = where, radius = radius }
  end
  local acc, fluid_of = resources_logic.new_acc(), {}
  for _, e in ipairs(surface.find_entities_filtered(query)) do
    if e.valid then
      local name = e.name
      local fluid = fluid_of[name]
      if fluid == nil then
        fluid = resources_logic.is_fluid(e.prototype)
        fluid_of[name] = fluid
      end
      local pos = e.position
      resources_logic.add(acc, name, pos.x, pos.y, e.amount, fluid)
    end
  end
  local all = resources_logic.finish(acc, surface.name)
  local patches = {}
  for i = 1, math.min(limit, #all) do patches[i] = all[i] end
  return { center = where, radius = radius, patches = patches, patches_total = #all }
end)
