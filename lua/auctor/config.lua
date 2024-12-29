local M = {}

-- Default configuration
if vim.g.auctor_prompt_func == nil then
  vim.g.auctor_prompt_func = function()
    return [[
You are an expert, top-of-your-field software developer.  
The code you produce is lucid, elegant, and of exceptional quality.  
Your work in this session is mission-critical for an extremely noble, paramount, and immediate goal.
]]
  end
end

-- API key can be set in vim.g.auctor_api_key. If not set, will check OPENAI_API_KEY env
-- If still not found, return error.
-- No default API key.

if vim.g.auctor_model == nil then
  vim.g.auctor_model = "gpt-4o"
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

if vim.g.auctor_instruction_marker == nil then
  vim.g.auctor_instruction_marker = "|||"
end

if vim.g.auctor_update_prompt == nil then
  vim.g.auctor_update_prompt = [[
    The following string is called the INSTRUCTION_MARKER: "]] .. vim.g.auctor_instruction_marker .. [[". 
    Update the provided code according to the comments starting with INSTRUCTION_MARKER. 
    Reply with a single codeblock containing modified code and remove all comments with INSTRUCTION_MARKER.
    If you need clarification, embed your questions into the codeblock as comments.
    Do not provide *any* text outside of the codeblock.
  ]]
end

if vim.g.auctor_add_prompt == nil then
  vim.g.auctor_add_prompt = [[
    This message will provide you with the contents of a file (in a code block), as well as file metadata.
    Analyze it and use your understanding responding to the future prompts.
    If this file was provided before, assume this prompt includes the latest version.
    Respond with "Understood". No other explanation or code is required.
  ]]
end

return M
