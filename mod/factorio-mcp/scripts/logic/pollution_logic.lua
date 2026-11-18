-- Pollution (smoke, spores, ...) on a grid of chunks around a point. The game stores pollution per
-- chunk, so one sample at each chunk centre is the whole picture.
local M = {}

local CHUNK = 32
local MAX_GRID = 15

local function round1(v) return math.floor(v * 10 + 0.5) / 10 end

function M.check_grid(grid)
  if grid % 2 ~= 1 or grid < 1 or grid > MAX_GRID then
    error({ code = "bad_params", message = "grid must be an odd number of chunks from 1 to " .. MAX_GRID })
  end
  return grid
end

local function first_chunk(center, grid)
  local half = (grid - 1) / 2
  return math.floor(center.x / CHUNK) - half, math.floor(center.y / CHUNK) - half
end

-- `sample(position) -> amount` -> [{x, y, amount}] at chunk centres, grid x grid chunks
function M.grid(sample, center, grid)
  local cx0, cy0 = first_chunk(center, grid)
  local cells = {}
  for dy = 0, grid - 1 do
    for dx = 0, grid - 1 do
      local pos = { x = (cx0 + dx) * CHUNK + CHUNK / 2, y = (cy0 + dy) * CHUNK + CHUNK / 2 }
      cells[#cells + 1] = { x = pos.x, y = pos.y, amount = sample(pos) }
    end
  end
  return cells
end

-- the polluted cells, most polluted first
function M.top(cells, limit)
  local list = {}
  for _, c in ipairs(cells) do
    if c.amount > 0 then list[#list + 1] = { x = c.x, y = c.y, amount = round1(c.amount) } end
  end
  table.sort(list, function(a, b) return a.amount > b.amount end)
  for i = #list, limit + 1, -1 do list[i] = nil end
  return list
end

-- {{x0, y0}, {x1, y1}} covering the grid's chunks
function M.bounds(center, grid)
  local cx0, cy0 = first_chunk(center, grid)
  return { { cx0 * CHUNK, cy0 * CHUNK }, { (cx0 + grid) * CHUNK, (cy0 + grid) * CHUNK } }
end

return M
