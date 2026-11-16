-- Tick-split job bookkeeping. Everything lives in one plain-data table (storage.mcp), so it survives
-- save/load: no functions, no iterators, no entity references.
--   state = {next_job_id, jobs = array of job}
--   job   = {id, kind, state = running|done|cancelled, mode = ticks|idle, created_tick, touched_tick,
--            params, surfaces (names), work (a stack: flat 4-tuples surface_index, x0, y0, size, in tiles),
--            total_weight, done_weight, acc, result = {fields, list_name, list}}
-- Work items are square map areas. A stepper either handles an area (returning its cost in work
-- units) or splits it into four smaller ones, so empty parts of the map cost almost nothing and
-- dense parts are cut into small pieces.
local paging = require("scripts.logic.paging")

local M = {}

M.TTL_TICKS = 36000
M.MAX_RESULTS = 8
M.TILE = 32 -- smallest area: one chunk

function M.new()
  return { next_job_id = 1, jobs = {} }
end

-- Jobs saved by an older version of the mod have another layout (a chunk list and a cursor, no
-- work stack). They are transient, so: a running one is cancelled, a finished one keeps its result.
-- Safe to call any time outside on_load (it writes to the state).
function M.migrate(state)
  for _, job in ipairs(state.jobs) do
    if job.total_weight == nil then
      job.total_weight, job.done_weight = 0, 0
      if job.state == "running" then
        job.state = "cancelled"
        job.acc, job.work, job.chunks, job.cursor = nil, nil, nil, nil
      end
    end
  end
end

function M.find(state, id)
  for i, job in ipairs(state.jobs) do
    if job.id == id then return job, i end
  end
  return nil
end

-- progress weight of an area: its size in chunks
function M.weight(size)
  return (size / M.TILE) ^ 2
end

function M.push(job, si, x0, y0, size)
  local work = job.work
  local n = #work
  work[n + 1], work[n + 2], work[n + 3], work[n + 4] = si, x0, y0, size
end

-- Replace an area by its four quadrants (its weight is carried by them).
function M.split(job, si, x0, y0, size)
  local half = size / 2
  M.push(job, si, x0, y0, half)
  M.push(job, si, x0 + half, y0, half)
  M.push(job, si, x0, y0 + half, half)
  M.push(job, si, x0 + half, y0 + half, half)
end

-- plan = {surfaces = {names}, work = flat array of 4-tuples, acc = plain data, mode = "ticks"|"idle"}
function M.start(state, kind, params, tick, plan)
  local id = state.next_job_id
  state.next_job_id = id + 1
  local total = 0
  for i = 4, #plan.work, 4 do total = total + M.weight(plan.work[i]) end
  state.jobs[#state.jobs + 1] = {
    id = id, kind = kind, state = "running", mode = plan.mode, created_tick = tick, touched_tick = tick,
    params = params, surfaces = plan.surfaces, work = plan.work, total_weight = total, done_weight = 0,
    acc = plan.acc,
  }
  return id
end

function M.progress(job)
  if job.state == "done" then return 1 end
  if not job.total_weight or job.total_weight == 0 then return 0 end
  return math.floor(job.done_weight / job.total_weight * 1000) / 1000
end

function M.pending(job)
  return job.work and math.floor(#job.work / 4) or 0
end

local function finish(job, stepper)
  local ok, result = pcall(stepper.finish, job)
  if not ok then
    log("factorio-mcp: job " .. job.id .. " could not finish: " .. tostring(result))
    result = { fields = { error = "job failed" } }
  end
  job.result = result
  job.state = "done"
  job.acc, job.work = nil, nil
end

-- Work through areas until `budget` work units are spent. stepper =
--   {work = function(job, si, x0, y0, size) -> cost, split, finish = function(job) -> result}.
-- An area that raises (e.g. its surface vanished) is skipped. Returns true when the job is done.
function M.step(state, id, budget, stepper, tick)
  local job = M.find(state, id)
  if not job or job.state ~= "running" then return job ~= nil and job.state == "done" end
  if tick then job.touched_tick = tick end
  local work = job.work
  local spent = 0
  while spent < budget and #work > 0 do
    local n = #work
    local si, x0, y0, size = work[n - 3], work[n - 2], work[n - 1], work[n]
    work[n], work[n - 1], work[n - 2], work[n - 3] = nil, nil, nil, nil
    local ok, cost, split = pcall(stepper.work, job, si, x0, y0, size)
    if not ok then
      log("factorio-mcp: job " .. job.id .. " skipped an area: " .. tostring(cost))
      cost, split = 1, false
    end
    if not split then job.done_weight = job.done_weight + M.weight(size) end
    spent = spent + (cost or 1)
  end
  if #work == 0 then
    finish(job, stepper)
    return true
  end
  return false
end

function M.cancel(state, id)
  local job = M.find(state, id)
  if not job or job.state ~= "running" then return false end
  job.state = "cancelled"
  job.acc, job.work = nil, nil
  return true
end

-- Remove a finished job.
function M.remove(state, id)
  local _, index = M.find(state, id)
  if index then table.remove(state.jobs, index) end
end

-- One page of a finished job's result. The job is removed after its last page.
-- Returns the reply fields (a fresh table) and the next offset (nil at the end).
function M.take_page(state, id, offset, limit, budget_bytes)
  local job = M.find(state, id)
  if not job or job.state ~= "done" then return nil end
  local result = job.result
  local reply = {}
  for k, v in pairs(result.fields) do reply[k] = v end
  local nxt = nil
  if result.list_name then
    local fixed = #helpers.table_to_json(reply)
    local items
    items, nxt = paging.page(result.list, offset, limit, function(item) return item end,
      math.max(1000, budget_bytes - fixed))
    reply[result.list_name] = items
    reply.total = #result.list
  end
  if nxt == nil then M.remove(state, id) end
  return reply, nxt
end

-- Drop results older than ttl_ticks and keep at most max_results finished jobs (oldest go first).
function M.collect_garbage(state, tick, ttl_ticks, max_results)
  local kept, finished = {}, {}
  for _, job in ipairs(state.jobs) do
    if job.state == "running" then
      kept[#kept + 1] = job
    elseif tick - job.touched_tick <= ttl_ticks then
      kept[#kept + 1] = job
      finished[#finished + 1] = job
    end
  end
  table.sort(finished, function(a, b) return a.touched_tick < b.touched_tick end)
  local drop = {}
  for i = 1, #finished - max_results do drop[finished[i]] = true end
  state.jobs = {}
  for _, job in ipairs(kept) do
    if not drop[job] then state.jobs[#state.jobs + 1] = job end
  end
end

return M
