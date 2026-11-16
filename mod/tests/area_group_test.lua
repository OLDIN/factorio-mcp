package.path = "factorio-mcp/?.lua;tests/?.lua;" .. package.path
local env = require("support.env")
env.fresh()
local area_group = require("scripts.logic.area_group")

local function rec(name, status, dist, extra)
  local r = { name = name, type = "assembling-machine", x = dist, y = 0, dist = dist, status = status, recipe = "gear" }
  for k, v in pairs(extra or {}) do r[k] = v end
  return r
end

local records = {
  rec("asm", "working", 1), rec("asm", "working", 2), rec("asm", "working", 3),
  rec("asm", "no_ingredients", 9), rec("asm", "no_ingredients", 4), rec("asm", "full_output", 6),
}
local res = area_group.build(records, 20, 100000)
assert(res.totals.machines == 6 and res.totals.working == 3)
assert(res.totals.by_status.no_ingredients == 2 and res.totals.by_status.full_output == 1)
assert(#res.groups == 1 and res.groups[1].count == 6 and res.groups[1].working == 3)
assert(#res.stopped == 3 and res.truncated == false)
assert(res.stopped[1].dist == nil and res.stopped[1].x == 4, "nearest first, internals stripped")
assert(res.stopped[3].x == 9)

-- max_listed cuts the list but totals stay complete
res = area_group.build(records, 2, 100000)
assert(#res.stopped == 2 and res.truncated == true and res.totals.machines == 6)

-- the encoded reply never exceeds the budget
local many = {}
for i = 1, 200 do many[i] = rec("asm", "no_ingredients", i) end
res = area_group.build(many, 200, 3000)
assert(#helpers.table_to_json(res) <= 3000 and res.truncated == true and res.totals.machines == 200)

-- drills: about-to-run-dry first; enrich only runs for listed records
local enriched = 0
local drills = {
  rec("drill", "working", 1, { type = "mining-drill", remaining = 5000, resource = "iron-ore" }),
  rec("drill", "no_minable_resources", 2, { type = "mining-drill", remaining = 0, resource = "iron-ore" }),
}
res = area_group.build(drills, 20, 100000, function(r) enriched = enriched + 1; return r end)
assert(res.drills[1].remaining == 0 and #res.stopped == 0 and enriched == 2)
print("area_group_test ok")
