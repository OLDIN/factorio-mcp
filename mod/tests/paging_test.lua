-- Pure-Lua tests for scripts/logic/paging.lua
package.path = "factorio-mcp/?.lua;tests/?.lua;" .. package.path
local env = require("support.env")
env.fresh()
local paging = require("scripts.logic.paging")

local names = {}
for i = 1, 10 do names[i] = "n" .. i end
local function render(name) return { name = name, pad = string.rep("x", 100) } end
local one = #helpers.table_to_json(render("n1")) + 1

-- whole list fits: no next
local items, nxt = paging.page(names, 0, 50, render, 100000)
assert(#items == 10 and nxt == nil)

-- limit smaller than the list: next points at the first item not returned
items, nxt = paging.page(names, 0, 4, render, 100000)
assert(#items == 4 and nxt == 4 and items[1].name == "n1")
items, nxt = paging.page(names, 4, 4, render, 100000)
assert(#items == 4 and items[1].name == "n5" and nxt == 8)
items, nxt = paging.page(names, 8, 4, render, 100000)
assert(#items == 2 and nxt == nil and items[2].name == "n10")

-- limit larger than the budget allows: fewer items and a next
items, nxt = paging.page(names, 0, 10, render, one * 3 + 1)
assert(#items == 3 and nxt == 3, "got " .. #items)

-- one item bigger than the whole budget is still returned
items, nxt = paging.page(names, 0, 10, render, 5)
assert(#items == 1 and nxt == 1)

-- offset past the end: empty page, no next
items, nxt = paging.page(names, 20, 5, render, 1000)
assert(#items == 0 and nxt == nil)

print("paging_test ok")
