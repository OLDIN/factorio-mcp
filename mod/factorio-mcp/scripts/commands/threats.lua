-- `threats` subcommand: enemy spawners, worms and demolishers around a point or a player.
-- Params: {caller, player?} or {caller, surface, x, y}; radius? (default 128, at most 256; larger
-- radii run as job kind `threats`), limit? (1..30, default 10).
local dispatcher = require("scripts.dispatcher")
local caller = require("scripts.logic.caller")
local params_lib = require("scripts.logic.params")
local threats_logic = require("scripts.logic.threats_logic")

local MAX_SYNC_RADIUS = 256

dispatcher.register("threats", function(p)
  local force = caller.force(p)
  local radius = params_lib.number(p, "radius", 128)
  if radius <= 0 or radius > MAX_SYNC_RADIUS then
    error({ code = "bad_params", message = "radius must be above 0 and at most " .. MAX_SYNC_RADIUS .. " (larger radii run as a job, kind threats)" })
  end
  local limit = params_lib.int(p, "limit", 10, 1, 30)
  local surface, center = caller.center(p)
  local acc = threats_logic.new_acc(center, surface.name, limit)
  local enemies = threats_logic.enemy_force_names(force, game.forces)
  if #enemies > 0 then
    local found = surface.find_entities_filtered({
      position = { x = center.x, y = center.y }, radius = radius, type = threats_logic.ENEMY_TYPES, force = enemies,
    })
    for _, e in ipairs(found) do
      if e.valid then threats_logic.add(acc, threats_logic.record(e, surface)) end
    end
    threats_logic.add_surface_units(acc, surface, enemies, radius)
  end
  local result = threats_logic.finish(acc)
  result.center = { surface = surface.name, x = center.x, y = center.y }
  result.radius = radius
  return result
end)
