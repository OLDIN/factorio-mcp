-- `players` subcommand: list players with online status, admin flag, and positions.
local dispatcher = require("scripts.dispatcher")
local player_format = require("scripts.logic.player_format")

dispatcher.register("players", function()
  local list = {}
  for _, p in pairs(game.players) do
    list[#list + 1] = player_format.format_player(p)
  end
  return {
    players = list,
  }
end)
