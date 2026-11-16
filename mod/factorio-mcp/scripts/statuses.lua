-- Name of a LuaEntity.status value, from the reverse of defines.entity_status.
local M = {}

local reverse

local function build()
  reverse = {}
  for name, value in pairs(defines.entity_status) do reverse[value] = name end
end

function M.name(status)
  if status == nil then return "none" end
  if not reverse then build() end
  return reverse[status] or "unknown"
end

return M
