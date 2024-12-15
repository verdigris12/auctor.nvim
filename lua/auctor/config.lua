local M = {}

-- Default configuration
if vim.g.auctor_prompt == nil then
  vim.g.auctor_prompt = "Replace text according to comments"
end

-- API key can be set in vim.g.auctor_api_key. If not set, will check OPENAI_API_KEY env
-- If still not found, return error.
-- No default API key.

if vim.g.auctor_model == nil then
  vim.g.auctor_model = "gpt-3.5-turbo"
end

if vim.g.auctor_temperature == nil then
  vim.g.auctor_temperature = 0.7
end

-- Keep track of whether the first AuctorUpdate was called in this session
if _G.auctor_session_first_update_called == nil then
  _G.auctor_session_first_update_called = false
end

-- Keep track of total amount spent in this session
if _G.auctor_session_total_cost == nil then
  _G.auctor_session_total_cost = 0
end

-- Auto add toggle
if vim.g.auctor_auto_add == nil then
  vim.g.auctor_auto_add = false
end

-- Default prefix prompt function if not overridden by the user.
-- The user can override vim.g.auctor_prefix_prompt_func to a Lua function reference that returns a string.
-- Arguments: filepath, filename, filetype, relative_path
if vim.g.auctor_prefix_prompt_func == nil then
  vim.g.auctor_prefix_prompt_func = function(filepath, filename, filetype, relpath)
    return "You are analyzing a file.\nFile path: " .. filepath ..
           "\nFile name: " .. filename ..
           "\nFile type: " .. filetype ..
           "\nRelative path: " .. relpath ..
           "\nBelow is the file content. Please analyze it, but do not return a transformation here."
  end
end

return M
