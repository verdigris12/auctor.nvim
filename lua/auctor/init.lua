-- Entry point for the Auctor plugin. Exposes a setup() function
-- which initialises state, loads provider configuration files and
-- registers commands and autocmds.

local state = require('auctor.state')
local providers = require('auctor.providers')
local commands = require('auctor.commands')
local util = require('auctor.util')
local config = require('auctor.config')

local M = {}

--- Initialise Auctor. This function should be called once when the
-- plugin is loaded. Options override the built-in defaults:
--   instruction_marker (string)
--   system_update_prompt (string)
--   system_add_prompt (string)
--   auto_add (boolean)
--   providers (table) – optional provider definitions to merge
function M.setup(opts)
  opts = opts or {}
  -- Merge opts into state.opts, falling back to defaults
  state.opts.instruction_marker = opts.instruction_marker or config.default_instruction_marker
  -- If the user supplies a system update prompt use it, otherwise build one from the marker
  if opts.system_update_prompt then
    state.opts.system_update_prompt = opts.system_update_prompt
  else
    state.opts.system_update_prompt = config.build_update_prompt(state.opts.instruction_marker)
  end
  state.opts.system_add_prompt = opts.system_add_prompt or config.default_system_add_prompt
  state.opts.auto_add = opts.auto_add or false
  -- Initial session state
  state.session_first_update_called = false
  state.session_total_cost = 0
  state.current_job = nil
  -- Install user-provided providers if given
  if opts.providers then
    for name, def in pairs(opts.providers) do
      state.providers[name] = def
    end
  end
  -- Load providers from config file if present
  local path = providers.load_from_file()
  -- Ensure at least the default provider exists
  providers.ensure_default()
  -- Notify the user if a file was loaded
  if path then
    util.notify('Auctor config loaded from ' .. path, 'info')
  end
  -- Register user commands and autocmds
  commands.setup_commands()
  commands.setup_autocmds()
end

return M