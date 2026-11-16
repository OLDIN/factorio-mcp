-- Glue between the pure job engine and the game: storage, settings, and the conditional on_tick.
-- Nothing runs in the background unless a job in "ticks" mode is running.
local engine = require("scripts.logic.job_engine")
local kinds = require("scripts.logic.job_kinds")

local M = {}

local tick_handler_registered = false

local function setting(name, default)
  local s = settings.global[name]
  if s and s.value then return s.value end
  return default
end

function M.tick_handler_registered()
  return tick_handler_registered
end

-- Creates the state on first use. Never call from on_load (storage must not be written there).
function M.state()
  if not storage.mcp then storage.mcp = engine.new() end
  engine.migrate(storage.mcp)
  return storage.mcp
end

-- Registers on_tick only while a "ticks" job is running; otherwise removes it.
-- Reads storage only, so it is safe in on_load.
function M.sync_handler()
  local state = storage.mcp
  local needed = false
  if state then
    for _, job in ipairs(state.jobs) do
      if job.state == "running" and job.mode == "ticks" then needed = true; break end
    end
  end
  if needed then
    script.on_event(defines.events.on_tick, M.on_tick)
  else
    script.on_event(defines.events.on_tick, nil)
  end
  tick_handler_registered = needed
end

function M.on_tick(event)
  local state = storage.mcp
  if not state then return M.sync_handler() end
  for _, job in ipairs(state.jobs) do
    if job.state == "running" and job.mode == "ticks" then
      local done = engine.step(state, job.id, setting("factorio-mcp-work-per-tick", 50), kinds.stepper(job.kind), event.tick)
      if done then M.sync_handler() end
      return
    end
  end
  M.sync_handler()
end

-- Idle mode: nobody is online (the game may be paused), so each poll does a bigger batch.
function M.step_idle(job)
  local state = M.state()
  local done = engine.step(state, job.id, setting("factorio-mcp-idle-work-per-poll", 20000), kinds.stepper(job.kind), game.tick)
  if done then M.sync_handler() end
  return done
end

function M.collect_garbage()
  engine.collect_garbage(M.state(), game.tick, engine.TTL_TICKS, engine.MAX_RESULTS)
end

return M
