-- This file runs when the plugin is loaded. It sets up the plugin.
-- It requires the main module.
if vim.g.loaded_auctor then
  return
end
vim.g.loaded_auctor = true

require('auctor').setup()
