data:extend({
  {
    type = "int-setting",
    name = "factorio-mcp-work-per-tick",
    setting_type = "runtime-global",
    default_value = 50,
    minimum_value = 1,
    maximum_value = 2000,
    order = "a",
  },
  {
    type = "int-setting",
    name = "factorio-mcp-idle-work-per-poll",
    setting_type = "runtime-global",
    default_value = 20000,
    minimum_value = 1,
    maximum_value = 200000,
    order = "b",
  },
})
