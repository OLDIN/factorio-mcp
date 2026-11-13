-- Reply envelope: one line of JSON, {"v":1,"ok":true,"result":...} or {"v":1,"ok":false,"error":{...}}.
local M = {}

M.PROTOCOL = 1

local function finite(n)
  return n == n and n ~= math.huge and n ~= -math.huge
end

local function is_array(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  for i = 1, n do
    if t[i] == nil then return false end
  end
  return n > 0
end

-- Returns a copy of `value` without non-finite numbers (NaN, +inf, -inf): they are not valid JSON.
-- Such table fields disappear; array elements are dropped so the array stays an array.
function M.sanitize(value)
  local tv = type(value)
  if tv == "number" then
    if finite(value) then return value end
    return nil
  end
  if tv ~= "table" then return value end
  local out = {}
  if is_array(value) then
    for i = 1, #value do
      local v = M.sanitize(value[i])
      if v ~= nil then out[#out + 1] = v end
    end
    return out
  end
  for k, v in pairs(value) do
    local clean = M.sanitize(v)
    if clean ~= nil then out[k] = clean end
  end
  return out
end

function M.ok(result)
  return helpers.table_to_json({ v = M.PROTOCOL, ok = true, result = M.sanitize(result or {}) })
end

function M.err(code, message)
  message = tostring(message or ""):gsub("[%c]+", " "):sub(1, 200)
  return helpers.table_to_json({ v = M.PROTOCOL, ok = false, error = { code = code, message = message } })
end

return M
