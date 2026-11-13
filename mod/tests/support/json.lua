-- Minimal JSON encoder/decoder for the pure-Lua mod tests (stands in for helpers.table_to_json /
-- helpers.json_to_table). Like the game, it encodes an empty table as [].
local M = {}

local escapes = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }

local function encode_string(s)
  return '"' .. s:gsub('[%c"\\]', function(c)
    return escapes[c] or string.format("\\u%04x", c:byte())
  end) .. '"'
end

local function is_array(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  for i = 1, n do
    if t[i] == nil then return false end
  end
  return true
end

function M.encode(v)
  local tv = type(v)
  if tv == "nil" then return "null" end
  if tv == "boolean" then return tostring(v) end
  if tv == "number" then
    assert(v == v and v ~= math.huge and v ~= -math.huge, "non-finite number cannot be encoded")
    return string.format("%.14g", v)
  end
  if tv == "string" then return encode_string(v) end
  assert(tv == "table", "cannot encode " .. tv)
  local parts = {}
  if is_array(v) then
    for i = 1, #v do parts[i] = M.encode(v[i]) end
    return "[" .. table.concat(parts, ",") .. "]"
  end
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = tostring(k) end
  table.sort(keys)
  for _, k in ipairs(keys) do
    parts[#parts + 1] = encode_string(k) .. ":" .. M.encode(v[k])
  end
  return "{" .. table.concat(parts, ",") .. "}"
end

-- Decoder: returns the value or raises an error on malformed input.
function M.decode(s)
  local pos = 1
  local function fail() error("invalid json at " .. pos, 0) end
  local function skip() pos = s:find("%S", pos) or (#s + 1) end
  local value

  local function str()
    local out = {}
    pos = pos + 1
    while true do
      local c = s:sub(pos, pos)
      if c == "" then fail() end
      if c == '"' then pos = pos + 1; return table.concat(out) end
      if c == "\\" then
        local e = s:sub(pos + 1, pos + 1)
        local map = { n = "\n", r = "\r", t = "\t", ['"'] = '"', ["\\"] = "\\", ["/"] = "/" }
        if e == "u" then
          out[#out + 1] = string.char(tonumber(s:sub(pos + 2, pos + 5), 16) % 256)
          pos = pos + 6
        elseif map[e] then
          out[#out + 1] = map[e]
          pos = pos + 2
        else
          fail()
        end
      else
        out[#out + 1] = c
        pos = pos + 1
      end
    end
  end

  function value()
    skip()
    local c = s:sub(pos, pos)
    if c == "{" then
      local t = {}
      pos = pos + 1
      skip()
      if s:sub(pos, pos) == "}" then pos = pos + 1; return t end
      while true do
        skip()
        if s:sub(pos, pos) ~= '"' then fail() end
        local k = str()
        skip()
        if s:sub(pos, pos) ~= ":" then fail() end
        pos = pos + 1
        t[k] = value()
        skip()
        local d = s:sub(pos, pos)
        pos = pos + 1
        if d == "}" then return t end
        if d ~= "," then fail() end
      end
    elseif c == "[" then
      local t = {}
      pos = pos + 1
      skip()
      if s:sub(pos, pos) == "]" then pos = pos + 1; return t end
      while true do
        t[#t + 1] = value()
        skip()
        local d = s:sub(pos, pos)
        pos = pos + 1
        if d == "]" then return t end
        if d ~= "," then fail() end
      end
    elseif c == '"' then
      return str()
    elseif s:sub(pos, pos + 3) == "true" then pos = pos + 4; return true
    elseif s:sub(pos, pos + 4) == "false" then pos = pos + 5; return false
    elseif s:sub(pos, pos + 3) == "null" then pos = pos + 4; return nil
    else
      local num = s:match("^-?%d+%.?%d*[eE]?[+-]?%d*", pos)
      if not num or num == "" then fail() end
      pos = pos + #num
      return tonumber(num) or fail()
    end
  end

  local result = value()
  skip()
  if pos <= #s then fail() end
  return result
end

return M
