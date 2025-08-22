-- Command registration for Auctor. This module defines the Neovim
-- user-commands and autocmds that drive the plugin.

local api = require('auctor.api')
local state = require('auctor.state')
local providers = require('auctor.providers')
local ui = require('auctor.ui_config')

local M = {}

--- Setup all user commands for Auctor. Commands are:
--   :AuctorUpdate         – Update the visual selection
--   :AuctorAdd            – Upload the entire buffer
--   :AuctorInsert         – Insert an instruction marker
--   :AuctorAutoAddToggle  – Toggle automatic add on BufReadPost/BufNewFile
--   :AuctorUse [name]     – Switch to a provider
--   :AuctorAbort          – Cancel the current request
--   :AuctorStatus         – Show plugin status
--   :AuctorConfigUI       – Open provider configuration UI
function M.setup_commands()
  vim.api.nvim_create_user_command('AuctorUpdate', function()
    api.auctor_update()
  end, { range = true, desc = 'Update the selected region via Auctor' })

  vim.api.nvim_create_user_command('AuctorAdd', function()
    api.auctor_add()
  end, { desc = 'Upload the current buffer via Auctor' })

  vim.api.nvim_create_user_command('AuctorInsert', function()
    api.auctor_insert()
  end, { desc = 'Insert an instruction marker' })

  vim.api.nvim_create_user_command('AuctorAutoAddToggle', function()
    api.auctor_auto_add_toggle()
  end, { desc = 'Toggle automatic add on BufRead/BufNew' })

  vim.api.nvim_create_user_command('AuctorUse', function(opts)
    api.auctor_use(opts.args)
  end, { nargs = '?', complete = function()
    local items = {}
    for name in pairs(state.providers) do
      table.insert(items, name)
    end
    return items
  end, desc = 'Set the active Auctor provider' })

  vim.api.nvim_create_user_command('AuctorAbort', function()
    api.auctor_abort()
  end, { desc = 'Abort the active Auctor request' })

  vim.api.nvim_create_user_command('AuctorStatus', function()
    api.auctor_status()
  end, { desc = 'Show Auctor status' })

  vim.api.nvim_create_user_command('AuctorConfigUI', function()
    ui.show_config_ui()
  end, { desc = 'Open the provider configuration UI' })
end

--- Setup autocmds for auto-add. Registers a BufReadPost and BufNewFile
-- autocmd which calls auto_add_if_enabled() from api.lua if
-- the auto_add option is enabled.
function M.setup_autocmds()
  vim.api.nvim_create_autocmd({ 'BufReadPost', 'BufNewFile' }, {
    callback = function()
      api.auto_add_if_enabled()
    end,
  })
end

return M