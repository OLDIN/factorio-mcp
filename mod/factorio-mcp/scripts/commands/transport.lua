-- `transport` subcommand: belts, inserters and pipes of the caller's force around a point or a player.
-- Params: {caller, player?} or {caller, surface, x, y}; radius? (default 16, at most 32), limit? (1..30, default 15).
-- Up to TRANSPORT_FULL_READ_MAX entities everything is read; a crowded area is counted per name and only
-- sampled in detail (reply has sampled = true), so a packed bus stays around a couple of milliseconds.
local dispatcher = require("scripts.dispatcher")
local caller = require("scripts.logic.caller")
local params_lib = require("scripts.logic.params")
local geo = require("scripts.logic.geo")
local statuses = require("scripts.statuses")
local transport_logic = require("scripts.logic.transport_logic")
local limits = require("scripts.limits")

local MAX_RADIUS = 32

-- items on all transport lines of one belt, loader or splitter (one pcall per belt, no closures per line)
local function read_lines(e, acc)
  for i = 1, e.get_max_transport_line_index() do
    transport_logic.add_belt_items(acc, e.get_transport_line(i).get_contents())
  end
end

-- entity prototype names of one type (static for the session; only shapes the reply, never storage)
local names_by_type = {}
local function names_of(entity_type)
  local names = names_by_type[entity_type]
  if not names then
    names = {}
    for name in pairs(prototypes.get_entity_filtered({ { filter = "type", type = entity_type } })) do
      names[#names + 1] = name
    end
    table.sort(names)
    names_by_type[entity_type] = names
  end
  return names
end

local BELT_LIST, FLUID_LIST = {}, {}
for t in pairs(transport_logic.BELT_TYPES) do BELT_LIST[#BELT_LIST + 1] = t end
for t in pairs(transport_logic.FLUID_TYPES) do FLUID_LIST[#FLUID_LIST + 1] = t end
table.sort(BELT_LIST)
table.sort(FLUID_LIST)

local function add_inserter(acc, surface, e)
  local pos = e.position
  transport_logic.add_inserter(acc, { name = e.name, status = statuses.name(e.status),
    gps = geo.gps(surface.name, pos.x, pos.y) })
end

-- Every entity read: fine up to limits.TRANSPORT_FULL_READ_MAX entities (~1-1.5 us each).
local function read_all(acc, surface, area)
  for _, e in ipairs(surface.find_entities_filtered(area)) do
    local t = e.type
    transport_logic.count(acc, e.name)
    if t == "inserter" then
      add_inserter(acc, surface, e)
    elseif transport_logic.BELT_TYPES[t] then
      if transport_logic.take_belt(acc) then pcall(read_lines, e, acc) end
    elseif transport_logic.FLUID_TYPES[t] then
      transport_logic.add_entity_fluids(acc, e)
    end
  end
end

-- A crowded area (a packed bus): counts per name from count_entities_filtered (no entity is touched),
-- and only a limited number of inserters, belts and fluid boxes read.
local function read_sample(acc, surface, area)
  local function counted(filter)
    local q = { position = area.position, radius = area.radius, force = area.force }
    for k, v in pairs(filter) do q[k] = v end
    return surface.count_entities_filtered(q)
  end
  local totals = { inserters = 0, belts = 0 }
  for _, entity_type in ipairs(transport_logic.TYPES) do
    local n = counted({ type = entity_type })
    if n > 0 then
      if entity_type == "inserter" then totals.inserters = n end
      if transport_logic.BELT_TYPES[entity_type] then totals.belts = totals.belts + n end
      for _, name in ipairs(names_of(entity_type)) do
        local c = counted({ name = name })
        if c > 0 then transport_logic.count(acc, name, c) end
      end
    end
  end
  transport_logic.sampled(acc, totals)
  local function find(types, limit)
    return surface.find_entities_filtered({ position = area.position, radius = area.radius, force = area.force,
      type = types, limit = limit })
  end
  for _, e in ipairs(find("inserter", limits.TRANSPORT_SAMPLE_READS)) do add_inserter(acc, surface, e) end
  for _, e in ipairs(find(BELT_LIST, limits.MAX_TRANSPORT_BELT_READS)) do
    if transport_logic.take_belt(acc) then pcall(read_lines, e, acc) end
  end
  for _, e in ipairs(find(FLUID_LIST, limits.TRANSPORT_SAMPLE_READS)) do transport_logic.add_entity_fluids(acc, e) end
end

dispatcher.register("transport", function(p)
  local force = caller.force(p)
  local radius = params_lib.number(p, "radius", 16)
  if radius <= 0 or radius > MAX_RADIUS then
    error({ code = "bad_params", message = "radius must be above 0 and at most " .. MAX_RADIUS })
  end
  local limit = params_lib.int(p, "limit", 15, 1, 30)
  local surface, center = caller.center(p)
  local area = { position = { x = center.x, y = center.y }, radius = radius, type = transport_logic.TYPES, force = force }
  local acc = transport_logic.new_acc(limit, limits.MAX_TRANSPORT_BELT_READS)
  local crowded = surface.count_entities_filtered({ position = area.position, radius = radius, type = area.type,
    force = force, limit = limits.TRANSPORT_FULL_READ_MAX + 1 }) > limits.TRANSPORT_FULL_READ_MAX
  if crowded then read_sample(acc, surface, area) else read_all(acc, surface, area) end
  local result = transport_logic.finish(acc)
  result.center = { surface = surface.name, x = center.x, y = center.y }
  result.radius = radius
  return result
end)
