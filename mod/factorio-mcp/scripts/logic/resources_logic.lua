-- Resource patches: entities of the same resource in touching chunks (8 neighbours) form one patch.
-- Records are plain tables {name, x, y, amount, fluid}; fluid resources (crude oil, ...) keep the
-- raw entity amount summed and count wells instead of tiles (no yield conversion).
local geo = require("scripts.logic.geo")

local M = {}

local CHUNK = 32

-- Whether a resource prototype yields a fluid (its first mining product is a fluid).
function M.is_fluid(prototype)
  local ok, fluid = pcall(function()
    local products = prototype.mineable_properties.products
    return products ~= nil and products[1] ~= nil and products[1].type == "fluid"
  end)
  return ok and fluid == true
end

-- numeric chunk key (no string building per tile); chunk coordinates stay far inside +-2^20
local OFFSET, SPAN = 2 ^ 20, 2 ^ 21
local function key_of(cx, cy) return (cx + OFFSET) * SPAN + (cy + OFFSET) end

-- Accumulator: per resource name, per chunk {cx, cy, amount, n, sx, sy}. Plain data (a job keeps it
-- in storage between ticks).
function M.new_acc()
  return { chunks = {}, fluid = {} }
end

function M.add(acc, name, x, y, amount, fluid)
  local chunks = acc.chunks[name]
  if not chunks then
    chunks = {}
    acc.chunks[name] = chunks
    acc.fluid[name] = fluid == true
  end
  local cx, cy = math.floor(x / CHUNK), math.floor(y / CHUNK)
  local key = key_of(cx, cy)
  local c = chunks[key]
  if not c then
    c = { cx = cx, cy = cy, amount = 0, n = 0, sx = 0, sy = 0 }
    chunks[key] = c
  end
  c.amount = c.amount + (amount or 0)
  c.n = c.n + 1
  c.sx = c.sx + x
  c.sy = c.sy + y
end

-- records: [{name, x, y, amount, fluid}] -> patches, largest (most tiles or wells) first
function M.patches(records, surface_name)
  local acc = M.new_acc()
  for _, r in ipairs(records) do M.add(acc, r.name, r.x, r.y, r.amount, r.fluid) end
  return M.finish(acc, surface_name)
end

-- patches of an accumulator, largest (most tiles or wells) first
function M.finish(acc, surface_name)
  local by_name, fluid_of = acc.chunks, acc.fluid
  local out = {}
  for name, chunks in pairs(by_name) do
    local seen = {}
    for key, start in pairs(chunks) do
      if not seen[key] then
        seen[key] = true
        local amount, n, sx, sy = 0, 0, 0, 0
        local stack = { start }
        while #stack > 0 do
          local c = table.remove(stack)
          amount, n, sx, sy = amount + c.amount, n + c.n, sx + c.sx, sy + c.sy
          for dx = -1, 1 do
            for dy = -1, 1 do
              local k = key_of(c.cx + dx, c.cy + dy)
              if chunks[k] and not seen[k] then
                seen[k] = true
                stack[#stack + 1] = chunks[k]
              end
            end
          end
        end
        local patch = { name = name, amount = amount, gps = geo.gps(surface_name, sx / n, sy / n), fluid = fluid_of[name] }
        if patch.fluid then patch.wells = n else patch.tiles = n end
        patch.size = n
        out[#out + 1] = patch
      end
    end
  end
  table.sort(out, function(a, b)
    if a.size ~= b.size then return a.size > b.size end
    if a.amount ~= b.amount then return a.amount > b.amount end
    return a.name < b.name
  end)
  for _, p in ipairs(out) do p.size = nil end
  return out
end

return M
