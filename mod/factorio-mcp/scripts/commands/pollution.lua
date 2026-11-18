-- `pollution` subcommand: the surface's pollutant (smoke, spores, ...), a chunk grid around a point,
-- the biggest polluters on the surface, and enemy spawners that pollution reaches.
-- Params: {caller, player?} or {caller, surface, x, y}; grid? (odd, 1..15 chunks, default 9), limit? (1..30, default 10).
local dispatcher = require("scripts.dispatcher")
local caller = require("scripts.logic.caller")
local params_lib = require("scripts.logic.params")
local geo = require("scripts.logic.geo")
local pollution_logic = require("scripts.logic.pollution_logic")
local threats_logic = require("scripts.logic.threats_logic")

local function round1(v) return math.floor(v * 10 + 0.5) / 10 end

-- pollution statistics of the surface: emitted per minute by entity name (top `limit`)
local function sources(surface, limit)
  local ok, stats = pcall(game.get_pollution_statistics, surface)
  if not ok or not stats then return {} end
  local list = {}
  for name in pairs(stats.input_counts) do
    local per_minute = stats.get_flow_count({ name = name, category = "input",
      precision_index = defines.flow_precision_index.one_minute, count = false })
    if per_minute > 0 then list[#list + 1] = { name = name, per_minute = round1(per_minute) } end
  end
  table.sort(list, function(a, b) return a.per_minute > b.per_minute end)
  for i = #list, limit + 1, -1 do list[i] = nil end
  return list
end

dispatcher.register("pollution", function(p)
  local force = caller.force(p)
  local grid = pollution_logic.check_grid(params_lib.int(p, "grid", 9, 1, 99))
  local limit = params_lib.int(p, "limit", 10, 1, 30)
  local surface, center = caller.center(p)
  local cells = pollution_logic.grid(function(pos) return surface.get_pollution(pos) end, center, grid)
  local top = {}
  for i, c in ipairs(pollution_logic.top(cells, limit)) do
    top[i] = { gps = geo.gps(surface.name, c.x, c.y), amount = c.amount }
  end
  local fed = {}
  local enemies = threats_logic.enemy_force_names(force, game.forces)
  if #enemies > 0 then
    local spawners = surface.find_entities_filtered({ area = pollution_logic.bounds(center, grid),
      type = "unit-spawner", force = enemies })
    for _, s in ipairs(spawners) do
      local amount = surface.get_pollution(s.position)
      if amount > 0 and #fed < limit then
        fed[#fed + 1] = { name = s.name, gps = geo.gps(surface.name, s.position.x, s.position.y), amount = round1(amount) }
      end
    end
  end
  local pollutant = surface.pollutant_type
  return {
    surface = surface.name, pollutant = pollutant and pollutant.name or nil,
    total = round1(surface.get_total_pollution()),
    center = { surface = surface.name, x = center.x, y = center.y }, grid = grid,
    top_cells = top, sources = sources(surface, 10), fed_spawners = fed,
  }
end)
