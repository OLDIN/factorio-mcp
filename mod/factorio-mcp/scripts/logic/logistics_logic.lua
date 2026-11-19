-- Logistic networks: robots, roboports, charging queues and the biggest stocks.
local geo = require("scripts.logic.geo")

local M = {}

function M.network(net, surface_name, limit)
  local cells = net.cells or {}
  local charging, gps = 0, nil
  for i, c in ipairs(cells) do
    charging = charging + (c.to_charge_robot_count or 0)
    if i == 1 and c.owner then gps = geo.gps(surface_name, c.owner.position.x, c.owner.position.y) end
  end
  local contents = {}
  for _, item in ipairs(net.get_contents() or {}) do
    contents[#contents + 1] = { name = item.name, quality = item.quality, count = item.count }
  end
  table.sort(contents, function(a, b)
    if a.count ~= b.count then return a.count > b.count end
    return a.name < b.name
  end)
  for i = #contents, limit + 1, -1 do contents[i] = nil end
  return {
    surface = surface_name, id = net.network_id, gps = gps, roboports = #cells, charging = charging,
    logistic_robots = { available = net.available_logistic_robots, total = net.all_logistic_robots },
    construction_robots = { available = net.available_construction_robots, total = net.all_construction_robots },
    top_contents = contents,
  }
end

local function share(n)
  local total = n.logistic_robots.total
  if total == 0 then return nil end
  return n.logistic_robots.available / total
end

-- the least available share of logistic robots first; networks without robots last
function M.sort_networks(list)
  table.sort(list, function(a, b)
    local sa, sb = share(a), share(b)
    if sa ~= sb then
      if sa == nil then return false end
      if sb == nil then return true end
      return sa < sb
    end
    if a.surface ~= b.surface then return a.surface < b.surface end
    return a.id < b.id
  end)
  return list
end

-- one item in a network's contents, all qualities summed
function M.count_item(contents, name)
  local n = 0
  for _, item in ipairs(contents) do
    if item.name == name then n = n + item.count end
  end
  return n
end

return M
