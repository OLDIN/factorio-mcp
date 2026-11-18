-- Scans military and defensive structures around a point:
-- turrets (ammo, electric, fluid, artillery), walls, gates, land-mines, radars.
-- Checks supply state (ammo, energy, fluid) and health/damage.

local M = {}

M.DEFENSE_TYPES = {
  "ammo-turret",
  "electric-turret",
  "fluid-turret",
  "turret",
  "artillery-turret",
  "wall",
  "gate",
  "land-mine",
  "radar",
}

local function read(obj, field)
  local ok, val = pcall(function() return obj[field] end)
  if ok then return val end
  return nil
end

local function is_turret_type(etype)
  return etype == "ammo-turret"
    or etype == "electric-turret"
    or etype == "fluid-turret"
    or etype == "turret"
    or etype == "artillery-turret"
end

local function is_wall_type(etype)
  return etype == "wall" or etype == "gate"
end

-- Worms are type "turret" on the enemy force; neutral entities are map decoration.
-- Neither is part of anyone's defense, so the scan skips them.
local function is_hostile_or_neutral(entity)
  local force = read(entity, "force")
  if not force then return false end
  local fname = read(force, "name")
  return fname == "enemy" or fname == "neutral"
end

function M.scan(surface, center, radius, max_listed)
  local entities = surface.find_entities_filtered({
    position = { x = center.x, y = center.y },
    radius = radius,
    type = M.DEFENSE_TYPES,
  })

  local total = 0
  local turrets_count = 0
  local walls_count = 0
  local other_count = 0

  local issue_no_ammo = 0
  local issue_no_power = 0
  local issue_no_fluid = 0
  local issue_damaged = 0

  local groups_map = {}
  local problem_candidates = {}

  for _, entity in ipairs(entities) do
    if entity.valid and not is_hostile_or_neutral(entity) then
      total = total + 1
      local name = entity.name
      local etype = entity.type
      local pos = entity.position

      local health = read(entity, "health") or 0
      local max_health = read(entity, "max_health") or 0
      local is_damaged = (max_health > 0) and (health < max_health)

      if is_damaged then
        issue_damaged = issue_damaged + 1
      end

      local is_turret = is_turret_type(etype)
      local is_wall = is_wall_type(etype)
      if is_turret then
        turrets_count = turrets_count + 1
      elseif is_wall then
        walls_count = walls_count + 1
      else
        other_count = other_count + 1
      end

      local unsupplied_issue = nil
      local ammo_count = nil
      local ammo_dict = nil
      local fluid_amount = nil
      local fluid_dict = nil

      if etype == "ammo-turret" or etype == "artillery-turret" or etype == "turret" then
        local inv_id = defines.inventory.turret_ammo
        if etype == "artillery-turret" and defines.inventory.artillery_turret_ammo then
          inv_id = defines.inventory.artillery_turret_ammo
        end
        local ok, inv = pcall(function() return entity.get_inventory(inv_id) end)
        ammo_count = 0
        if ok and inv and inv.valid then
          local ok_c, cont = pcall(function() return inv.get_contents() end)
          if ok_c and type(cont) == "table" then
            ammo_dict = {}
            for _, item in ipairs(cont) do
              ammo_count = ammo_count + item.count
              ammo_dict[item.name] = (ammo_dict[item.name] or 0) + item.count
            end
          end
        end
        if ammo_count == 0 then
          unsupplied_issue = "no_ammo"
          issue_no_ammo = issue_no_ammo + 1
        end

      elseif etype == "electric-turret" or etype == "radar" then
        local energy = read(entity, "energy") or 0
        if energy <= 0 then
          unsupplied_issue = "no_power"
          issue_no_power = issue_no_power + 1
        end

      elseif etype == "fluid-turret" then
        local ok, cont = pcall(function() return entity.get_fluid_contents() end)
        fluid_amount = 0
        if ok and type(cont) == "table" then
          fluid_dict = {}
          for fname, amt in pairs(cont) do
            fluid_amount = fluid_amount + amt
            fluid_dict[fname] = (fluid_dict[fname] or 0) + amt
          end
        end
        if fluid_amount <= 0 then
          unsupplied_issue = "no_fluid"
          issue_no_fluid = issue_no_fluid + 1
        end
      end

      -- Group aggregation
      local grp = groups_map[name]
      if not grp then
        grp = {
          name = name,
          type = etype,
          count = 0,
          ready = 0,
          damaged = 0,
          ammo = nil,
          fluids = nil,
        }
        groups_map[name] = grp
      end

      grp.count = grp.count + 1
      if is_damaged then
        grp.damaged = grp.damaged + 1
      end
      if not unsupplied_issue then
        grp.ready = grp.ready + 1
      end

      if ammo_dict then
        grp.ammo = grp.ammo or {}
        for aname, acnt in pairs(ammo_dict) do
          grp.ammo[aname] = (grp.ammo[aname] or 0) + acnt
        end
      end

      if fluid_dict then
        grp.fluids = grp.fluids or {}
        for fname, famt in pairs(fluid_dict) do
          grp.fluids[fname] = (grp.fluids[fname] or 0) + famt
        end
      end

      -- Check if problematic
      if unsupplied_issue or is_damaged then
        local priority
        local main_issue = unsupplied_issue or "damaged"
        if is_turret and unsupplied_issue then
          priority = 1
        elseif is_turret and is_damaged then
          priority = 2
        elseif is_wall and is_damaged then
          priority = 3
        else
          priority = 4
        end

        table.insert(problem_candidates, {
          priority = priority,
          name = name,
          type = etype,
          x = pos.x,
          y = pos.y,
          issue = main_issue,
          health = math.floor(health),
          max_health = math.floor(max_health),
          ammo = ammo_count,
          fluid = fluid_amount and math.floor(fluid_amount) or nil,
        })
      end
    end
  end

  -- Sort groups by count descending
  local groups = {}
  for _, grp in pairs(groups_map) do
    table.insert(groups, grp)
  end
  table.sort(groups, function(a, b)
    if a.count ~= b.count then return a.count > b.count end
    return a.name < b.name
  end)

  -- Sort problems by priority ascending (1 is worst)
  table.sort(problem_candidates, function(a, b)
    if a.priority ~= b.priority then return a.priority < b.priority end
    return a.health < b.health
  end)

  local problems = {}
  local limit = math.min(#problem_candidates, max_listed)
  for i = 1, limit do
    local item = problem_candidates[i]
    item.priority = nil  -- strip internal priority
    table.insert(problems, item)
  end

  return {
    summary = {
      total = total,
      turrets = turrets_count,
      walls = walls_count,
      other = other_count,
      issues = {
        no_ammo = issue_no_ammo,
        no_power = issue_no_power,
        no_fluid = issue_no_fluid,
        damaged = issue_damaged,
      },
    },
    groups = groups,
    problems = problems,
    problems_total = #problem_candidates,
  }
end

return M
