-- Whole-base power: collect one pole per electric network during a map scan, then read each
-- network's statistics once at the end. Machines short of power and accumulators are counted per
-- network on the way. Lone idle networks (under 3 poles, nothing consuming) are only counted.
local geo = require("scripts.logic.geo")
local power_logic = require("scripts.logic.power_logic")
local statuses = require("scripts.statuses")

local M = {}

local TINY_POLES = 3

function M.new_acc()
  return { nets = {}, starved = {}, acc_energy = {}, acc_buffer = {}, acc_count = {} }
end

local function key(id) return tostring(id) end

function M.take(acc, entity, surface_name)
  local id = entity.electric_network_id
  if not id then return end
  local k = key(id)
  local etype = entity.type
  if etype == "electric-pole" then
    local net = acc.nets[k]
    if not net then
      local pos = entity.position
      net = { id = id, surface = surface_name, pole = entity, poles = 0, gps = geo.gps(surface_name, pos.x, pos.y) }
      acc.nets[k] = net
    end
    net.poles = net.poles + 1
  elseif etype == "accumulator" then
    acc.acc_count[k] = (acc.acc_count[k] or 0) + 1
    acc.acc_energy[k] = (acc.acc_energy[k] or 0) + (entity.energy or 0)
    acc.acc_buffer[k] = (acc.acc_buffer[k] or 0) + (entity.electric_buffer_size or 0)
  else
    local status = statuses.name(entity.status)
    if status == "low_power" or status == "no_power" then
      local s = acc.starved[k] or { low_power = 0, no_power = 0 }
      s[status] = s[status] + 1
      acc.starved[k] = s
    end
  end
end

-- -> {summary = {networks, starved_networks, tiny}, list = [network]}
function M.finish(acc, limit)
  local window = defines.flow_precision_index.five_seconds
  local list, seen, tiny, starved_networks = {}, 0, 0, 0
  for k, net in pairs(acc.nets) do
    if net.pole.valid then
      seen = seen + 1
      local summary = power_logic.network_summary(net.pole.electric_network_statistics, window, limit)
      local starved = acc.starved[k] or { low_power = 0, no_power = 0 }
      local is_starved = starved.low_power + starved.no_power > 0
      if is_starved then starved_networks = starved_networks + 1 end
      if net.poles < TINY_POLES and summary.consumed_kw == 0 and not is_starved then
        tiny = tiny + 1
      else
        local buffer = acc.acc_buffer[k] or 0
        list[#list + 1] = {
          id = net.id, surface = net.surface, poles = net.poles, gps = net.gps,
          produced_kw = summary.produced_kw, consumed_kw = summary.consumed_kw,
          top_producers = summary.top_producers, top_consumers = summary.top_consumers,
          starved = starved,
          accumulators = power_logic.accumulators(acc.acc_count[k] and { { energy = acc.acc_energy[k],
            electric_buffer_size = buffer } } or {}),
        }
        if acc.acc_count[k] then list[#list].accumulators.count = acc.acc_count[k] end
      end
    end
  end
  power_logic.sort_networks(list)
  return { summary = { networks = seen, starved_networks = starved_networks, tiny = tiny }, list = list }
end

return M
