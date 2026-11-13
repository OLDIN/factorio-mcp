-- factorio-mcp: read-only queries for an external MCP service, over RCON.
-- One console command, `/factorio-mcp <sub> <json>`, dispatching to fixed read-only functions.
-- It refuses players (server/RCON only). The mod does nothing in the background.

local dispatcher = require("scripts.dispatcher")
require("scripts.commands.hello")

commands.add_command(
  "factorio-mcp",
  "Internal: read-only queries for the factorio-mcp service (server/RCON only).",
  dispatcher.run
)
