-- Trains: one train as a record (state, where, cargo, problem), problem trains first, paging.
-- Only schedule getters are used; passengers are never read.
local geo = require("scripts.logic.geo")

local M = {}

local LONG_WAIT_TICKS = 5 * 60 * 60 -- 5 minutes at a station
local PROBLEM_STATES = { no_path = true, no_schedule = true, destination_full = true }
local PROBLEM_RANK = { no_path = 1, destination_full = 2, no_schedule = 3, manual_with_cargo = 4, long_wait = 5 }
local CARGO_LIMIT = 5

-- reverse table of defines.train_state (number -> name)
function M.state_names()
  local out = {}
  for name, v in pairs(defines.train_state) do out[v] = name end
  return out
end

local function summed(items)
  local by_name, list = {}, {}
  for _, it in ipairs(items or {}) do
    if not by_name[it.name] then
      by_name[it.name] = { name = it.name, count = 0 }
      list[#list + 1] = by_name[it.name]
    end
    by_name[it.name].count = by_name[it.name].count + it.count
  end
  table.sort(list, function(a, b) return a.count > b.count end)
  for i = #list, CARGO_LIMIT + 1, -1 do list[i] = nil end
  return list
end

local function fluids_of(dict)
  local list = {}
  for name, amount in pairs(dict or {}) do list[#list + 1] = { name = name, amount = math.floor(amount) } end
  table.sort(list, function(a, b) return a.amount > b.amount end)
  return list
end

function M.record(train, names)
  local state = names[train.state] or tostring(train.state)
  local front = train.front_stock
  local surface_name = front and front.surface.name or nil
  local ok, schedule = pcall(train.get_schedule)
  local waiting = (ok and schedule and schedule.ticks_in_station) or 0
  local cargo = summed(train.get_contents())
  local r = {
    id = train.id, group = train.group, state = state, surface = surface_name,
    gps = front and geo.gps(surface_name, front.position.x, front.position.y) or nil,
    station = train.station and train.station.backer_name or nil,
    target = train.path_end_stop and train.path_end_stop.backer_name or nil,
    waiting_ticks = waiting, cargo = cargo, fluids = fluids_of(train.get_fluid_contents()),
  }
  if PROBLEM_STATES[state] then
    r.problem = state
  elseif (state == "manual_control" or state == "manual_control_stop") and #cargo > 0 then
    r.problem = "manual_with_cargo"
  elseif state == "wait_station" and waiting > LONG_WAIT_TICKS then
    r.problem = "long_wait"
  end
  return r
end

function M.page(records, problems_only, offset, limit)
  local by_state, problems_total, list = {}, 0, {}
  for _, r in ipairs(records) do
    by_state[r.state] = (by_state[r.state] or 0) + 1
    if r.problem then problems_total = problems_total + 1 end
    if r.problem or not problems_only then list[#list + 1] = r end
  end
  table.sort(list, function(a, b)
    local ra, rb = PROBLEM_RANK[a.problem] or 99, PROBLEM_RANK[b.problem] or 99
    if ra ~= rb then return ra < rb end
    return a.id < b.id
  end)
  local trains = {}
  for i = offset + 1, math.min(offset + limit, #list) do trains[#trains + 1] = list[i] end
  local nxt = nil
  if offset + limit < #list then nxt = offset + limit end
  return { by_state = by_state, total = #records, problems_total = problems_total, trains = trains, next = nxt }
end

return M
