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

local function chunk_of(v)
  local c = math.floor(v / CHUNK)
  if c == 0 then c = 0 end -- no "-0" key (Lua 5.2 numbers are doubles)
  return c
end

-- records: [{name, x, y, amount, fluid}] -> patches, largest (most tiles or wells) first
function M.patches(records, surface_name)
  -- name -> "cx,cy" -> {cx, cy, amount, n, sx, sy}
  local by_name, fluid_of = {}, {}
  for _, r in ipairs(records) do
    local chunks = by_name[r.name]
    if not chunks then
      chunks = {}
      by_name[r.name] = chunks
      fluid_of[r.name] = r.fluid == true
    end
    local cx, cy = chunk_of(r.x), chunk_of(r.y)
    local key = cx .. "," .. cy
    local c = chunks[key]
    if not c then
      c = { cx = cx, cy = cy, amount = 0, n = 0, sx = 0, sy = 0 }
      chunks[key] = c
    end
    c.amount = c.amount + (r.amount or 0)
    c.n = c.n + 1
    c.sx = c.sx + r.x
    c.sy = c.sy + r.y
  end

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
              local k = (c.cx + dx) .. "," .. (c.cy + dy)
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
