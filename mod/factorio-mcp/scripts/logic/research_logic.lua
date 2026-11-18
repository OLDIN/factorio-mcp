-- Research: technologies that can be researched now, one technology's state, paging.
local M = {}

local function all_researched(prerequisites)
  for _, p in pairs(prerequisites) do
    if not p.researched then return false end
  end
  return true
end

-- names of enabled, not yet researched technologies whose prerequisites are all researched (sorted)
function M.available(technologies)
  local out = {}
  for name, t in pairs(technologies) do
    if t.enabled and not t.researched and all_researched(t.prerequisites) then out[#out + 1] = name end
  end
  table.sort(out)
  return out
end

function M.state(t)
  local missing = {}
  for name, p in pairs(t.prerequisites) do
    if not p.researched then missing[#missing + 1] = name end
  end
  table.sort(missing)
  local ingredients = {}
  for i, ing in ipairs(t.research_unit_ingredients or {}) do
    ingredients[i] = { name = ing.name, amount = ing.amount }
  end
  return {
    name = t.name, level = t.level, researched = t.researched, enabled = t.enabled,
    progress = t.saved_progress, unit_count = t.research_unit_count,
    ingredients = ingredients, missing_prerequisites = missing,
  }
end

-- {total, offset, items, next}
function M.page(list, offset, limit)
  local items = {}
  for i = offset + 1, math.min(offset + limit, #list) do items[#items + 1] = list[i] end
  local nxt = nil
  if offset + limit < #list then nxt = offset + limit end
  return { total = #list, offset = offset, items = items, next = nxt }
end

return M
