-- Distances, compass directions and [gps] tags. Factorio's y axis grows southwards.
local M = {}

local DIRECTIONS = { "E", "SE", "S", "SW", "W", "NW", "N", "NE" }
-- Factorio runs Lua 5.2 (math.atan2); the local test Lua may be newer (two-argument math.atan).
local atan2 = math.atan2 or math.atan

function M.distance(a, b)
  return math.sqrt((b.x - a.x) ^ 2 + (b.y - a.y) ^ 2)
end

-- One of 8 compass points from `from` towards `to`.
function M.direction(from, to)
  local angle = atan2(to.y - from.y, to.x - from.x) -- 0 = east, positive = south (clockwise)
  local sector = math.floor(angle / (math.pi / 4) + 0.5) % 8
  return DIRECTIONS[sector + 1]
end

local function round(v)
  local r = math.floor(v + 0.5)
  if r == 0 then r = 0 end -- no "-0"
  return string.format("%d", r)
end

function M.gps(surface_name, x, y)
  return "[gps=" .. round(x) .. "," .. round(y) .. "," .. surface_name .. "]"
end

return M
