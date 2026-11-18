-- Production statistics: items and fluids produced and consumed per minute, per surface.
--
-- Calibrated on Factorio 2.1.24 (dev server, 2026-11-19): `get_flow_count{..., count = false}`
-- returns the average per MINUTE over the window for every precision index (600 items in 5 s ->
-- 7200, in 10 min -> 60). A plain item name counts only normal quality, while `input_counts`
-- keys merge all qualities, so items are queried once per quality and summed. Fluids have no
-- quality. "input" is produced, "output" is consumed.
local M = {}

local function round2(v) return math.floor(v * 100 + 0.5) / 100 end
M.round2 = round2

local function flow(stats, name, category, window_index)
  return stats.get_flow_count({ name = name, category = category, precision_index = window_index, count = false })
end

-- One surface's statistics -> {name -> {produced, consumed, by_quality?}}; `qualities` nil for fluids.
local function surface_rates(stats, window_index, qualities)
  local names = {}
  for name in pairs(stats.input_counts) do names[name] = true end
  for name in pairs(stats.output_counts) do names[name] = true end
  local out = {}
  for name in pairs(names) do
    local produced, consumed, by_quality = 0, 0, nil
    if qualities then
      for _, q in ipairs(qualities) do
        local id = { name = name, quality = q }
        local p = flow(stats, id, "input", window_index)
        produced = produced + p
        consumed = consumed + flow(stats, id, "output", window_index)
        if p > 0 then
          by_quality = by_quality or {}
          by_quality[q] = round2(p)
        end
      end
    else
      produced = flow(stats, name, "input", window_index)
      consumed = flow(stats, name, "output", window_index)
    end
    if produced > 0 or consumed > 0 then
      out[name] = { produced = round2(produced), consumed = round2(consumed), by_quality = by_quality }
    end
  end
  return out
end

-- `list` = {{surface = name, stats = LuaFlowStatistics}} -> {surface -> {name -> rates}}
function M.rates(list, window_index, qualities)
  local out = {}
  for _, entry in ipairs(list) do
    out[entry.surface] = surface_rates(entry.stats, window_index, qualities)
  end
  return out
end

-- {surface -> {name -> rates}} -> {name -> {produced, consumed}} summed over surfaces
function M.merge(per_surface)
  local out = {}
  for _, by_name in pairs(per_surface) do
    for name, r in pairs(by_name) do
      local m = out[name]
      if not m then
        m = { produced = 0, consumed = 0 }
        out[name] = m
      end
      m.produced = round2(m.produced + r.produced)
      m.consumed = round2(m.consumed + r.consumed)
    end
  end
  return out
end

local function entry(name, r)
  return { name = name, produced = r.produced, consumed = r.consumed, net = round2(r.produced - r.consumed) }
end

local function top(entries, keep, limit, order)
  local list = {}
  for _, e in ipairs(entries) do
    if keep(e) then list[#list + 1] = e end
  end
  table.sort(list, function(a, b)
    local ka, kb = order(a), order(b)
    if ka ~= kb then return ka > kb end
    return a.name < b.name
  end)
  local out = {}
  for i = 1, math.min(limit, #list) do out[i] = list[i] end
  return out
end

-- {name -> rates} -> {top_produced, top_consumed, deficits}
function M.summarize(merged, limit)
  local entries = {}
  for name, r in pairs(merged) do entries[#entries + 1] = entry(name, r) end
  return {
    top_produced = top(entries, function(e) return e.produced > 0 end, limit, function(e) return e.produced end),
    top_consumed = top(entries, function(e) return e.consumed > 0 end, limit, function(e) return e.consumed end),
    deficits = top(entries, function(e) return e.consumed > e.produced end, limit, function(e) return -e.net end),
  }
end

return M
