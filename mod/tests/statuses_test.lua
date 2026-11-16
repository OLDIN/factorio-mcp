package.path = "factorio-mcp/?.lua;tests/?.lua;" .. package.path
local env = require("support.env")
env.fresh()
_G.defines = { entity_status = { working = 1, no_ingredients = 2, full_output = 3 } }
local statuses = require("scripts.statuses")
assert(statuses.name(1) == "working" and statuses.name(3) == "full_output")
assert(statuses.name(nil) == "none")
assert(statuses.name(999) == "unknown")
print("statuses_test ok")
