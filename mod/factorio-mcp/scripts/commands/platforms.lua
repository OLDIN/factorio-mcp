-- `platforms` subcommand: the caller's force's space platforms (none without Space Age).
-- Params: {caller, name?, limit? (1..50, default 10 hub stocks per platform)}.
local dispatcher = require("scripts.dispatcher")
local caller = require("scripts.logic.caller")
local params_lib = require("scripts.logic.params")
local platforms_logic = require("scripts.logic.platforms_logic")

dispatcher.register("platforms", function(p)
  local force = caller.force(p)
  local name = params_lib.string(p, "name")
  local limit = params_lib.int(p, "limit", 10, 1, 50)
  local names = platforms_logic.state_names()
  local list = {}
  for _, platform in pairs(force.platforms or {}) do
    if platform.valid and (not name or platform.name == name) then
      list[#list + 1] = platforms_logic.record(platform, names, limit)
    end
  end
  if name and #list == 0 then error({ code = "not_found", message = "no such platform" }) end
  table.sort(list, function(a, b) return a.name < b.name end)
  return { platforms = list, total = #list }
end)
