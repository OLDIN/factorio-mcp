-- Belts, inserters and pipes around a point. TYPES is its own allowlist (area_scan.AREA_TYPES is
-- unchanged): no vehicles, characters or wagons are ever requested, so nobody's cargo is read.
local M = {}

M.TYPES = {
  "transport-belt", "underground-belt", "splitter", "loader", "loader-1x1",
  "inserter", "pipe", "pipe-to-ground", "pump", "storage-tank",
}

M.BELT_TYPES = { ["transport-belt"] = true, ["underground-belt"] = true, ["splitter"] = true,
  ["loader"] = true, ["loader-1x1"] = true }
M.FLUID_TYPES = { ["pipe"] = true, ["pipe-to-ground"] = true, ["pump"] = true, ["storage-tank"] = true }

-- the worst first; an inserter in any of these is "stuck"
local STUCK = { no_power = 1, low_power = 2, waiting_for_space_in_destination = 3, waiting_for_source_items = 4 }

function M.new_acc(limit)
  return { limit = limit, counts = {}, by_status = {}, stuck = {}, stuck_total = 0, items = {}, fluids = {} }
end

function M.count(acc, name)
  acc.counts[name] = (acc.counts[name] or 0) + 1
end

-- record: {name, gps, status} (status is the defines.entity_status name)
function M.add_inserter(acc, record)
  acc.by_status[record.status] = (acc.by_status[record.status] or 0) + 1
  if STUCK[record.status] then
    acc.stuck_total = acc.stuck_total + 1
    acc.stuck[#acc.stuck + 1] = record
  end
end

-- contents: [{name, quality?, count}] of one transport line (qualities are summed)
function M.add_belt_items(acc, contents)
  for _, it in ipairs(contents or {}) do acc.items[it.name] = (acc.items[it.name] or 0) + it.count end
end

function M.add_fluid(acc, name, amount)
  acc.fluids[name] = (acc.fluids[name] or 0) + amount
end

-- A pipe, pump or tank. Factorio 2.1 has no LuaEntity.fluidbox; get_fluid(i) is this entity's own share
-- of its fluid segment (checked live: pipe 18/100, tank 4620/25000), so the sum counts nothing twice.
function M.add_entity_fluids(acc, e)
  for i = 1, e.fluids_count do
    local f = e.get_fluid(i)
    if f then M.add_fluid(acc, f.name, f.amount) end
  end
end

local function sorted(map, key, top)
  local list = {}
  for name, v in pairs(map) do list[#list + 1] = { name = name, [key] = v } end
  table.sort(list, function(a, b)
    if a[key] ~= b[key] then return a[key] > b[key] end
    return a.name < b.name
  end)
  if top then for i = #list, top + 1, -1 do list[i] = nil end end
  return list
end

function M.finish(acc)
  table.sort(acc.stuck, function(a, b)
    if STUCK[a.status] ~= STUCK[b.status] then return STUCK[a.status] < STUCK[b.status] end
    return a.gps < b.gps
  end)
  for i = #acc.stuck, acc.limit + 1, -1 do acc.stuck[i] = nil end
  local fluids = sorted(acc.fluids, "amount")
  for _, f in ipairs(fluids) do f.amount = math.floor(f.amount * 10 + 0.5) / 10 end
  return {
    counts = acc.counts,
    inserters = { by_status = acc.by_status, stuck = acc.stuck, stuck_total = acc.stuck_total },
    belts = { items = sorted(acc.items, "count", 10) },
    fluids = fluids,
  }
end

return M
