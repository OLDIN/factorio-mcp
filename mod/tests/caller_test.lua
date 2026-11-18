-- Tests for caller (the token's nick -> player, force, centre) and params validation.
package.path = "factorio-mcp/?.lua;tests/?.lua;" .. package.path
local env = require("support.env")
env.fresh()

local force = { name = "player" }
local surface = { name = "nauvis" }
local players = {
  alice = { name = "alice", connected = true, force = force,
    physical_position = { x = 1.5, y = -2 }, physical_surface = surface },
  bob = { name = "bob", connected = false, force = force },
}
_G.game = {
  get_player = function(key) return players[key] end,
  get_surface = function(name) if name == "nauvis" then return surface end end,
}

local caller = require("scripts.logic.caller")
local params = require("scripts.logic.params")

local function err_of(fn, ...)
  local ok, e = pcall(fn, ...)
  assert(not ok, "expected an error")
  return e
end

-- caller
local e = err_of(caller.force, {})
assert(e.code == "bad_params" and e.message == "caller must be a string", "missing caller")
e = err_of(caller.force, { caller = 5 })
assert(e.code == "bad_params", "non-string caller")
e = err_of(caller.force, { caller = "nobody" })
assert(e.code == "not_found" and e.message == "no such player", "unknown caller")
assert(caller.force({ caller = "bob" }) == force, "offline caller still has a force")
assert(caller.player({ caller = "alice" }) == players.alice)

-- centre
local s, c = caller.center({ player = "alice" })
assert(s == surface and c.x == 1.5 and c.y == -2, "centre from an online player")
e = err_of(caller.center, { player = "bob" })
assert(e.code == "not_found" and e.message == "player is offline: position unknown", "offline centre")
e = err_of(caller.center, { player = "nobody" })
assert(e.code == "not_found" and e.message == "no such player")
s, c = caller.center({ surface = "nauvis", x = 3, y = 4 })
assert(s == surface and c.x == 3 and c.y == 4, "centre from a point")
e = err_of(caller.center, { surface = "mars", x = 0, y = 0 })
assert(e.code == "not_found" and e.message == "no such surface")
e = err_of(caller.center, {})
assert(e.code == "bad_params", "neither player nor surface")

-- params
assert(params.number({}, "r", 32) == 32)
assert(params.number({ r = 5 }, "r", 32) == 5)
assert(err_of(params.number, { r = 0 / 0 }, "r", 1).code == "bad_params", "NaN")
assert(err_of(params.number, { r = "5" }, "r", 1).code == "bad_params", "string")
assert(params.int({}, "n", 15, 1, 50) == 15)
assert(err_of(params.int, { n = 51 }, "n", 15, 1, 50).code == "bad_params", "above max")
assert(err_of(params.int, { n = 1.5 }, "n", 15, 1, 50).code == "bad_params", "fraction")
assert(params.string({}, "s") == nil)
assert(params.string({ s = "x" }, "s") == "x")
assert(err_of(params.string, { s = 1 }, "s").code == "bad_params")
assert(params.one_of({}, "w", "1m", { "5s", "1m" }) == "1m")
e = err_of(params.one_of, { w = "2m" }, "w", "1m", { "5s", "1m" })
assert(e.code == "bad_params" and e.message == "w must be one of: 5s, 1m", "one_of message")

print("caller_test ok")
