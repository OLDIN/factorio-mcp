-- Pure-Lua tests for format_player and redact_settings
package.path = "factorio-mcp/?.lua;tests/?.lua;" .. package.path
local env = require("support.env")

env.fresh()
local player_format = require("scripts.logic.player_format")
local format_player = player_format.format_player
local redact_settings = player_format.redact_settings

-- 1. format_player tests
-- connected player has online = true and retains position / surface
local online_p = format_player({
  name = "alice",
  index = 1,
  connected = true,
  admin = true,
  afk_time = 120,
  online_time = 3600,
  color = { r = 1, g = 0, b = 0, a = 1 },
  position = { x = 10.5, y = -20.25 },
  surface = "nauvis",
})
assert(online_p.name == "alice")
assert(online_p.index == 1)
assert(online_p.online == true)
assert(online_p.admin == true)
assert(online_p.afk_ticks == 120)
assert(online_p.online_ticks == 3600)
assert(online_p.position ~= nil and online_p.position.x == 10.5 and online_p.position.y == -20.25)
assert(online_p.surface == "nauvis")

-- offline player has online = false and position = nil, surface = nil
local offline_p = format_player({
  name = "bob",
  index = 2,
  connected = false,
  admin = false,
  afk_time = 0,
  online_time = 1000,
  color = { r = 0, g = 1, b = 0, a = 1 },
  position = { x = 100, y = 200 },
  surface = "vulcanus",
})
assert(offline_p.name == "bob")
assert(offline_p.index == 2)
assert(offline_p.online == false)
assert(offline_p.position == nil, "offline player position must be nil")
assert(offline_p.surface == nil, "offline player surface must be nil")

-- 2. redact_settings tests
local raw_settings = {
  startup = {
    ["api-token"] = { value = "secret_123" },
    ["speed"] = { value = 2 },
    ["secret-password"] = { value = "pass" },
    ["auth_key"] = { value = "key_val" },
    ["max_players"] = { value = 10 },
  },
  runtime_global = {
    ["service_token"] = { value = "tok_xyz" },
    ["enable_feature"] = { value = true },
  },
}

local redacted = redact_settings(raw_settings)
assert(redacted.startup["speed"] ~= nil and redacted.startup["speed"].value == 2)
assert(redacted.startup["max_players"] ~= nil and redacted.startup["max_players"].value == 10)
assert(redacted.startup["api-token"] == nil, "api-token must be redacted")
assert(redacted.startup["secret-password"] == nil, "secret-password must be redacted")
assert(redacted.startup["auth_key"] == nil, "auth_key must be redacted")
assert(redacted.runtime_global["service_token"] == nil, "service_token must be redacted")
assert(redacted.runtime_global["enable_feature"] ~= nil and redacted.runtime_global["enable_feature"].value == true)

print("players_format_test ok")
