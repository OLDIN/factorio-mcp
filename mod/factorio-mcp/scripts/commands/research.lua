-- `research` subcommand: what the caller's force researches now, its queue, and what is available.
-- Params: {caller, name?, offset? (default 0), limit? (1..50, default 20)}.
local dispatcher = require("scripts.dispatcher")
local caller = require("scripts.logic.caller")
local params_lib = require("scripts.logic.params")
local research_logic = require("scripts.logic.research_logic")

local function tech_name(t)
  if type(t) == "string" then return t end
  return t.name
end

dispatcher.register("research", function(p)
  local force = caller.force(p)
  local name = params_lib.string(p, "name")
  if name then
    local t = force.technologies[name]
    if not t then error({ code = "not_found", message = "no such technology" }) end
    return research_logic.state(t)
  end
  local offset = params_lib.int(p, "offset", 0, 0, 100000)
  local limit = params_lib.int(p, "limit", 20, 1, 50)
  local current = nil
  local cur = force.current_research
  if cur then
    current = { name = cur.name, level = cur.level, progress = math.floor(force.research_progress * 1000 + 0.5) / 1000 }
  end
  local queue = {}
  for i, t in ipairs(force.research_queue or {}) do queue[i] = tech_name(t) end
  local researched, total = 0, 0
  for _, t in pairs(force.technologies) do
    total = total + 1
    if t.researched then researched = researched + 1 end
  end
  return {
    current = current, queue = queue, researched = researched, total = total,
    available = research_logic.page(research_logic.available(force.technologies), offset, limit),
  }
end)
