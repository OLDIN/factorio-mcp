data:extend({
  {
    type = "int-setting",
    name = "factorio-mcp-chunks-per-tick",
    setting_type = "runtime-global",
    default_value = 8,
    minimum_value = 1,
    maximum_value = 256,
    order = "a",
  },
  {
    type = "int-setting",
    name = "factorio-mcp-idle-chunks-per-poll",
    setting_type = "runtime-global",
    default_value = 512,
    minimum_value = 1,
    maximum_value = 8192,
    order = "b",
  },
})
