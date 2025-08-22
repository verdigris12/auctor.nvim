-- Minimal TOML parser and writer for the Auctor configuration file.
-- We deliberately avoid external dependencies to keep installation
-- simple. The parser only understands the subset of TOML required for
-- provider definitions:
--   [providers.NAME]
--   key = "value"
--   key = number
--   key = true/false
-- Lines beginning with # are ignored. Blank lines are skipped.

local M = {}

local function trim(s)
  return (s:gsub('^%s+', ''):gsub('%s+$', ''))
end

--- Parse TOML configuration content into a providers table.
-- @param content string: the raw contents of a TOML file
-- @return table providers: map of provider names to config tables
function M.parse(content)
  local providers = {}
  local current = nil
  for raw_line in content:gmatch('[^\r\n]+') do
    local line = trim(raw_line)
    -- Skip empty lines and comments
    if line ~= '' and not line:match('^#') then
      local section = line:match('^%[providers%.([%w%.-_]+)%]$')
      if section then
        current = {}
        providers[section] = current
      elseif current then
        local key, value = line:match('^([%w_]+)%s*=%s*(.+)$')
        if key then
          value = trim(value)
          -- Remove surrounding quotes for strings
          if value:match('^".*"$') then
            value = value:sub(2, -2)
            value = value:gsub('\\"', '"')
          elseif value:match('^[0-9%.]+$') then
            value = tonumber(value)
          elseif value == 'true' or value == 'false' then
            value = value == 'true'
          end
          current[key] = value
        end
      end
    end
  end
  return providers
end

--- Serialise the providers table into TOML format.
-- Only the known keys are emitted in a deterministic order. Unknown keys
-- are ignored. The active provider (if provided) is written with
-- `active = true` to aid discovery on load.
-- @param providers table: map of provider names to config tables
-- @param active_name string|nil: name of the active provider
-- @return string TOML document
function M.serialize(providers, active_name)
  local lines = {}
  local order = {
    'base_url', 'model', 'temperature', 'api_key_env', 'update_prompt', 'add_prompt'
  }
  -- Sort providers alphabetically for stability
  local names = {}
  for name in pairs(providers) do
    table.insert(names, name)
  end
  table.sort(names)
  for _, name in ipairs(names) do
    local data = providers[name]
    table.insert(lines, string.format('[providers.%s]', name))
    for _, key in ipairs(order) do
      local v = data[key]
      if v ~= nil then
        if type(v) == 'string' then
          local escaped = v:gsub('"', '\\"')
          table.insert(lines, string.format('%s = "%s"', key, escaped))
        elseif type(v) == 'number' then
          table.insert(lines, string.format('%s = %s', key, tostring(v)))
        elseif type(v) == 'boolean' then
          table.insert(lines, string.format('%s = %s', key, v and 'true' or 'false'))
        end
      end
    end
    if active_name and active_name == name then
      table.insert(lines, 'active = true')
    end
    table.insert(lines, '') -- blank line after each provider
  end
  return table.concat(lines, '\n')
end

return M