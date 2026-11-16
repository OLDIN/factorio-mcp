-- Tick-split jobs: job_start, job_result, job_cancel, job_status.
local dispatcher = require("scripts.dispatcher")
local engine = require("scripts.logic.job_engine")
local jobs = require("scripts.jobs")
local kinds = require("scripts.logic.job_kinds")
local limits = require("scripts.limits")

local function id_param(params)
  local id = params.job_id
  if type(id) ~= "number" or id ~= math.floor(id) then
    error({ code = "bad_params", message = "job_id must be an integer" })
  end
  return id
end

local function int_param(params, key, default, min, max)
  local v = params[key]
  if v == nil then return default end
  if type(v) ~= "number" or v ~= math.floor(v) or v < min or v > max then
    error({ code = "bad_params", message = key .. " must be an integer between " .. min .. " and " .. max })
  end
  return v
end

dispatcher.register("job_start", function(params)
  local kind = params.kind
  if type(kind) ~= "string" or not kinds.known(kind) then
    error({ code = "bad_params", message = "unknown job kind" })
  end
  if params.params ~= nil and type(params.params) ~= "table" then
    error({ code = "bad_params", message = "params must be an object" })
  end
  local mode = params.mode
  if mode ~= nil and mode ~= "ticks" and mode ~= "idle" then
    error({ code = "bad_params", message = "mode must be ticks or idle" })
  end
  local state = jobs.state()
  jobs.collect_garbage()
  local running = 0
  for _, job in ipairs(state.jobs) do
    if job.state == "running" then running = running + 1 end
  end
  if running >= limits.MAX_RUNNING_JOBS then
    error({ code = "too_many_jobs", message = "too many jobs are running; wait for one to finish" })
  end
  local plan = kinds.plan(kind, params.params)
  -- nobody online: the game may be paused, so advance by polling instead of by ticks
  plan.mode = mode or (#game.connected_players == 0 and "idle" or "ticks")
  local id = engine.start(state, kind, plan.params or params.params or {}, game.tick, plan)
  jobs.sync_handler()
  return { job_id = id, mode = plan.mode, total_chunks = math.floor(#plan.chunks / 3) }
end)

dispatcher.register("job_result", function(params)
  local id = id_param(params)
  local offset = int_param(params, "offset", 0, 0, 100000000)
  local limit = int_param(params, "limit", 200, 1, 1000)
  jobs.collect_garbage()
  local state = jobs.state()
  local job = engine.find(state, id)
  if not job then error({ code = "job_not_found", message = "no such job" }) end
  if job.state == "running" and job.mode == "idle" then jobs.step_idle(job) end
  if job.state == "running" then
    return { state = "running", mode = job.mode, progress = engine.progress(job) }
  end
  if job.state == "cancelled" then
    engine.remove(state, id)
    return { state = "cancelled" }
  end
  local reply, nxt = engine.take_page(state, id, offset, limit, limits.RESPONSE_BUDGET_BYTES - 200)
  reply.state = "done"
  reply.next = nxt
  return reply
end)

dispatcher.register("job_cancel", function(params)
  local cancelled = engine.cancel(jobs.state(), id_param(params))
  jobs.sync_handler()
  return { cancelled = cancelled }
end)

dispatcher.register("job_status", function()
  local list = {}
  for _, job in ipairs(jobs.state().jobs) do
    list[#list + 1] = { id = job.id, kind = job.kind, state = job.state, mode = job.mode, progress = engine.progress(job) }
  end
  return { jobs = list, tick_handler_registered = jobs.tick_handler_registered() }
end)
