-- Space platforms: state, where they are or were, speed, damage and the hub's biggest stocks.
local M = {}

function M.state_names()
  local out = {}
  for name, v in pairs(defines.space_platform_state) do out[v] = name end
  return out
end

local function hub_contents(hub, limit)
  if not hub or not hub.valid then return {} end
  local ok, inv = pcall(hub.get_inventory, defines.inventory.hub_main)
  if not ok or not inv or not inv.valid then return {} end
  local list = {}
  for _, it in ipairs(inv.get_contents()) do list[#list + 1] = { name = it.name, quality = it.quality, count = it.count } end
  table.sort(list, function(a, b) return a.count > b.count end)
  for i = #list, limit + 1, -1 do list[i] = nil end
  return list
end

function M.record(platform, names, limit)
  local loc = platform.space_location
  local last = platform.last_visited_space_location
  return {
    name = platform.name, state = names[platform.state] or tostring(platform.state),
    location = loc and loc.name or nil, last_location = last and last.name or nil,
    speed = platform.speed, distance = platform.distance,
    damaged_tiles = #(platform.damaged_tiles or {}),
    hub_contents = hub_contents(platform.hub, limit),
  }
end

return M
