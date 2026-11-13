-- `server_info` subcommand: tick, speed, mods, settings, surfaces.
local dispatcher = require("scripts.dispatcher")
local player_format = require("scripts.logic.player_format")

local function copy_pollution(p)
  if not p then return nil end
  return {
    enabled = p.enabled,
    diffusion_ratio = p.diffusion_ratio,
    min_to_diffuse = p.min_to_diffuse,
    ageing = p.ageing,
    expected_max_per_chunk = p.expected_max_per_chunk,
    min_to_show_per_chunk = p.min_to_show_per_chunk,
    min_pollution_to_damage_trees = p.min_pollution_to_damage_trees,
    pollution_with_max_forest_damage = p.pollution_with_max_forest_damage,
    pollution_per_tree_damage = p.pollution_per_tree_damage,
    pollution_restored_per_tree_damage = p.pollution_restored_per_tree_damage,
    enemy_attack_pollution_consumption_modifier = p.enemy_attack_pollution_consumption_modifier,
  }
end

local function copy_evolution(e)
  if not e then return nil end
  return {
    enabled = e.enabled,
    time_factor = e.time_factor,
    destroy_factor = e.destroy_factor,
    pollution_factor = e.pollution_factor,
  }
end

local function copy_expansion(e)
  if not e then return nil end
  return {
    enabled = e.enabled,
    max_expansion_distance = e.max_expansion_distance,
    friendly_base_influence_radius = e.friendly_base_influence_radius,
    enemy_building_influence_radius = e.enemy_building_influence_radius,
    building_coefficient = e.building_coefficient,
    other_base_coefficient = e.other_base_coefficient,
    neighbouring_chunk_coefficient = e.neighbouring_chunk_coefficient,
    neighbouring_base_chunk_coefficient = e.neighbouring_base_chunk_coefficient,
    min_expansion_distance = e.min_expansion_distance,
    max_expansion_cooldown = e.max_expansion_cooldown,
    min_expansion_cooldown = e.min_expansion_cooldown,
    settler_group_min_size = e.settler_group_min_size,
    settler_group_max_size = e.settler_group_max_size,
  }
end

local function copy_unit_group(u)
  if not u then return nil end
  return {
    min_group_gathering_time = u.min_group_gathering_time,
    max_group_gathering_time = u.max_group_gathering_time,
    max_wait_time_for_late_members = u.max_wait_time_for_late_members,
    max_group_radius = u.max_group_radius,
    min_group_radius = u.min_group_radius,
    max_member_speedup_when_behind = u.max_member_speedup_when_behind,
    max_member_slowdown_when_ahead = u.max_member_slowdown_when_ahead,
    max_group_slowdown_factor = u.max_group_slowdown_factor,
    max_gathering_unit_groups = u.max_gathering_unit_groups,
    max_unit_group_size = u.max_unit_group_size,
  }
end

local function copy_asteroids(a)
  if not a then return nil end
  return {
    spawning_rate = a.spawning_rate,
    max_ray_portals_expanded_per_tick = a.max_ray_portals_expanded_per_tick,
  }
end

local function copy_map_settings(m)
  if not m then return nil end
  return {
    pollution = copy_pollution(m.pollution),
    enemy_evolution = copy_evolution(m.enemy_evolution),
    enemy_expansion = copy_expansion(m.enemy_expansion),
    unit_group = copy_unit_group(m.unit_group),
    asteroids = copy_asteroids(m.asteroids),
    max_failed_behavior_count = m.max_failed_behavior_count,
  }
end

local function copy_difficulty(d)
  if not d then return nil end
  return {
    technology_price_multiplier = d.technology_price_multiplier,
    spoil_time_modifier = d.spoil_time_modifier,
  }
end

local function collect_settings(category)
  local result = {}
  if not category then return result end
  for name, s in pairs(category) do
    result[name] = { value = s.value }
  end
  return result
end

dispatcher.register("server_info", function()
  -- Surfaces list
  local surfaces = {}
  for _, s in pairs(game.surfaces) do
    surfaces[#surfaces + 1] = {
      name = s.name,
      planet = (s.planet and s.planet.valid and s.planet.name) or nil,
    }
  end

  -- Mod settings
  local raw_mod_settings = {
    startup = collect_settings(settings.startup),
    runtime_global = collect_settings(settings.global),
  }
  local redacted_settings = player_format.redact_settings(raw_mod_settings)

  return {
    tick = game.tick,
    ticks_played = game.ticks_played,
    paused = not not game.tick_paused,
    speed = game.speed,
    players_online = #game.connected_players,
    mods = script.active_mods,
    difficulty = copy_difficulty(game.difficulty_settings),
    map_settings = copy_map_settings(game.map_settings),
    map_gen_settings = game.default_map_gen_settings,
    mod_settings = redacted_settings,
    surfaces = surfaces,
  }
end)
