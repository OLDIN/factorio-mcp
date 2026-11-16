-- Tick-split job bookkeeping. Everything lives in one plain-data table (storage.mcp), so it survives
-- save/load: no functions, no iterators, no entity references.
--   state = {next_job_id, jobs = array of job}
--   job   = {id, kind, state = running|done|cancelled, mode = ticks|idle, created_tick, touched_tick,
--            params, surfaces (names), chunks (flat: surface_index, cx, cy, ...), total, cursor,
--            acc, result = {fields, list_name, list}}
local paging = require("scripts.logic.paging")

local M = {}

M.TTL_TICKS = 36000
M.MAX_RESULTS = 8

function M.new()
  return { next_job_id = 1, jobs = {} }
end

function M.find(state, id)
  for i, job in ipairs(state.jobs) do
    if job.id == id then return job, i end
  end
  return nil
end

-- plan = {surfaces = {names}, chunks = flat array, acc = plain data, mode = "ticks"|"idle"}
function M.start(state, kind, params, tick, plan)
  local id = state.next_job_id
  state.next_job_id = id + 1
  state.jobs[#state.jobs + 1] = {
    id = id, kind = kind, state = "running", mode = plan.mode, created_tick = tick, touched_tick = tick,
    params = params, surfaces = plan.surfaces, chunks = plan.chunks, total = math.floor(#plan.chunks / 3),
    cursor = 0, acc = plan.acc,
  }
  return id
end

function M.progress(job)
  if job.state == "done" then return 1 end
  if job.total == 0 then return 0 end
  return math.floor(job.cursor / job.total * 1000) / 1000
end

local function finish(job, stepper)
  local ok, result = pcall(stepper.finish, job)
  if not ok then
    log("factorio-mcp: job " .. job.id .. " could not finish: " .. tostring(result))
    result = { fields = { error = "job failed" } }
  end
  job.result = result
  job.state = "done"
  job.acc, job.chunks = nil, nil
end

-- Process up to `budget` chunks. stepper = {chunk = function(job, surface_index, cx, cy), finish = function(job) -> result}.
-- A chunk that raises (e.g. its surface vanished) is skipped. Returns true when the job is done.
function M.step(state, id, budget, stepper, tick)
  local job = M.find(state, id)
  if not job or job.state ~= "running" then return job ~= nil and job.state == "done" end
  if tick then job.touched_tick = tick end
  local last = math.min(job.total, job.cursor + budget)
  while job.cursor < last do
    local base = job.cursor * 3
    local ok, err = pcall(stepper.chunk, job, job.chunks[base + 1], job.chunks[base + 2], job.chunks[base + 3])
    if not ok then log("factorio-mcp: job " .. job.id .. " skipped a chunk: " .. tostring(err)) end
    job.cursor = job.cursor + 1
  end
  if job.cursor >= job.total then
    finish(job, stepper)
    return true
  end
  return false
end

function M.cancel(state, id)
  local job = M.find(state, id)
  if not job or job.state ~= "running" then return false end
  job.state = "cancelled"
  job.acc, job.chunks = nil, nil
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
