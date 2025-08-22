-- Internal state used by the Auctor plugin.
-- This module centralises mutable state so that other modules can
-- coordinate without polluting the global namespace.

local M = {}

-- Options set by the user via setup(). These are merged with the
-- defaults in config.lua when the plugin initialises.
M.opts = {}

-- Provider registry. This table maps provider names to provider
-- definitions. A provider definition has at least the following keys:
--   base_url        (string)  -- HTTP endpoint for chat completions
--   model           (string)  -- default model name
--   temperature     (number)  -- temperature for sampling
--   api_key_env     (string)  -- name of environment variable containing API key
--   headers         (table)   -- optional extra headers as { key = value }
--   update_prompt   (string)  -- provider-specific system prompt for update requests
--   add_prompt      (string)  -- provider-specific system prompt for add requests
M.providers = {}

-- Name of the currently active provider. If nil, the default provider is
-- used. Commands such as :AuctorUse set this value.
M.active_provider = nil

-- Tracks whether the first update call has occurred in this session. This
-- affects whether the system prompt is sent on the first :AuctorUpdate.
M.session_first_update_called = false

-- Total cost accumulated in this Neovim session. Costs are computed per
-- request based on token usage and provider pricing.
M.session_total_cost = 0

-- Handle of the currently running HTTP job. Used by :AuctorAbort to
-- cancel in-flight requests.
M.current_job = nil

return M