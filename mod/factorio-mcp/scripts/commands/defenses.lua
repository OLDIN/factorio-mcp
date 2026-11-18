-- `defenses` subcommand: military and defensive structures around a player or a point.
-- Reads turrets, ammo counts, fluid amounts, power state, and wall integrity.
-- Params: {player?} or {surface, x, y}; radius? (default 32, at most 64), max_listed? (default 20, at most 50).
-- The scan runs in one tick, so the radius is bounded like the synchronous `area` scan.
local dispatcher = require("scripts.dispatcher")
local caller = require("scripts.logic.caller")
local params_lib = require("scripts.logic.params")
local defenses_scan = require("scripts.logic.defenses_scan")

local MAX_DEFENSES_RADIUS = 64
local MAX_LISTED = 50

dispatcher.register("defenses", function(params)
  local radius = params_lib.number(params, "radius", 32)
  if radius <= 0 then error({ code = "bad_params", message = "radius must be positive" }) end
  if radius > MAX_DEFENSES_RADIUS then
    error({ code = "bad_params", message = "radius above " .. MAX_DEFENSES_RADIUS .. " is not supported" })
  end
  local max_listed = params_lib.number(params, "max_listed", 20)
  if max_listed < 1 or max_listed ~= math.floor(max_listed) then
    error({ code = "bad_params", message = "max_listed must be a positive integer" })
  end
  if max_listed > MAX_LISTED then
    error({ code = "bad_params", message = "max_listed above " .. MAX_LISTED .. " is not supported" })
  end
  local surface, center = caller.center(params)
  local result = defenses_scan.scan(surface, center, radius, max_listed)
  result.center = { surface = surface.name, x = center.x, y = center.y }
  result.radius = radius
  return result
end)
