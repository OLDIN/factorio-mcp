-- Pure-Lua tests for scripts/envelope.lua
package.path = "factorio-mcp/?.lua;tests/?.lua;" .. package.path
local env = require("support.env")
local json = require("support.json")

local e = env.fresh()
local envelope = require("scripts.envelope")

-- sanitize drops non-finite numbers (NaN, +inf, -inf) and keeps the rest
local clean = envelope.sanitize({ a = 0 / 0, b = 1 / 0, c = 1, d = -1 / 0, nested = { x = 0 / 0, y = 2 } })
assert(clean.c == 1)
assert(clean.a == nil and clean.b == nil and clean.d == nil)
assert(clean.nested.x == nil and clean.nested.y == 2)

-- arrays are compacted instead of getting holes
local arr = envelope.sanitize({ 1, 0 / 0, 3 })
assert(#arr == 2 and arr[1] == 1 and arr[2] == 3)

-- the input is not mutated
local src = { a = 0 / 0 }
envelope.sanitize(src)
assert(src.a ~= src.a)

-- ok / err envelopes carry the protocol version and are single-line JSON
local ok = envelope.ok({ answer = 42, bad = 1 / 0 })
local decoded = json.decode(ok)
assert(decoded.v == 1 and decoded.ok == true and decoded.result.answer == 42 and decoded.result.bad == nil)
assert(not ok:find("\n"))

local err = json.decode(envelope.err("not_found", "no such player\nbob"))
assert(err.v == 1 and err.ok == false and err.error.code == "not_found")
assert(not envelope.err("x", "line1\nline2"):find("\n"))

-- a result already encoded (and sanitized) by its handler is wrapped, not encoded a second time
local pre = envelope.ok_encoded('{"answer":42}')
local pd = json.decode(pre)
assert(pd.v == 1 and pd.ok == true and pd.result.answer == 42 and not pre:find("\n"))
-- encode_result: sanitized and encoded once, usable as both a size check and the reply
local enc = envelope.encode_result({ a = 1, bad = 0 / 0 })
assert(json.decode(enc).a == 1 and json.decode(enc).bad == nil)

print("envelope_test ok")
