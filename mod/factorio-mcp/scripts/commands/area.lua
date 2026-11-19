-- `area` subcommand: machines and drills around a player or a point (read-only, allowlisted types).
-- Params: {player?} or {surface, x, y}; radius? (default 32), max_listed? (default 20).
local dispatcher = require("scripts.dispatcher")
local caller = require("scripts.logic.caller")
local params_lib = require("scripts.logic.params")
local limits = require("scripts.limits")
local area_scan = require("scripts.logic.area_scan")

dispatcher.register("area", function(params)
  local radius = params_lib.number(params, "radius", 32)
  if radius <= 0 then error({ code = "bad_params", message = "radius must be positive" }) end
  if radius > limits.MAX_SYNC_AREA_RADIUS then
    error({ code = "bad_params", message = "radius above " .. limits.MAX_SYNC_AREA_RADIUS .. " must run as a job (job_start, kind area)" })
  end
  local max_listed = params_lib.number(params, "max_listed", 20)
  if max_listed < 1 or max_listed ~= math.floor(max_listed) then
    error({ code = "bad_params", message = "max_listed must be a positive integer" })
  end
  local surface, center = caller.center(params)
  -- the result comes back encoded too (the budget check's encoding): the reply is not encoded twice
  return area_scan.scan(surface, center, radius, max_listed, limits.RESPONSE_BUDGET_BYTES - 500,
    { center = { surface = surface.name, x = center.x, y = center.y }, radius = radius })
end)
