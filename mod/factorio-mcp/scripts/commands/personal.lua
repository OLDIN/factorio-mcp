-- `inventory` and `alerts` subcommands: ONLY the caller's own (the nick from the service's token).
-- Params: inventory {caller}; alerts {caller, limit? (1..20 examples per type, default 5)}.
local dispatcher = require("scripts.dispatcher")
local caller = require("scripts.logic.caller")
local params_lib = require("scripts.logic.params")
local personal_logic = require("scripts.logic.personal_logic")

dispatcher.register("inventory", function(p)
  return personal_logic.inventory(caller.player(p))
end)

dispatcher.register("alerts", function(p)
  local player = caller.player(p)
  local limit = params_lib.int(p, "limit", 5, 1, 20)
  local ok, alerts = pcall(player.get_alerts, {})
  local result = personal_logic.alerts(ok and alerts or {}, game.surfaces, limit)
  result.online = player.connected
  return result
end)
