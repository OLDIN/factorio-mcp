-- Summary of machine/drill records: totals, groups, and the stopped / drill lists.
-- A record is {name, type, x, y, dist, status (string), recipe?, crafting_progress?, resource?, remaining?}.
-- The accumulator is plain data (it lives in `storage` while a tick-split job runs).
local envelope = require("scripts.envelope")

local M = {}

local function bump(map, key)
  map[key] = (map[key] or 0) + 1
end

local function by_dist(a, b)
  if a.dist ~= b.dist then return a.dist < b.dist end
  return a.name < b.name
end

-- drills: the ones about to run dry first (unknown remaining last), then nearest
local function drill_order(a, b)
  local ra, rb = a.remaining or math.huge, b.remaining or math.huge
  if ra ~= rb then return ra < rb end
  return by_dist(a, b)
end

local function strip(record)
  local out = {}
  for k, v in pairs(record) do
    if k ~= "dist" and k ~= "type" then out[k] = v end
  end
  return out
end

function M.new(max_listed)
  return {
    max_listed = max_listed,
    totals = { machines = 0, working = 0, by_status = {} },
    groups = {}, stopped = {}, drills = {}, stopped_total = 0, drills_total = 0,
  }
end

-- keep only the best `max_listed` records once the list grows well past it
local function trim(list, order, keep, force)
  if #list > keep * 2 + 16 or (force and #list > keep) then
    table.sort(list, order)
    for i = #list, keep + 1, -1 do list[i] = nil end
  end
end

function M.add(acc, r)
  local totals = acc.totals
  totals.machines = totals.machines + 1
  bump(totals.by_status, r.status)
  if r.status == "working" then totals.working = totals.working + 1 end
  local key = r.name .. "|" .. (r.recipe or "")
  local g = acc.groups[key]
  if not g then
    g = { name = r.name, recipe = r.recipe, count = 0, working = 0, by_status = {} }
    acc.groups[key] = g
  end
  g.count = g.count + 1
  if r.status == "working" then g.working = g.working + 1 end
  bump(g.by_status, r.status)
  if r.type == "mining-drill" then
    acc.drills_total = acc.drills_total + 1
    acc.drills[#acc.drills + 1] = r
    trim(acc.drills, drill_order, acc.max_listed)
  elseif r.status ~= "working" then
    acc.stopped_total = acc.stopped_total + 1
    acc.stopped[#acc.stopped + 1] = r
    trim(acc.stopped, by_dist, acc.max_listed)
  end
end

-- enrich(record) -> record: optional, called only on records that make it into a list.
-- extra: optional fields added to the result (inside the budget). Returns the result and its
-- encoding (envelope.encode_result), which a command can hand to the dispatcher as is.
function M.finish(acc, budget_bytes, enrich, extra)
  local group_list = {}
  for _, g in pairs(acc.groups) do group_list[#group_list + 1] = g end
  table.sort(group_list, function(a, b)
    if a.count ~= b.count then return a.count > b.count end
    if a.name ~= b.name then return a.name < b.name end
    return (a.recipe or "") < (b.recipe or "")
  end)
  table.sort(acc.stopped, by_dist)
  table.sort(acc.drills, drill_order)
  trim(acc.stopped, by_dist, acc.max_listed, true)
  trim(acc.drills, drill_order, acc.max_listed, true)
  local truncated = acc.stopped_total > acc.max_listed or acc.drills_total > acc.max_listed

  local function listed(list)
    local out = {}
    for i, record in ipairs(list) do
      if enrich then record = enrich(record) end
      out[i] = strip(record)
    end
    return out
  end
  local listed_stopped, listed_drills = listed(acc.stopped), listed(acc.drills)
  local result = {
    totals = acc.totals, groups = group_list,
    stopped = listed_stopped, drills = listed_drills, truncated = truncated,
  }
  for k, v in pairs(extra or {}) do result[k] = v end
  -- fit the budget: drop from the longer list's tail until the encoded reply fits
  local encoded = envelope.encode_result(result)
  while #encoded > budget_bytes and (#listed_stopped + #listed_drills + #group_list) > 0 do
    truncated = true
    if #listed_stopped >= #listed_drills and #listed_stopped > 0 then
      listed_stopped[#listed_stopped] = nil
    elseif #listed_drills > 0 then
      listed_drills[#listed_drills] = nil
    else
      group_list[#group_list] = nil
    end
    result.truncated = truncated
    encoded = envelope.encode_result(result)
  end
  result.truncated = truncated
  return result, encoded
end

function M.build(records, max_listed, budget_bytes, enrich)
  local acc = M.new(max_listed)
  for _, r in ipairs(records) do M.add(acc, r) end
  return M.finish(acc, budget_bytes, enrich)
end

return M
