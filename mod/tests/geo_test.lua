-- Tests for geo: distance, compass direction (y grows southwards) and gps tags.
package.path = "factorio-mcp/?.lua;tests/?.lua;" .. package.path
local env = require("support.env")
env.fresh()
local geo = require("scripts.logic.geo")

assert(geo.distance({ x = 0, y = 0 }, { x = 3, y = 4 }) == 5)
assert(geo.direction({ x = 0, y = 0 }, { x = 0, y = -10 }) == "N")
assert(geo.direction({ x = 0, y = 0 }, { x = 10, y = 10 }) == "SE")
assert(geo.direction({ x = 0, y = 0 }, { x = -10, y = 0 }) == "W")
assert(geo.direction({ x = 0, y = 0 }, { x = 10, y = -10 }) == "NE")
assert(geo.direction({ x = 0, y = 0 }, { x = 0, y = 7 }) == "S")
assert(geo.direction({ x = 0, y = 0 }, { x = -5, y = 5 }) == "SW")
assert(geo.direction({ x = 0, y = 0 }, { x = -5, y = -5 }) == "NW")
assert(geo.direction({ x = 0, y = 0 }, { x = 9, y = 1 }) == "E")
assert(geo.gps("nauvis", 12.6, -3.2) == "[gps=13,-3,nauvis]", geo.gps("nauvis", 12.6, -3.2))
assert(geo.gps("nauvis", -0.4, 0) == "[gps=0,0,nauvis]", geo.gps("nauvis", -0.4, 0))
print("geo_test ok")
