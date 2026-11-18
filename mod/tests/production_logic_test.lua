-- Tests for production_logic: per-minute rates per surface, summed over qualities, and the summary.
package.path = "factorio-mcp/?.lua;tests/?.lua;" .. package.path
local env = require("support.env")
env.fresh()
local production_logic = require("scripts.logic.production_logic")

-- A fake LuaFlowStatistics: rates[category][name][quality or "-"] = per-minute value.
local function fake_stats(rates)
  local inputs, outputs = {}, {}
  for name in pairs(rates.input or {}) do inputs[name] = 1 end
  for name in pairs(rates.output or {}) do outputs[name] = 1 end
  return {
    input_counts = inputs,
    output_counts = outputs,
    get_flow_count = function(t)
      assert(t.count == false, "per-minute values need count = false")
      assert(t.precision_index == 7, "window index passed through")
      local name, quality = t.name, "-"
      if type(name) == "table" then name, quality = name.name, name.quality end
      local by_name = (rates[t.category] or {})[name] or {}
      return by_name[quality] or 0
    end,
  }
end

local QUALITIES = { "normal", "rare" }

local nauvis = fake_stats({
  input = { ["iron-plate"] = { normal = 100, rare = 20 }, ["iron-gear-wheel"] = { normal = 10 } },
  output = { ["iron-plate"] = { normal = 200 }, ["iron-gear-wheel"] = { normal = 0 } },
})
local vulcanus = fake_stats({ input = { ["iron-plate"] = { normal = 60 } } })

local per_surface = production_logic.rates({
  { surface = "nauvis", stats = nauvis },
  { surface = "vulcanus", stats = vulcanus },
}, 7, QUALITIES)

-- qualities are summed: 100 normal + 20 rare
assert(per_surface.nauvis["iron-plate"].produced == 120, "qualities summed")
assert(per_surface.nauvis["iron-plate"].consumed == 200)
assert(per_surface.nauvis["iron-plate"].by_quality.rare == 20, "by_quality kept for items")
assert(per_surface.vulcanus["iron-plate"].produced == 60)

local merged = production_logic.merge(per_surface)
assert(merged["iron-plate"].produced == 180 and merged["iron-plate"].consumed == 200)

local summary = production_logic.summarize(merged, 15)
assert(summary.deficits[1].name == "iron-plate", "largest deficit first")
assert(summary.deficits[1].net == -20, "net = produced - consumed")
assert(summary.top_produced[1].name == "iron-plate")
assert(summary.top_consumed[1].name == "iron-plate")
for _, e in ipairs(summary.top_produced) do assert(e.by_quality == nil, "no by_quality in the summary") end

-- limit keeps one entry per list
local one = production_logic.summarize(merged, 1)
assert(#one.top_produced == 1 and #one.top_consumed == 1 and #one.deficits == 1)

-- fluids have no quality: plain names
local fluid_stats = fake_stats({ input = { water = { ["-"] = 1200.123 } }, output = { water = { ["-"] = 600 } } })
local fluids = production_logic.rates({ { surface = "nauvis", stats = fluid_stats } }, 7, nil)
assert(fluids.nauvis.water.produced == 1200.12, "rounded to 2 decimals")
assert(fluids.nauvis.water.by_quality == nil)

-- nothing flowed in the window: the entry is dropped; empty statistics give empty lists
local idle = fake_stats({ input = { coal = { normal = 0 } } })
local empty = production_logic.summarize(production_logic.merge(production_logic.rates({ { surface = "nauvis", stats = idle } }, 7, QUALITIES)), 15)
assert(#empty.top_produced == 0 and #empty.top_consumed == 0 and #empty.deficits == 0, "idle entries dropped")

print("production_logic_test ok")
