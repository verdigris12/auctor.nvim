-- Healthcheck for the Auctor plugin. Implements :checkhealth auctor

local providers = require('auctor.providers')
local state = require('auctor.state')

local M = {}

function M.check()
  local health = vim.health or vim.healthcheck
  if not health or not health.report_start then
    vim.api.nvim_err_writeln('Healthcheck API not available')
    return
  end
  health.report_start('Auctor')
  -- Check Neovim version for vim.system and vim.json
  local has_system = vim.system ~= nil
  if has_system then
    health.report_ok('vim.system is available')
  else
    health.report_error('vim.system is not available; Neovim >= 0.10 is required')
  end
  -- Check curl executable
  if vim.fn.executable('curl') == 1 then
    health.report_ok('curl executable found')
  else
    health.report_error('curl executable not found in PATH')
  end
  -- Check active provider
  local p = providers.get_active()
  if p then
    health.report_ok('Active provider: ' .. (p.model or '') .. ' via ' .. (p.base_url or ''))
    -- Check API key env
    if p.api_key_env and p.api_key_env ~= '' then
      if os.getenv(p.api_key_env) then
        health.report_ok('Environment variable ' .. p.api_key_env .. ' is set')
      else
        health.report_warn('Environment variable ' .. p.api_key_env .. ' is not set; API calls will fail')
      end
    else
      health.report_warn('Provider ' .. (state.active_provider or 'default') .. ' does not specify api_key_env; API calls may fail')
    end
  else
    health.report_warn('No active provider configured')
  end
end

return M