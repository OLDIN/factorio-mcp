-- Pure summary of machine/drill records around a point: totals, groups, and the stopped / drill lists.
-- A record is {name, type, x, y, dist, status (string), recipe?, crafting_progress?, resource?, remaining?}.
local M = {}

local function bump(map, key)
  map[key] = (map[key] or 0) + 1
end

local function by_dist(a, b)
  if a.dist ~= b.dist then return a.dist < b.dist end
  return a.name < b.name
end

-- Fields of a listed record that are not part of the public shape.
local function strip(record)
  local out = {}
  for k, v in pairs(record) do
    if k ~= "dist" and k ~= "type" then out[k] = v end
  end
  return out
end

-- enrich(record) -> record: optional, called only on records that make it into a list.
function M.build(records, max_listed, budget_bytes, enrich)
  local totals = { machines = #records, working = 0, by_status = {} }
  local groups, group_list = {}, {}
  local stopped, drills = {}, {}
  for _, r in ipairs(records) do
    bump(totals.by_status, r.status)
    if r.status == "working" then totals.working = totals.working + 1 end
    local key = r.name .. "|" .. (r.recipe or "")
    local g = groups[key]
    if not g then
      g = { name = r.name, recipe = r.recipe, count = 0, working = 0, by_status = {} }
      groups[key] = g
      group_list[#group_list + 1] = g
    end
    g.count = g.count + 1
    if r.status == "working" then g.working = g.working + 1 end
    bump(g.by_status, r.status)
    if r.type == "mining-drill" then
      drills[#drills + 1] = r
    elseif r.status ~= "working" then
      stopped[#stopped + 1] = r
    end
  end
  table.sort(group_list, function(a, b)
    if a.count ~= b.count then return a.count > b.count end
    if a.name ~= b.name then return a.name < b.name end
    return (a.recipe or "") < (b.recipe or "")
  end)
  table.sort(stopped, by_dist)
  -- drills: the ones about to run dry first (unknown remaining last), then nearest
  table.sort(drills, function(a, b)
    local ra, rb = a.remaining or math.huge, b.remaining or math.huge
    if ra ~= rb then return ra < rb end
    return by_dist(a, b)
  end)

  local truncated = false
  local function cut(list)
    local out = {}
    for i = 1, math.min(#list, max_listed) do
      local record = list[i]
      if enrich then record = enrich(record) end
      out[i] = strip(record)
    end
    if #list > max_listed then truncated = true end
    return out
  end
  local listed_stopped, listed_drills = cut(stopped), cut(drills)

  local result = {
    totals = totals, groups = group_list,
    stopped = listed_stopped, drills = listed_drills, truncated = truncated,
  }
  -- fit the budget: drop from the longer list's tail until the encoded reply fits
  while #helpers.table_to_json(result) > budget_bytes and (#listed_stopped + #listed_drills + #group_list) > 0 do
    truncated = true
    if #listed_stopped >= #listed_drills and #listed_stopped > 0 then
      listed_stopped[#listed_stopped] = nil
    elseif #listed_drills > 0 then
      listed_drills[#listed_drills] = nil
    else
      group_list[#group_list] = nil
    end
  end
  result.truncated = truncated
  return result
end

return M
