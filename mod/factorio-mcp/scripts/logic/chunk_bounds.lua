-- Bounding box of each surface's generated chunks, kept in storage.mcp_bounds[surface index] =
-- {minx, miny, maxx, maxy} (chunk coordinates). on_chunk_generated widens it (a few comparisons), so
-- planning a whole-map job never walks every chunk in one tick (~25 ms on a real map). The box is
-- filled by a walk at load time (on_init / on_configuration_changed). It never shrinks: deleted chunks
-- only leave a few empty blocks to count. Plain data in storage, the same on every peer.
local M = {}

local function store()
  if type(storage) ~= "table" then return nil end
  if not storage.mcp_bounds then storage.mcp_bounds = {} end
  return storage.mcp_bounds
end

function M.extend(b, cx, cy)
  if not b then return { minx = cx, miny = cy, maxx = cx, maxy = cy } end
  if cx < b.minx then b.minx = cx elseif cx > b.maxx then b.maxx = cx end
  if cy < b.miny then b.miny = cy elseif cy > b.maxy then b.maxy = cy end
  return b
end

-- one pass over all generated chunks; nil when there are none
function M.walk(surface)
  local b
  for chunk in surface.get_chunks() do b = M.extend(b, chunk.x, chunk.y) end
  return b
end

-- the stored box, or nil (never writes: safe to call anywhere)
function M.cached(surface)
  local all = type(storage) == "table" and storage.mcp_bounds or nil
  if not all or surface.index == nil then return nil end
  return all[surface.index]
end

function M.remember(surface, b)
  if b and surface.index ~= nil then
    local all = store()
    if all then all[surface.index] = b end
  end
  return b
end

-- on_chunk_generated
function M.on_chunk(surface, cx, cy)
  if surface.index == nil then return end
  local all = store()
  if all then all[surface.index] = M.extend(all[surface.index], cx, cy) end
end

-- on_surface_deleted / on_surface_cleared
function M.forget(surface_index)
  local all = type(storage) == "table" and storage.mcp_bounds or nil
  if all then all[surface_index] = nil end
end

-- on_init / on_configuration_changed: walk every surface once
function M.rebuild()
  if type(storage) ~= "table" then return end
  storage.mcp_bounds = {}
  for _, surface in pairs(game.surfaces) do M.remember(surface, M.walk(surface)) end
end

return M
