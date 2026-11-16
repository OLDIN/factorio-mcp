-- `area` subcommand: machines and drills around a player or a point (read-only, allowlisted types).
-- Params: {player?} or {surface, x, y}; radius? (default 32), max_listed? (default 20).
local dispatcher = require("scripts.dispatcher")
local limits = require("scripts.limits")
local area_scan = require("scripts.logic.area_scan")

local function number_param(params, key, default)
  local v = params[key]
  if v == nil then return default end
  if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then
    error({ code = "bad_params", message = key .. " must be a finite number" })
  end
  return v
end

local function center_from(params)
  if params.player ~= nil then
    if type(params.player) ~= "string" then
      error({ code = "bad_params", message = "player must be a string" })
    end
    local player = game.get_player(params.player)
    if not player then
      error({ code = "not_found", message = "no such player" })
    end
    if not player.connected then
      error({ code = "not_found", message = "player is offline: position unknown" })
    end
    local pos = player.physical_position
    return player.physical_surface, { x = pos.x, y = pos.y }
  end
  if type(params.surface) ~= "string" then
    error({ code = "bad_params", message = "give player, or surface with x and y" })
  end
  local surface = game.get_surface(params.surface)
  if not surface then
    error({ code = "not_found", message = "no such surface" })
  end
  return surface, { x = number_param(params, "x", nil) or 0, y = number_param(params, "y", nil) or 0 }
end

dispatcher.register("area", function(params)
  local radius = number_param(params, "radius", 32)
  if radius <= 0 then error({ code = "bad_params", message = "radius must be positive" }) end
  if radius > limits.MAX_SYNC_AREA_RADIUS then
    error({ code = "bad_params", message = "radius above " .. limits.MAX_SYNC_AREA_RADIUS .. " must run as a job (job_start, kind area)" })
  end
  local max_listed = number_param(params, "max_listed", 20)
  if max_listed < 1 or max_listed ~= math.floor(max_listed) then
    error({ code = "bad_params", message = "max_listed must be a positive integer" })
  end
  local surface, center = center_from(params)
  local result = area_scan.scan(surface, center, radius, max_listed, limits.RESPONSE_BUDGET_BYTES - 500)
  result.center = { surface = surface.name, x = center.x, y = center.y }
  result.radius = radius
  return result
end)
