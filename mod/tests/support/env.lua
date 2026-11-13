-- Fake Factorio globals for the pure-Lua tests. Call env.fresh() at the start of a test: it
-- unloads the mod modules and installs clean fakes, so module-level state never leaks between tests.
local json = require("support.json")

local M = {}

function M.fresh()
  for name in pairs(package.loaded) do
    if name:match("^scripts%.") then package.loaded[name] = nil end
  end
  local e = { printed = {}, player_printed = {}, logged = {}, active_mods = { base = "2.1.24" } }
  e.json = json

  _G.rcon = { print = function(msg) e.printed[#e.printed + 1] = msg end }
  _G.log = function(msg) e.logged[#e.logged + 1] = tostring(msg) end
  _G.helpers = {
    table_to_json = function(t) return json.encode(t) end,
    -- the real function returns nil or raises on garbage; the tests exercise both through pcall
    json_to_table = function(s) return json.decode(s) end,
  }
  _G.game = {
    get_player = function(index)
      return { index = index, print = function(msg) e.player_printed[#e.player_printed + 1] = msg end }
    end,
  }
  _G.script = { active_mods = e.active_mods }
  _G.settings = { startup = {}, global = {} }
  _G.storage = {}
  _G.commands = { add_command = function(name, help, fn) e.command = { name = name, help = help, fn = fn } end }
  return e
end

return M
