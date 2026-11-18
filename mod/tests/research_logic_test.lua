-- Tests for research_logic: what can be researched now, one technology's state, paging.
package.path = "factorio-mcp/?.lua;tests/?.lua;" .. package.path
local env = require("support.env")
env.fresh()
local research_logic = require("scripts.logic.research_logic")

local function tech(name, researched, prereqs, enabled)
  return {
    name = name, researched = researched, enabled = enabled ~= false, level = 1,
    prerequisites = prereqs or {}, research_unit_count = 10, saved_progress = 0,
    research_unit_ingredients = { { type = "item", name = "automation-science-pack", amount = 1 } },
  }
end

local automation = tech("automation", true)
local logistics = tech("logistics", false, { automation = automation })
local electronics = tech("electronics", false, { automation = automation, logistics = logistics })
local hidden = tech("secret", false, {}, false)
local techs = { automation = automation, logistics = logistics, electronics = electronics, secret = hidden }

local avail = research_logic.available(techs)
assert(#avail == 1 and avail[1] == "logistics", "only logistics: enabled, not done, prerequisites done")

local st = research_logic.state(electronics)
assert(st.name == "electronics" and st.researched == false)
assert(#st.missing_prerequisites == 1 and st.missing_prerequisites[1] == "logistics")
assert(st.ingredients[1].name == "automation-science-pack" and st.ingredients[1].amount == 1)
assert(st.unit_count == 10)

-- a modpack with 2,000 available technologies: one page, the rest by offset
local many = {}
for i = 1, 2000 do many["t" .. string.format("%04d", i)] = tech("t" .. string.format("%04d", i), false) end
local list = research_logic.available(many)
assert(#list == 2000)
local page = research_logic.page(list, 0, 20)
assert(page.total == 2000 and #page.items == 20 and page.next == 20 and page.items[1] == "t0001")
local last = research_logic.page(list, 1990, 20)
assert(#last.items == 10 and last.next == nil)
assert(#research_logic.page({}, 0, 20).items == 0)

print("research_logic_test ok")
