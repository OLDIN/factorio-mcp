-- Review Focus 2: on_load must re-register the conditional on_tick from storage, and never write storage.
package.path = "factorio-mcp/?.lua;tests/?.lua;" .. package.path
local env = require("support.env")

local function setup(state)
  local e = env.fresh()
  _G.defines = { events = { on_tick = 0 } }
  e.handlers = {}
  e.registrations = 0
  _G.script.on_event = function(event, handler)
    e.registrations = e.registrations + 1
    e.handlers[event] = handler
  end
  _G.settings = { startup = {}, global = {} }
  _G.storage = { mcp = state }
  -- from now on any write to storage's top level is a bug (this is what on_load must not do)
  setmetatable(_G.storage, { __newindex = function() error("storage written in on_load") end })
  return e, require("scripts.jobs")
end

local function job(state, mode) return { id = 1, kind = "machines_overview", state = state, mode = mode } end

-- a running ticks job: exactly one on_tick handler gets registered
local e, jobs = setup({ next_job_id = 2, jobs = { job("running", "ticks") } })
jobs.sync_handler()
assert(e.handlers[0] ~= nil and e.registrations == 1)
assert(jobs.tick_handler_registered() == true)

-- no active jobs: the handler is removed (registered with nil)
e, jobs = setup({ next_job_id = 2, jobs = { job("done", "ticks"), job("cancelled", "ticks") } })
jobs.sync_handler()
assert(e.handlers[0] == nil and e.registrations == 1 and jobs.tick_handler_registered() == false)

-- an idle job never needs ticks
e, jobs = setup({ next_job_id = 2, jobs = { job("running", "idle") } })
jobs.sync_handler()
assert(e.handlers[0] == nil)

-- no state at all (a save from before the mod had jobs): still fine, still no write
e, jobs = setup(nil)
jobs.sync_handler()
assert(e.handlers[0] == nil)

-- the tick handler does the work and unregisters itself when the job finishes
local done_state = { next_job_id = 2, jobs = {} }
e, jobs = setup(done_state)
local engine = require("scripts.logic.job_engine")
_G.game = { tick = 5, connected_players = { {} }, get_surface = function() return nil end }
_G.storage = { mcp = done_state }  -- plain table again: the job is started like a command would
local kinds = require("scripts.logic.job_kinds")
local real_stepper = kinds.stepper
kinds.stepper = function() return { chunk = function() end, finish = function() return { fields = {} } end } end
engine.start(done_state, "machines_overview", {}, 5, { surfaces = { "nauvis" }, work = { 1, 0, 0, 32, 1, 32, 0, 32 }, acc = {}, mode = "ticks" })
jobs.sync_handler()
assert(e.handlers[0] ~= nil)
jobs.on_tick({ tick = 6 })
-- the default budget covers both areas, so the job finishes on this tick and the handler goes away
assert(done_state.jobs[1].state == "done" and e.handlers[0] == nil)
kinds.stepper = real_stepper

print("jobs_onload_test ok")
