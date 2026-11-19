-- `trains` subcommand: the caller's force's trains, problem trains first.
-- Params: {caller, surface?, problems_only? (bool), offset? (default 0), limit? (1..50, default 15)}.
local dispatcher = require("scripts.dispatcher")
local caller = require("scripts.logic.caller")
local params_lib = require("scripts.logic.params")
local trains_logic = require("scripts.logic.trains_logic")

dispatcher.register("trains", function(p)
  local force = caller.force(p)
  local filter = { force = force }
  local only = params_lib.string(p, "surface")
  if only then
    local surface = game.get_surface(only)
    if not surface then error({ code = "not_found", message = "no such surface" }) end
    filter.surface = surface
  end
  if p.problems_only ~= nil and type(p.problems_only) ~= "boolean" then
    error({ code = "bad_params", message = "problems_only must be true or false" })
  end
  local offset = params_lib.int(p, "offset", 0, 0, 100000)
  local limit = params_lib.int(p, "limit", 15, 1, 50)
  local names = trains_logic.state_names()
  local records = {}
  for _, train in ipairs(game.train_manager.get_trains(filter)) do
    if train.valid then records[#records + 1] = trains_logic.record(train, names) end
  end
  return trains_logic.page(records, p.problems_only == true, offset, limit)
end)
