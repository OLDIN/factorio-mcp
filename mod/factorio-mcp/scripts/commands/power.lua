-- `power` subcommand: electric networks of the caller's force around a point or a player.
-- Params: {caller, player?} or {caller, surface, x, y}; radius? (default 32, at most 64), limit? (1..30, default 10).
-- Flows are the last 5 seconds ("now"); see power_logic for units and direction.
local dispatcher = require("scripts.dispatcher")
local caller = require("scripts.logic.caller")
local params_lib = require("scripts.logic.params")
local geo = require("scripts.logic.geo")
local power_logic = require("scripts.logic.power_logic")
local area_scan = require("scripts.logic.area_scan")
local statuses = require("scripts.statuses")

local MAX_RADIUS = 64
local MAX_NETWORKS = 10
local STARVED = { low_power = true, no_power = true }

dispatcher.register("power", function(p)
  local force = caller.force(p)
  local radius = params_lib.number(p, "radius", 32)
  if radius <= 0 or radius > MAX_RADIUS then
    error({ code = "bad_params", message = "radius must be above 0 and at most " .. MAX_RADIUS })
  end
  local limit = params_lib.int(p, "limit", 10, 1, 30)
  local surface, center = caller.center(p)
  local around = { position = { x = center.x, y = center.y }, radius = radius, force = force }
  local window = defines.flow_precision_index.five_seconds

  local by_id, order = {}, {}
  local function network(id)
    local n = by_id[id]
    if not n then
      n = { id = id, poles = 0, starved = { low_power = 0, no_power = 0 }, acc = {} }
      by_id[id] = n
      order[#order + 1] = n
    end
    return n
  end

  around.type = "electric-pole"
  for _, pole in ipairs(surface.find_entities_filtered(around)) do
    local id = pole.electric_network_id
    if id then
      local n = network(id)
      n.poles = n.poles + 1
      if not n.pole then n.pole = pole end
    end
  end

  around.type = "accumulator"
  for _, a in ipairs(surface.find_entities_filtered(around)) do
    local id = a.electric_network_id
    if id and by_id[id] then table.insert(by_id[id].acc, a) end
  end

  local examples = {}
  around.type = area_scan.AREA_TYPES
  for _, m in ipairs(surface.find_entities_filtered(around)) do
    local status = statuses.name(m.status)
    if STARVED[status] then
      local id = m.electric_network_id
      if id and by_id[id] then
        by_id[id].starved[status] = by_id[id].starved[status] + 1
      end
      if #examples < limit then
        local pos = m.position
        examples[#examples + 1] = { name = m.name, gps = geo.gps(surface.name, pos.x, pos.y), status = status, network = id }
      end
    end
  end

  local networks = {}
  for _, n in ipairs(order) do
    local summary = power_logic.network_summary(n.pole.electric_network_statistics, window, limit)
    local pos = n.pole.position
    networks[#networks + 1] = {
      id = n.id, poles = n.poles, gps = geo.gps(surface.name, pos.x, pos.y),
      produced_kw = summary.produced_kw, consumed_kw = summary.consumed_kw,
      top_producers = summary.top_producers, top_consumers = summary.top_consumers,
      accumulators = power_logic.accumulators(n.acc), starved = n.starved,
    }
  end
  power_logic.sort_networks(networks)
  local total = #networks
  for i = total, MAX_NETWORKS + 1, -1 do networks[i] = nil end

  return {
    center = { surface = surface.name, x = center.x, y = center.y }, radius = radius, window = "5s",
    networks = networks, networks_total = total, starved_examples = examples,
  }
end)
