local M = {}

local config = require('auctor.config')
local commands = require('auctor.commands')

function M.setup()
  commands.setup_autocmds()
  commands.setup_commands()
end

return M
