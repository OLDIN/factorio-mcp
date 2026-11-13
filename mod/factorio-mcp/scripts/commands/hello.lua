-- `hello`: what this mod is, which commands it knows, and a fingerprint of the mod set.
local dispatcher = require("scripts.dispatcher")
local envelope = require("scripts.envelope")
local limits = require("scripts.limits")
local fingerprint = require("scripts.logic.fingerprint")

dispatcher.register("hello", function()
  local startup = {}
  for name, setting in pairs(settings.startup) do
    startup[name] = setting.value
  end
  return {
    mod_version = script.active_mods["factorio-mcp"],
    protocol = envelope.PROTOCOL,
    commands = dispatcher.names(),
    fingerprint = fingerprint.canonical(script.active_mods, startup),
    max_response_bytes = limits.RESPONSE_BUDGET_BYTES,
  }
end)
