package.path = "factorio-mcp/?.lua;tests/?.lua;" .. package.path
local env = require("support.env")
local e = env.fresh()
local engine = require("scripts.logic.job_engine")

-- n areas of one chunk each
local function plan(n, mode)
  local work = {}
  for i = 1, n do
    work[#work + 1] = 1; work[#work + 1] = i * 32; work[#work + 1] = 0; work[#work + 1] = 32
  end
  return { surfaces = { "nauvis" }, work = work, acc = { seen = 0 }, mode = mode or "ticks" }
end

local stepper = {
  work = function(job) job.acc.seen = job.acc.seen + 1; return 1, false end,
  finish = function(job)
    local list = {}
    for i = 1, job.acc.seen do list[i] = { n = i, pad = string.rep("x", 50) } end
    return { fields = { summary = { seen = job.acc.seen } }, list_name = "groups", list = list }
  end,
}

-- start + step to done; the budget is in work units; progress reported
local state = engine.new()
local id = engine.start(state, "demo", { a = 1 }, 100, plan(10))
local job = engine.find(state, id)
assert(job.state == "running" and job.total_weight == 10 and engine.pending(job) == 10)
assert(engine.step(state, id, 4, stepper) == false and engine.pending(job) == 6)
assert(math.abs(engine.progress(job) - 0.4) < 1e-9)
assert(engine.step(state, id, 100, stepper) == true and job.state == "done" and job.work == nil and job.acc == nil)

-- the whole state survives a JSON round trip (no functions, iterators or references)
local id2 = engine.start(state, "demo", {}, 101, plan(5))
engine.step(state, id2, 2, stepper)
local copy = e.json.decode(e.json.encode(state))
local job2 = engine.find(copy, id2)
assert(job2 and engine.pending(job2) == 3 and job2.acc.seen == 2)
assert(engine.step(copy, id2, 100, stepper) == true, "a reloaded job continues to the end")

-- an area can be split into four: the work stays the same and progress counts it once
local split_state = engine.new()
local split_plan = { surfaces = { "nauvis" }, work = { 1, 0, 0, 128 }, acc = { seen = 0 }, mode = "idle" }
local sid = engine.start(split_state, "demo", {}, 1, split_plan)
local sjob = engine.find(split_state, sid)
assert(sjob.total_weight == 16)
local splitter = {
  work = function(j, si, x0, y0, size)
    if size > 32 then engine.split(j, si, x0, y0, size); return 2, true end
    j.acc.seen = j.acc.seen + 1
    return 1, false
  end,
  finish = stepper.finish,
}
assert(engine.step(split_state, sid, 1, splitter) == false, "the first step only splits")
assert(engine.pending(sjob) == 4 and sjob.done_weight == 0)
assert(engine.step(split_state, sid, 1000, splitter) == true)
assert(engine.find(split_state, sid).result.fields.summary.seen == 16, "128x128 is sixteen chunks")

-- take_page: pages, then the job disappears with the last page
local reply, nxt = engine.take_page(state, id, 0, 4, 100000)
assert(#reply.groups == 4 and nxt == 4 and reply.summary.seen == 10 and reply.total == 10)
reply, nxt = engine.take_page(state, id, 4, 100, 100000)
assert(#reply.groups == 6 and nxt == nil)
assert(engine.find(state, id) == nil, "result is removed after the last page")

-- cancel
local id3 = engine.start(state, "demo", {}, 102, plan(5))
assert(engine.cancel(state, id3) == true and engine.find(state, id3).state == "cancelled")
assert(engine.cancel(state, id3) == false)

-- an area that raises is skipped, the job still finishes
local id4 = engine.start(state, "demo", {}, 103, plan(3))
local flaky = {
  work = function(job, si, x0) if x0 == 64 then error("surface is gone") end; job.acc.seen = job.acc.seen + 1; return 1, false end,
  finish = stepper.finish,
}
assert(engine.step(state, id4, 100, flaky) == true)
assert(engine.find(state, id4).result.fields.summary.seen == 2)

-- an empty plan finishes on the first step
local id5 = engine.start(state, "demo", {}, 104, plan(0))
assert(engine.step(state, id5, 1, stepper) == true)

-- garbage collection: expired results go, at most max_results remain, running jobs are kept
local gc = engine.new()
for i = 1, 12 do
  local gid = engine.start(gc, "demo", {}, i, plan(1))
  engine.step(gc, gid, 10, stepper, i)
end
local running = engine.start(gc, "demo", {}, 0, plan(5))
engine.collect_garbage(gc, 20, 1000, 8)
local done = 0
for _, j in ipairs(gc.jobs) do if j.state == "done" then done = done + 1 end end
assert(done == 8 and engine.find(gc, running), "keeps 8 finished results and the running job")
assert(engine.find(gc, 1) == nil and engine.find(gc, 12) ~= nil, "oldest are dropped first")
engine.collect_garbage(gc, 100000, 36000, 8)
assert(#gc.jobs == 1 and gc.jobs[1].id == running, "expired results are dropped")

-- a save from version 0.1.0: jobs in the old layout must not crash anything
local old = {
  next_job_id = 4,
  jobs = {
    { id = 1, kind = "machines_overview", state = "running", mode = "ticks", created_tick = 1, touched_tick = 1,
      params = {}, surfaces = { "nauvis" }, chunks = { 1, 0, 0 }, total = 1, cursor = 0, acc = { machines = 0 } },
    { id = 2, kind = "machines_overview", state = "done", mode = "idle", created_tick = 1, touched_tick = 1,
      params = {}, surfaces = { "nauvis" }, total = 1, cursor = 1,
      result = { fields = { summary = { machines = 5 } }, list_name = "groups", list = {} } },
    { id = 3, kind = "area", state = "cancelled", mode = "ticks", created_tick = 1, touched_tick = 1, params = {} },
  },
}
engine.migrate(old)
assert(old.jobs[1].state == "cancelled" and old.jobs[1].work == nil and engine.progress(old.jobs[1]) == 0)
assert(old.jobs[2].state == "done" and engine.progress(old.jobs[2]) == 1, "a finished result is kept")
assert(engine.progress(old.jobs[3]) == 0 and engine.pending(old.jobs[3]) == 0)
local page = engine.take_page(old, 2, 0, 10, 100000)
assert(page and page.summary.machines == 5, "an old finished result can still be fetched")

print("job_engine_test ok")
