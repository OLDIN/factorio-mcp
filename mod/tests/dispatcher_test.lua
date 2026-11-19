-- Pure-Lua tests for scripts/dispatcher.lua
package.path = "factorio-mcp/?.lua;tests/?.lua;" .. package.path
local env = require("support.env")

local e, dispatcher

local function setup()
  e = env.fresh()
  dispatcher = require("scripts.dispatcher")
  dispatcher.register("echo", function(params) return { got = params } end)
  dispatcher.register("fail_known", function() error({ code = "not_found", message = "no such player" }) end)
  dispatcher.register("boom", function() error("boom") end)
end

local function run(param, player_index)
  e.printed, e.player_printed = {}, {}
  dispatcher.run({ name = "factorio-mcp", tick = 1, parameter = param, player_index = player_index })
end

-- exactly one single-line JSON reply
local function reply()
  assert(#e.printed == 1, "expected exactly one rcon.print, got " .. #e.printed)
  assert(not e.printed[1]:find("\n"), "reply must be a single line")
  return e.json.decode(e.printed[1])
end

local function expect_error(code)
  local r = reply()
  assert(r.v == 1 and r.ok == false, "expected an error envelope: " .. e.printed[1])
  assert(r.error.code == code, "expected " .. code .. ", got " .. tostring(r.error.code))
  return r
end

setup()

-- unknown sub
run("nope {}")
expect_error("unknown_command")

-- missing sub / malformed sub name
run("")
expect_error("bad_params")
run(nil)
expect_error("bad_params")
run("BAD {}")
expect_error("bad_params")

-- a player (not the server/RCON) gets a chat line and no RCON output
run("echo {}", 3)
assert(#e.printed == 0, "rcon.print must not be called for players")
assert(#e.player_printed == 1 and e.player_printed[1]:find("server only"))

-- bad json and non-object parameters
run("echo {x")
expect_error("bad_params")
run("echo []")
expect_error("bad_params")
run("echo 5")
expect_error("bad_params")
run('echo "str"')
expect_error("bad_params")

-- too long parameter
local limits = require("scripts.limits")
run("echo {\"a\":\"" .. string.rep("x", limits.MAX_PARAM_BYTES) .. "\"}")
expect_error("bad_params")

-- happy path, with and without arguments
run('echo {"a":1}')
local r = reply()
assert(r.ok == true and r.result.got.a == 1)
run("echo")
r = reply()
assert(r.ok == true)

-- a handler raising a known error keeps its code
run("fail_known {}")
r = expect_error("not_found")
assert(r.error.message == "no such player")

-- any other Lua error becomes `internal` and leaks no stack
run("boom {}")
r = expect_error("internal")
assert(not r.error.message:find("stack traceback") and not r.error.message:find("boom"))
assert(#e.logged >= 1, "the real cause goes to the game log")

-- a handler result with non-finite numbers is sanitised, not crashed on
dispatcher.register("nan", function() return { x = 0 / 0, y = 1 } end)
run("nan {}")
r = reply()
assert(r.ok == true and r.result.x == nil and r.result.y == 1)

-- a handler may return the encoded result as a second value: the reply uses it as is
dispatcher.register("pre", function() return { x = 1 }, '{"x":2}' end)
run("pre {}")
r = reply()
assert(r.ok == true and r.result.x == 2, "the pre-encoded result is the reply")

-- names are sorted
dispatcher.register("alpha", function() return {} end)
local names = dispatcher.names()
for i = 2, #names do assert(names[i - 1] < names[i], "names must be sorted") end

-- invalid names are refused at registration
assert(not pcall(dispatcher.register, "Bad-Name", function() return {} end))

print("dispatcher_test ok")
