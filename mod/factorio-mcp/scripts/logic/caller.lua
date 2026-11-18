-- Who is asking and where to look. `caller` is the nick from the service's token (never from the
-- person's own words); every new subcommand reads only that player's force.
local params = require("scripts.logic.params")

local M = {}

local function not_found(message) error({ code = "not_found", message = message }) end

local function player_named(name)
  local player = game.get_player(name)
  if not player then not_found("no such player") end
  return player
end

function M.player(p)
  if type(p.caller) ~= "string" then
    error({ code = "bad_params", message = "caller must be a string" })
  end
  return player_named(p.caller)
end

function M.force(p)
  return M.player(p).force
end

-- {player} -> that player's physical position (online only); {surface, x, y} -> that point.
function M.center(p)
  if p.player ~= nil then
    if type(p.player) ~= "string" then
      error({ code = "bad_params", message = "player must be a string" })
    end
    local player = player_named(p.player)
    if not player.connected then not_found("player is offline: position unknown") end
    local pos = player.physical_position
    return player.physical_surface, { x = pos.x, y = pos.y }
  end
  if type(p.surface) ~= "string" then
    error({ code = "bad_params", message = "give player, or surface with x and y" })
  end
  local surface = game.get_surface(p.surface)
  if not surface then not_found("no such surface") end
  return surface, { x = params.number(p, "x", 0), y = params.number(p, "y", 0) }
end

return M
