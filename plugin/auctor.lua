-- This file registers Auctor when Neovim starts.
-- It loads the core module and calls its setup() function with any global
-- configuration provided via `vim.g.auctor_opts`.

-- Prevent double-loading
if vim.g.loaded_auctor then
  return
end
vim.g.loaded_auctor = true

-- Attempt to load the main module. If it fails, print an error.
local ok, auctor = pcall(require, 'auctor')
if not ok then
  vim.api.nvim_err_writeln('Auctor: failed to load core module: ' .. tostring(auctor))
  return
end

-- Pull any user-provided options from a global var for backwards
-- compatibility. Users are encouraged to call require('auctor').setup()
-- directly instead of setting vim.g.auctor_opts.
local opts = nil
if type(vim.g.auctor_opts) == 'table' then
  opts = vim.g.auctor_opts
end

auctor.setup(opts)
