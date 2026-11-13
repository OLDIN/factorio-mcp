-- The single console command `/factorio-mcp <sub> <json-object>`. Each <sub> is a fixed, read-only
-- Lua function registered here; there is no way to run arbitrary code through this command.
local envelope = require("scripts.envelope")
local limits = require("scripts.limits")

local M = {}

local handlers = {}

function M.register(name, handler)
  assert(type(name) == "string" and name:match("^[a-z_]+$"), "bad command name: " .. tostring(name))
  assert(type(handler) == "function", "handler must be a function")
  handlers[name] = handler
end

function M.names()
  local names = {}
  for name in pairs(handlers) do names[#names + 1] = name end
  table.sort(names)
  return names
end

local function fail(code, message)
  return envelope.err(code, message)
end

-- Builds the single-line reply for a parameter string. Never raises.
function M.execute(parameter)
  parameter = parameter or ""
  if #parameter > limits.MAX_PARAM_BYTES then
    return fail("bad_params", "parameter too long")
  end
  local sub, rest = parameter:match("^%s*(%S+)%s*(.-)%s*$")
  if not sub or not sub:match("^[a-z_]+$") then
    return fail("bad_params", "expected: <command> <json-object>")
  end
  local handler = handlers[sub]
  if not handler then
    return fail("unknown_command", "unknown command: " .. sub)
  end

  local params = {}
  if rest ~= "" then
    if rest:sub(1, 1) ~= "{" then
      return fail("bad_params", "parameters must be a JSON object")
    end
    local ok, decoded = pcall(helpers.json_to_table, rest)
    if not ok or type(decoded) ~= "table" then
      return fail("bad_params", "parameters are not valid JSON")
    end
    params = decoded
  end

  local called, result = pcall(handler, params)
  if not called then
    if type(result) == "table" and type(result.code) == "string" then
      return fail(result.code, result.message)
    end
    log("factorio-mcp: command '" .. sub .. "' failed: " .. tostring(result))
    return fail("internal", "internal error")
  end
  if type(result) ~= "table" then
    log("factorio-mcp: command '" .. sub .. "' returned " .. type(result))
    return fail("internal", "internal error")
  end
  local encoded, reply = pcall(envelope.ok, result)
  if not encoded then
    log("factorio-mcp: command '" .. sub .. "' reply could not be encoded: " .. tostring(reply))
    return fail("internal", "internal error")
  end
  return reply
end

-- Entry point of the console command. Server/RCON only (player_index == nil).
function M.run(cmd)
  if cmd.player_index then
    local player = game.get_player(cmd.player_index)
    if player then player.print("factorio-mcp: server only") end
    return
  end
  rcon.print(M.execute(cmd.parameter))
end

return M
