-- `transport` subcommand: belts, inserters and pipes of the caller's force around a point or a player.
-- Params: {caller, player?} or {caller, surface, x, y}; radius? (default 16, at most 32), limit? (1..30, default 15).
local dispatcher = require("scripts.dispatcher")
local caller = require("scripts.logic.caller")
local params_lib = require("scripts.logic.params")
local geo = require("scripts.logic.geo")
local statuses = require("scripts.statuses")
local transport_logic = require("scripts.logic.transport_logic")

local MAX_RADIUS = 32

local function belt_contents(e)
  local ok, n = pcall(e.get_max_transport_line_index)
  if not ok or not n then return {} end
  local out = {}
  for i = 1, n do
    local okl, contents = pcall(function() return e.get_transport_line(i).get_contents() end)
    if okl and contents then for _, it in ipairs(contents) do out[#out + 1] = it end end
  end
  return out
end

dispatcher.register("transport", function(p)
  local force = caller.force(p)
  local radius = params_lib.number(p, "radius", 16)
  if radius <= 0 or radius > MAX_RADIUS then
    error({ code = "bad_params", message = "radius must be above 0 and at most " .. MAX_RADIUS })
  end
  local limit = params_lib.int(p, "limit", 15, 1, 30)
  local surface, center = caller.center(p)
  local found = surface.find_entities_filtered({
    position = { x = center.x, y = center.y }, radius = radius, type = transport_logic.TYPES, force = force,
  })
  local acc = transport_logic.new_acc(limit)
  for _, e in ipairs(found) do
    if e.valid then
      local t = e.type
      transport_logic.count(acc, e.name)
      if t == "inserter" then
        transport_logic.add_inserter(acc, { name = e.name, status = statuses.name(e.status),
          gps = geo.gps(surface.name, e.position.x, e.position.y) })
      elseif transport_logic.BELT_TYPES[t] then
        transport_logic.add_belt_items(acc, belt_contents(e))
      elseif transport_logic.FLUID_TYPES[t] then
        transport_logic.add_entity_fluids(acc, e)
      end
    end
  end
  local result = transport_logic.finish(acc)
  result.center = { surface = surface.name, x = center.x, y = center.y }
  result.radius = radius
  return result
end)
