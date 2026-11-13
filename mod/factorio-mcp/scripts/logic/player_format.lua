-- Pure logic for formatting player entries and redacting sensitive mod settings.
local M = {}

local SECRET_PATTERNS = { "token", "key", "secret", "password" }

local function looks_secret(name)
  local lower = tostring(name):lower()
  for _, pattern in ipairs(SECRET_PATTERNS) do
    if lower:find(pattern, 1, true) then return true end
  end
  return false
end

local function is_string_value(v)
  if type(v) == "string" then return true end
  if type(v) == "table" and type(v.value) == "string" then return true end
  return false
end

local function redact_category(cat)
  if type(cat) ~= "table" then return cat end
  local out = {}
  for k, v in pairs(cat) do
    if looks_secret(k) and is_string_value(v) then
      -- omitted
    elseif type(v) == "table" and v.value == nil then
      out[k] = redact_category(v)
    else
      out[k] = v
    end
  end
  return out
end

function M.redact_settings(settings)
  if type(settings) ~= "table" then return settings end
  local out = {}
  for cat_name, cat in pairs(settings) do
    out[cat_name] = redact_category(cat)
  end
  return out
end

function M.format_player(fields)
  if not fields then return nil end

  local is_online = (fields.connected == true)
  local pos = nil
  local surf = nil

  if is_online then
    local raw_pos = fields.physical_position or fields.position
    if raw_pos then
      pos = { x = raw_pos.x, y = raw_pos.y }
    end
    local raw_surf = fields.physical_surface or fields.surface
    if type(raw_surf) == "table" and raw_surf.name then
      surf = raw_surf.name
    elseif type(raw_surf) == "string" then
      surf = raw_surf
    end
  end

  local color = nil
  if fields.color then
    color = {
      r = fields.color.r,
      g = fields.color.g,
      b = fields.color.b,
      a = fields.color.a,
    }
  end

  return {
    name = fields.name,
    index = fields.index,
    online = is_online,
    admin = (fields.admin == true),
    afk_ticks = fields.afk_time or fields.afk_ticks or 0,
    online_ticks = fields.online_time or fields.online_ticks or 0,
    color = color,
    position = pos,
    surface = surf,
  }
end

return M
