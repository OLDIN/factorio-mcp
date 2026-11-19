-- `logistics` subcommand: the caller's force's logistic networks.
-- Params: {caller, surface?, name?, limit? (1..50, default 15)}.
local dispatcher = require("scripts.dispatcher")
local caller = require("scripts.logic.caller")
local params_lib = require("scripts.logic.params")
local logistics_logic = require("scripts.logic.logistics_logic")

local MAX_NETWORKS = 20

dispatcher.register("logistics", function(p)
  local force = caller.force(p)
  local only = params_lib.string(p, "surface")
  if only and not game.get_surface(only) then error({ code = "not_found", message = "no such surface" }) end
  local limit = params_lib.int(p, "limit", 15, 1, 50)
  local name = params_lib.string(p, "name")
  local nets = {}
  for surface_name, list in pairs(force.logistic_networks) do
    if not only or surface_name == only then
      for _, net in ipairs(list) do nets[#nets + 1] = { surface = surface_name, net = net } end
    end
  end
  if name then
    local total, by_network = 0, {}
    for _, e in ipairs(nets) do
      local n = logistics_logic.count_item(e.net.get_contents() or {}, name)
      if n > 0 then
        total = total + n
        by_network[#by_network + 1] = { surface = e.surface, id = e.net.network_id, count = n }
      end
    end
    table.sort(by_network, function(a, b) return a.count > b.count end)
    return { name = name, total = total, by_network = by_network }
  end
  local list = {}
  for _, e in ipairs(nets) do list[#list + 1] = logistics_logic.network(e.net, e.surface, limit) end
  logistics_logic.sort_networks(list)
  local total = #list
  for i = total, MAX_NETWORKS + 1, -1 do list[i] = nil end
  return { networks = list, total = total }
end)
