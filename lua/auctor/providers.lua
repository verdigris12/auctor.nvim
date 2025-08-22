-- Provider management for Auctor. Handles loading from and saving to
-- configuration files, default provider creation and switching active
-- providers. The providers table lives in state.providers.

local state = require('auctor.state')
local toml = require('auctor.toml')

local M = {}

--- Return a table of default providers. At least one provider named
--- "default" will always exist. Other modules should call
--- providers.ensure_default() after loading from disk to guarantee
--- defaults are present.
function M.default_providers()
  return {
    default = {
      base_url = 'https://api.openai.com/v1/chat/completions',
      model = 'gpt-4o',
      temperature = 0.7,
      api_key_env = 'OPENAI_API_KEY',
      update_prompt = '',
      add_prompt = '',
    },
  }
end

--- Ensure that the providers table contains a default provider. If no
--- providers exist, the default provider is installed and set active.
function M.ensure_default()
  if not next(state.providers) then
    state.providers = M.default_providers()
    state.active_provider = 'default'
  elseif state.providers.default == nil then
    state.providers.default = M.default_providers().default
  end
  -- If no active provider is set but default exists, set it.
  if not state.active_provider then
    state.active_provider = 'default'
  end
end

--- Find the configuration file path for reading. Preference is given to
--- a file named `.auctor.toml` in the current working directory. If
--- absent, $XDG_CONFIG_HOME/auctor/auctor.toml is used when readable.
-- @return string|nil Path to config file or nil if none found
function M.find_config_path_for_loading()
  local cwd_file = vim.fn.getcwd() .. '/.auctor.toml'
  if vim.fn.filereadable(cwd_file) == 1 then
    return cwd_file
  end
  local config_home = vim.fn.stdpath('config')
  local fallback = config_home .. '/auctor/auctor.toml'
  if vim.fn.filereadable(fallback) == 1 then
    return fallback
  end
  return nil
end

--- Load providers from the first configuration file found. Updates
--- state.providers and state.active_provider accordingly. If a file
--- contains a provider with `active = true`, that provider becomes
--- active. Returns the path of the file loaded or nil.
-- @return string|nil path: path to loaded file, or nil if none loaded
function M.load_from_file()
  local path = M.find_config_path_for_loading()
  if not path then
    return nil
  end
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then
    return nil
  end
  local content = table.concat(lines, '\n')
  local parsed = toml.parse(content)
  local active = nil
  for name, data in pairs(parsed) do
    if data.active == true then
      active = name
      data.active = nil
    end
  end
  if next(parsed) then
    state.providers = parsed
    state.active_provider = active or state.active_provider
    return path
  end
  return nil
end

--- Save providers to the given path. Creates intermediate directories
--- if necessary. Serialises state.providers and state.active_provider.
-- @param path string: destination file path
function M.save_to_file(path)
  -- Ensure directory exists
  local dir = vim.fn.fnamemodify(path, ':h')
  if vim.fn.isdirectory(dir) == 0 then
    vim.fn.mkdir(dir, 'p')
  end
  local content = toml.serialize(state.providers, state.active_provider)
  -- Split into lines for writefile
  local lines = {}
  for s in content:gmatch('[^\n]*\n?') do
    if s ~= '' then
      if s:sub(-1) == '\n' then
        table.insert(lines, s:sub(1, -2))
      else
        table.insert(lines, s)
      end
    end
  end
  vim.fn.writefile(lines, path)
end

--- Add or update a provider. Overwrites any existing definition with
--- the same name. Does not alter the active provider.
-- @param name string provider name
-- @param data table provider definition
function M.add_provider(name, data)
  state.providers[name] = data
end

--- Remove a provider by name. If the removed provider was active,
--- the active provider is cleared. The caller should then call
--- ensure_default() afterwards.
-- @param name string provider name
function M.delete_provider(name)
  state.providers[name] = nil
  if state.active_provider == name then
    state.active_provider = nil
  end
end

--- Set the active provider by name. Returns true if the provider
--- exists, false otherwise. Does not persist to disk.
-- @param name string provider name
function M.set_active(name)
  if state.providers[name] then
    state.active_provider = name
    return true
  end
  return false
end

--- Get the definition of the active provider. Falls back to the
--- default provider if no active provider is set.
-- @return table provider definition
function M.get_active()
  return state.providers[state.active_provider] or state.providers.default
end

return M