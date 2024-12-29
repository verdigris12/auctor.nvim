local M = {}
local api = require('auctor.api')

function M.setup_commands()
  vim.api.nvim_create_user_command('AuctorUpdate', function()
    api.auctor_update()
  end, {range=true})

  vim.api.nvim_create_user_command('AuctorAdd', function()
    api.auctor_add()
  end, {})

  vim.api.nvim_create_user_command('AuctorAutoAddToggle', function()
    api.auctor_auto_add_toggle()
  end, {})

  vim.api.nvim_create_user_command('AuctorSelect', function()
    api.auctor_select()
  end, {})

  vim.api.nvim_create_user_command('AuctorInsert', function()
    api.auctor_insert()
  end, {})
end

function M.setup_autocmds()
  -- Autocmd to run AuctorAdd automatically if enabled
  vim.api.nvim_create_autocmd({"BufReadPost", "BufNewFile"}, {
    callback = function()
      api.auto_add_if_enabled()
    end
  })
end

return M
