-- Electric networks: flows in kW, accumulator charge, ordering by trouble.
--
-- Calibrated on Factorio 2.1.24 (2026-11-19): in `electric_network_statistics` "output" is
-- production and "input" is consumption (charging accumulators count as consumption);
-- `get_flow_count` returns joules per tick averaged over the window, so kW = value * 60 / 1000.
-- The statistics hold flows, not generator capacity, so there is no capacity ratio here.
local M = {}

local KW_PER_JOULE_PER_TICK = 60 / 1000

local function round1(v) return math.floor(v * 10 + 0.5) / 10 end

local function flows(stats, names, category, window_index)
  local list, total = {}, 0
  for name in pairs(names) do
    local kw = stats.get_flow_count({ name = name, category = category, precision_index = window_index })
      * KW_PER_JOULE_PER_TICK
    if kw > 0 then
      total = total + kw
      list[#list + 1] = { name = name, kw = round1(kw) }
    end
  end
  table.sort(list, function(a, b)
    if a.kw ~= b.kw then return a.kw > b.kw end
    return a.name < b.name
  end)
  return list, round1(total)
end

local function head(list, limit)
  local out = {}
  for i = 1, math.min(limit, #list) do out[i] = list[i] end
  return out
end

-- -> {produced_kw, consumed_kw, top_producers: [{name, kw}], top_consumers: [{name, kw}]}
function M.network_summary(stats, window_index, limit)
  local producers, produced = flows(stats, stats.output_counts, "output", window_index)
  local consumers, consumed = flows(stats, stats.input_counts, "input", window_index)
  return {
    produced_kw = produced, consumed_kw = consumed,
    top_producers = head(producers, limit), top_consumers = head(consumers, limit),
  }
end

-- accumulator entities -> {count, charge (0..1) or nil when there is no buffer}
function M.accumulators(entities)
  local energy, buffer = 0, 0
  for _, e in ipairs(entities) do
    energy = energy + (e.energy or 0)
    buffer = buffer + (e.electric_buffer_size or 0)
  end
  local charge = nil
  if buffer > 0 then charge = math.floor(energy / buffer * 100 + 0.5) / 100 end
  return { count = #entities, charge = charge }
end

local function starved(n) return n.starved.low_power + n.starved.no_power end

-- most starved machines first, then lowest accumulator charge (no accumulators last), then id
function M.sort_networks(list)
  table.sort(list, function(a, b)
    local sa, sb = starved(a), starved(b)
    if sa ~= sb then return sa > sb end
    local ca, cb = a.accumulators.charge, b.accumulators.charge
    if ca ~= cb then
      if ca == nil then return false end
      if cb == nil then return true end
      return ca < cb
    end
    return a.id < b.id
  end)
  return list
end

return M
