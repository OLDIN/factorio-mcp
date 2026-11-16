package.path = "factorio-mcp/?.lua;tests/?.lua;" .. package.path
local env = require("support.env")
local e = env.fresh()
local engine = require("scripts.logic.job_engine")

local function plan(n_chunks, mode)
  local chunks = {}
  for i = 1, n_chunks do chunks[#chunks + 1] = 1; chunks[#chunks + 1] = i; chunks[#chunks + 1] = 0 end
  return { surfaces = { "nauvis" }, chunks = chunks, acc = { seen = 0 }, mode = mode or "ticks" }
end

local stepper = {
  chunk = function(job, si, cx, cy) job.acc.seen = job.acc.seen + 1 end,
  finish = function(job)
    local list = {}
    for i = 1, job.acc.seen do list[i] = { n = i, pad = string.rep("x", 50) } end
    return { fields = { summary = { seen = job.acc.seen } }, list_name = "groups", list = list }
  end,
}

-- start + step to done; cursor moves; progress reported
local state = engine.new()
local id = engine.start(state, "demo", { a = 1 }, 100, plan(10))
local job = engine.find(state, id)
assert(job.state == "running" and job.total == 10 and job.cursor == 0)
assert(engine.step(state, id, 4, stepper) == false and job.cursor == 4)
assert(math.abs(engine.progress(job) - 0.4) < 1e-9)
assert(engine.step(state, id, 100, stepper) == true and job.state == "done" and job.chunks == nil and job.acc == nil)

-- the whole state survives a JSON round trip (no functions, iterators or references)
local id2 = engine.start(state, "demo", {}, 101, plan(5))
engine.step(state, id2, 2, stepper)
local copy = e.json.decode(e.json.encode(state))
local job2 = engine.find(copy, id2)
assert(job2 and job2.cursor == 2 and job2.acc.seen == 2 and job2.total == 5)
assert(engine.step(copy, id2, 100, stepper) == true, "a reloaded job continues to the end")

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

-- a chunk that raises is skipped, the job still finishes
local id4 = engine.start(state, "demo", {}, 103, plan(3))
local flaky = {
  chunk = function(job, si, cx) if cx == 2 then error("surface is gone") end; job.acc.seen = job.acc.seen + 1 end,
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

print("job_engine_test ok")
