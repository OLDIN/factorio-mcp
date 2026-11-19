-- Tests for personal_logic: the caller's own inventory and alerts.
package.path = "factorio-mcp/?.lua;tests/?.lua;" .. package.path
local env = require("support.env")
env.fresh()
_G.defines = {
  inventory = { character_main = 1, character_armor = 2, character_guns = 3, character_ammo = 4 },
  alert_type = { entity_destroyed = 0, turret_out_of_ammo = 1 },
}
local personal_logic = require("scripts.logic.personal_logic")

local function inv(items, grid)
  return { valid = true,
    get_contents = function() return items end,
    [1] = grid and { valid_for_read = true, name = items[1] and items[1].name, grid = grid } or nil }
end

local grid = { get_contents = function() return { { name = "solar-panel-equipment", quality = "normal", count = 3 } } end }
local player = {
  connected = true, crafting_queue_size = 2,
  get_main_inventory = function() return inv({ { name = "iron-plate", quality = "normal", count = 50 },
    { name = "coal", quality = "normal", count = 200 } }) end,
  get_inventory = function(id)
    if id == 2 then return inv({ { name = "modular-armor", quality = "normal", count = 1 } }, grid) end
    if id == 3 then return inv({ { name = "submachine-gun", quality = "normal", count = 1 } }) end
    if id == 4 then return inv({ { name = "firearm-magazine", quality = "normal", count = 30 } }) end
  end,
}
local out = personal_logic.inventory(player)
assert(out.online == true and out.readable == true)
assert(out.main[1].name == "coal" and out.main[2].name == "iron-plate", "biggest stacks first")
assert(out.armor.name == "modular-armor" and out.armor.equipment[1].name == "solar-panel-equipment")
assert(out.guns[1] == "submachine-gun" and out.ammo[1].count == 30 and out.crafting_queue_size == 2)

-- an offline player whose inventory cannot be read
local offline = { connected = false, get_main_inventory = function() return nil end, get_inventory = function() return nil end }
local off = personal_logic.inventory(offline)
assert(off.online == false and off.readable == false and off.main == nil)
-- reading raises (no character): also unreadable, not an error
local broken = { connected = false, get_main_inventory = function() error("no character") end }
assert(personal_logic.inventory(broken).readable == false)
-- Factorio 2.1, checked live: an offline player has no character, yet get_main_inventory() returns a
-- valid EMPTY inventory; it is not the player's real inventory, so offline is always unreadable
local ghost_inv = inv({})
local offline_empty = { connected = false, crafting_queue_size = 0,
  get_main_inventory = function() return ghost_inv end, get_inventory = function() return inv({}) end }
local oe = personal_logic.inventory(offline_empty)
assert(oe.online == false and oe.readable == false and oe.main == nil, "offline: readable false, no lists")

-- alerts: grouped by type, with examples on the right surface
local alerts = {
  [1] = {
    [0] = { { target = { name = "stone-wall", position = { x = 1, y = 2 } } }, { position = { x = 3, y = 4 }, prototype = { name = "gun-turret" } } },
    [1] = { { target = { name = "gun-turret", position = { x = 5, y = 6 } } } },
  },
}
local surfaces = { [1] = { name = "nauvis" } }
local a = personal_logic.alerts(alerts, surfaces, 1)
assert(a.by_type[1].type == "entity_destroyed" and a.by_type[1].count == 2, "most alerts first")
assert(#a.by_type[1].examples == 1, "examples capped at the limit")
assert(a.by_type[1].examples[1].gps == "[gps=1,2,nauvis]" and a.by_type[1].examples[1].name == "stone-wall")
assert(a.by_type[2].type == "turret_out_of_ammo")
assert(#personal_logic.alerts({}, surfaces, 5).by_type == 0)

print("personal_logic_test ok")
