-- Tests for chunk_bounds: the bounding box of generated chunks, kept in storage by on_chunk_generated
-- so that planning a job never walks every chunk of a big map in one tick.
package.path = "factorio-mcp/?.lua;tests/?.lua;" .. package.path
local env = require("support.env")
env.fresh()
local bounds = require("scripts.logic.chunk_bounds")

local walks = 0
local function surface(index, chunks)
  return { index = index, name = "s" .. index, valid = true,
    get_chunks = function()
      walks = walks + 1
      local i = 0
      return function() i = i + 1; return chunks[i] end
    end }
end

-- walk: the box of all chunks, nil for none
local s1 = surface(1, { { x = 0, y = 0 }, { x = -3, y = 5 }, { x = 7, y = -2 } })
local b = bounds.walk(s1)
assert(b.minx == -3 and b.miny == -2 and b.maxx == 7 and b.maxy == 5)
assert(bounds.walk(surface(9, {})) == nil)

-- extend: grows only
local e = bounds.extend(nil, 2, 3)
assert(e.minx == 2 and e.maxx == 2 and e.miny == 3 and e.maxy == 3)
bounds.extend(e, -1, 10)
bounds.extend(e, 0, 4)
assert(e.minx == -1 and e.maxx == 2 and e.miny == 3 and e.maxy == 10)

-- remember + cached: kept per surface index in storage, so the second plan does not walk
walks = 0
assert(bounds.cached(s1) == nil)
bounds.remember(s1, bounds.walk(s1))
assert(walks == 1 and bounds.cached(s1).maxx == 7)
-- a generated chunk widens the cached box (the event handler path)
bounds.on_chunk(s1, 20, 0)
assert(bounds.cached(s1).maxx == 20 and walks == 1)
-- a new surface's first chunk starts its box
local s2 = surface(2, {})
bounds.on_chunk(s2, -5, -6)
assert(bounds.cached(s2).minx == -5 and bounds.cached(s2).maxy == -6)
-- a deleted or cleared surface is forgotten
bounds.forget(2)
assert(bounds.cached(s2) == nil)

-- rebuild: every surface walked once (on_init / on_configuration_changed, i.e. at load time)
walks = 0
_G.game.surfaces = { s1 = s1, s3 = surface(3, { { x = 1, y = 1 } }) }
bounds.rebuild()
assert(walks == 2 and bounds.cached(s1).maxx == 7, "rebuilt from the chunks, the old widening is gone")
assert(bounds.cached({ index = 3 }).minx == 1)

-- a surface without an index (test doubles) is never cached
local anon = { get_chunks = s1.get_chunks }
bounds.remember(anon, { minx = 0, miny = 0, maxx = 0, maxy = 0 })
assert(bounds.cached(anon) == nil)

print("chunk_bounds_test ok")
