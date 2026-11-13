-- Pure-Lua tests for scripts/logic/fingerprint.lua
package.path = "factorio-mcp/?.lua;tests/?.lua;" .. package.path
local env = require("support.env")

env.fresh()
local fingerprint = require("scripts.logic.fingerprint")

-- deterministic: does not depend on insertion order
local a = fingerprint.canonical({ b = "2", a = "1" }, { z = true, y = 3 })
local b = fingerprint.canonical({ a = "1", b = "2" }, { y = 3, z = true })
assert(a == b, "order must not matter")
assert(type(a) == "string" and a ~= "")

-- a different mod version or startup value changes the fingerprint
assert(a ~= fingerprint.canonical({ a = "1", b = "3" }, { y = 3, z = true }))
assert(a ~= fingerprint.canonical({ a = "1", b = "2" }, { y = 4, z = true }))

-- structured (table) setting values are serialised deterministically
local c1 = fingerprint.canonical({}, { color = { r = 1, g = 2 } })
local c2 = fingerprint.canonical({}, { color = { g = 2, r = 1 } })
assert(c1 == c2)

-- secret-looking string settings never enter the fingerprint
local s1 = fingerprint.canonical({}, { ["api-token"] = "aaa", speed = 2 })
local s2 = fingerprint.canonical({}, { ["api-token"] = "bbb", speed = 2 })
assert(s1 == s2, "token-like settings must be ignored")
assert(not s1:find("aaa"))

print("fingerprint_test ok")
