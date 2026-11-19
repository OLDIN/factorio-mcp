-- The 512-tile blocks (16x16 chunks) of each surface that hold generated chunks, kept in
-- storage.mcp_blocks[surface index] = {[key] = true}. A whole-map job visits only these blocks, so a
-- far-away chunk (a long trip, a radar outpost) adds one block, not the empty box between it and the
-- base. on_chunk_generated adds a block (one table lookup), so planning a job never walks every chunk
-- in one tick (~25 ms on a real map); the set is filled by a walk at load time (on_init /
-- on_configuration_changed). It never shrinks: a block whose chunks were deleted costs one empty count.
-- Plain data in storage, the same on every peer.
local M = {}

M.BLOCK_CHUNKS = 16 -- chunks per block side (512 tiles)

-- numeric key of a block; block coordinates stay far inside +-2^20
local OFFSET, SPAN = 2 ^ 20, 2 ^ 21
function M.key(bx, by) return (bx + OFFSET) * SPAN + (by + OFFSET) end
function M.decode(key)
  local bx = math.floor(key / SPAN)
  return math.floor(bx - OFFSET), math.floor(key - bx * SPAN - OFFSET)
end

local function block_key(cx, cy)
  return M.key(math.floor(cx / M.BLOCK_CHUNKS), math.floor(cy / M.BLOCK_CHUNKS))
end

local function store()
  if type(storage) ~= "table" then return nil end
  if not storage.mcp_blocks then storage.mcp_blocks = {} end
  return storage.mcp_blocks
end

-- one pass over all generated chunks; nil when there are none
function M.walk(surface)
  local set
  for chunk in surface.get_chunks() do
    set = set or {}
    set[block_key(chunk.x, chunk.y)] = true
  end
  return set
end

-- the stored set, or nil (never writes: safe to call anywhere)
function M.cached(surface)
  local all = type(storage) == "table" and storage.mcp_blocks or nil
  if not all or surface.index == nil then return nil end
  return all[surface.index]
end

function M.remember(surface, set)
  if set and surface.index ~= nil then
    local all = store()
    if all then all[surface.index] = set end
  end
  return set
end

-- on_chunk_generated
function M.on_chunk(surface, cx, cy)
  if surface.index == nil then return end
  local all = store()
  if not all then return end
  local set = all[surface.index]
  if not set then
    set = {}
    all[surface.index] = set
  end
  set[block_key(cx, cy)] = true
end

-- on_surface_deleted / on_surface_cleared
function M.forget(surface_index)
  local all = type(storage) == "table" and storage.mcp_blocks or nil
  if all then all[surface_index] = nil end
end

-- on_init / on_configuration_changed: walk every surface once
function M.rebuild()
  if type(storage) ~= "table" then return end
  storage.mcp_bounds = nil -- the bounding box kept by unreleased 0.4.0 builds
  storage.mcp_blocks = {}
  for _, surface in pairs(game.surfaces) do M.remember(surface, M.walk(surface)) end
end

-- [{bx, by}] of a set, in a stable order (by x, then y)
function M.sorted(set)
  local out = {}
  for key in pairs(set or {}) do
    local bx, by = M.decode(key)
    out[#out + 1] = { bx = bx, by = by }
  end
  table.sort(out, function(a, b)
    if a.bx ~= b.bx then return a.bx < b.bx end
    return a.by < b.by
  end)
  return out
end

return M
