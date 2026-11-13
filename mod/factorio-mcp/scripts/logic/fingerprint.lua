-- Canonical description of the mod set and startup settings (pure). The service hashes it and
-- refreshes its reference cache when it changes. Startup settings are included because they can
-- change prototypes (recipes, machines).
local M = {}

local SECRET_PATTERNS = { "token", "key", "secret", "password" }

local function looks_secret(name)
  local lower = tostring(name):lower()
  for _, pattern in ipairs(SECRET_PATTERNS) do
    if lower:find(pattern, 1, true) then return true end
  end
  return false
end

local function sorted_keys(t)
  local keys = {}
  for k in pairs(t) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  return keys
end

local function serialize(value)
  if type(value) ~= "table" then return tostring(value) end
  local parts = {}
  for _, k in ipairs(sorted_keys(value)) do
    parts[#parts + 1] = tostring(k) .. "=" .. serialize(value[k])
  end
  return "{" .. table.concat(parts, ",") .. "}"
end

-- mods: name -> version; startup: setting name -> value
function M.canonical(mods, startup)
  local lines = {}
  for _, name in ipairs(sorted_keys(mods or {})) do
    lines[#lines + 1] = "mod:" .. name .. "=" .. tostring(mods[name])
  end
  for _, name in ipairs(sorted_keys(startup or {})) do
    if not looks_secret(name) then
      lines[#lines + 1] = "startup:" .. name .. "=" .. serialize(startup[name])
    end
  end
  return table.concat(lines, "\n")
end

return M
