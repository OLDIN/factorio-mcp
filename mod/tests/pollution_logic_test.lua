-- Tests for pollution_logic: a chunk grid around a point and its most polluted cells.
package.path = "factorio-mcp/?.lua;tests/?.lua;" .. package.path
local env = require("support.env")
env.fresh()
local pollution_logic = require("scripts.logic.pollution_logic")

-- one hot chunk at chunk (2, -1): its centre is (80, -16)
local function sample(pos)
  if pos.x == 80 and pos.y == -16 then return 500 end
  if pos.x == 16 and pos.y == 16 then return 3.333 end
  return 0
end

local cells = pollution_logic.grid(sample, { x = 10, y = 10 }, 5)
assert(#cells == 25, "5 x 5 chunks")
local top = pollution_logic.top(cells, 10)
assert(#top == 2, "only cells with pollution")
assert(top[1].x == 80 and top[1].y == -16 and top[1].amount == 500, "hottest first")
assert(top[2].amount == 3.3, "rounded to one decimal")
assert(#pollution_logic.top(cells, 1) == 1)

-- an even grid has no centre chunk
local ok, err = pcall(pollution_logic.check_grid, 4)
assert(not ok and err.code == "bad_params")
assert(pollution_logic.check_grid(9) == 9)
local ok2, err2 = pcall(pollution_logic.check_grid, 17)
assert(not ok2 and err2.code == "bad_params", "at most 15")

-- the grid's bounding box (for finding spawners inside it)
local box = pollution_logic.bounds({ x = 10, y = 10 }, 5)
assert(box[1][1] == -64 and box[1][2] == -64 and box[2][1] == 96 and box[2][2] == 96)

print("pollution_logic_test ok")
