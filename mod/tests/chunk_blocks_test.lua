-- Tests for chunk_blocks: the 512-tile blocks that hold generated chunks, kept in storage by
-- on_chunk_generated. A whole-map job visits these blocks only: a far-away chunk adds one block, not
-- the whole bounding box between it and the base.
package.path = "factorio-mcp/?.lua;tests/?.lua;" .. package.path
local env = require("support.env")
env.fresh()
local blocks = require("scripts.logic.chunk_blocks")

local walks = 0
local function surface(index, chunks)
  return { index = index, name = "s" .. index, valid = true,
    get_chunks = function()
      walks = walks + 1
      local i = 0
      return function() i = i + 1; return chunks[i] end
    end }
end

local function list(set)
  local out = {}
  for _, b in ipairs(blocks.sorted(set)) do out[#out + 1] = b.bx .. "," .. b.by end
  return table.concat(out, " ")
end

-- walk: one block per 16x16 chunks that hold any chunk, nil for none; key and decode round-trip
local s1 = surface(1, { { x = 0, y = 0 }, { x = 15, y = 15 }, { x = -1, y = 0 }, { x = 3000, y = -3000 } })
local set = blocks.walk(s1)
assert(list(set) == "-1,0 0,0 187,-188", "got " .. list(set))
assert(blocks.walk(surface(9, {})) == nil)
local bx, by = blocks.decode(blocks.key(-187, 42))
assert(bx == -187 and by == 42)

-- remember + cached: kept per surface index, so the second plan does not walk
walks = 0
assert(blocks.cached(s1) == nil)
blocks.remember(s1, blocks.walk(s1))
assert(walks == 1 and list(blocks.cached(s1)) == "-1,0 0,0 187,-188")
-- a generated chunk adds its block (the event handler path), an already known block adds nothing
blocks.on_chunk(s1, 20, 1)
blocks.on_chunk(s1, 21, 2)
assert(list(blocks.cached(s1)) == "-1,0 0,0 1,0 187,-188" and walks == 1)
-- a new surface's first chunk starts its set
local s2 = surface(2, {})
blocks.on_chunk(s2, -5, -6)
assert(list(blocks.cached(s2)) == "-1,-1")
-- a deleted or cleared surface is forgotten
blocks.forget(2)
assert(blocks.cached(s2) == nil)

-- rebuild: every surface walked once (on_init / on_configuration_changed), the older bounding-box
-- storage of unreleased builds dropped
walks = 0
_G.storage.mcp_bounds = { [1] = { minx = 0 } }
_G.game.surfaces = { s1 = s1, s3 = surface(3, { { x = 1, y = 1 } }) }
blocks.rebuild()
assert(walks == 2 and list(blocks.cached(s1)) == "-1,0 0,0 187,-188", "rebuilt from the chunks")
assert(list(blocks.cached({ index = 3 })) == "0,0" and _G.storage.mcp_bounds == nil)

-- a surface without an index (test doubles) is never cached
local anon = { get_chunks = s1.get_chunks }
blocks.remember(anon, { [blocks.key(0, 0)] = true })
assert(blocks.cached(anon) == nil)

print("chunk_blocks_test ok")
