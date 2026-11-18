-- Parameter validation shared by the subcommands. Errors are {code = "bad_params", message}.
local M = {}

local function bad(message) error({ code = "bad_params", message = message }) end

-- A finite number, or `default` when absent.
function M.number(p, key, default)
  local v = p[key]
  if v == nil then return default end
  if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then
    bad(key .. " must be a finite number")
  end
  return v
end

-- An integer in [min, max], or `default` when absent.
function M.int(p, key, default, min, max)
  local v = p[key]
  if v == nil then return default end
  if type(v) ~= "number" or v ~= math.floor(v) or v < min or v > max then
    bad(key .. " must be an integer between " .. min .. " and " .. max)
  end
  return v
end

-- A string, or `default` (may be nil) when absent.
function M.string(p, key, default)
  local v = p[key]
  if v == nil then return default end
  if type(v) ~= "string" then bad(key .. " must be a string") end
  return v
end

-- One of the `allowed` strings, or `default` when absent.
function M.one_of(p, key, default, allowed)
  local v = p[key]
  if v == nil then return default end
  for _, a in ipairs(allowed) do
    if v == a then return v end
  end
  bad(key .. " must be one of: " .. table.concat(allowed, ", "))
end

return M
