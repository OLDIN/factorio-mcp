-- factorio-mcp: read-only queries for an external MCP service, over RCON.
-- One console command, `/factorio-mcp <sub> <json>`, dispatching to fixed read-only functions.
-- It refuses players (server/RCON only). The mod does nothing in the background.

local dispatcher = require("scripts.dispatcher")
local jobs = require("scripts.jobs")
require("scripts.commands.hello")
require("scripts.commands.server_info")
require("scripts.commands.players")
require("scripts.commands.proto")
require("scripts.commands.area")
require("scripts.commands.defenses")
require("scripts.commands.production")
require("scripts.commands.power")
require("scripts.commands.research")
require("scripts.commands.threats")
require("scripts.commands.pollution")
require("scripts.commands.logistics")
require("scripts.commands.trains")
require("scripts.commands.platforms")
require("scripts.commands.personal")
require("scripts.commands.resources")
require("scripts.commands.transport")
require("scripts.commands.job")

commands.add_command(
  "factorio-mcp",
  "Internal: read-only queries for the factorio-mcp service (server/RCON only).",
  dispatcher.run
)

-- Tick-split jobs: no handler unless one is running. on_load only re-registers it from `storage`
-- (it must not write to storage); on_init / on_configuration_changed may create the state.
script.on_init(function()
  jobs.state()
  jobs.sync_handler()
end)

script.on_configuration_changed(function()
  jobs.state()
  jobs.sync_handler()
end)

script.on_load(function()
  jobs.sync_handler()
end)
