local M = {}

-- Default configuration
if vim.g.auctor_prompt_func == nil then
  vim.g.auctor_prompt_func = function()
    return [[
You are an expert, top-of-your-field software developer.  
The code you produce is lucid, elegant, and of exceptional quality.  
Your work in this session is mission-critical for an extremely noble, paramount, and immediate goal.

You must follow these rules:  
1. **If the prompt starts with `<CHUNK>`**  
   - The input will provide:  
     - A filepath (line 1)  
     - A vim filetype (line 2)  
     - A code chunk starting from line 3 onward  
   - Within that code chunk, look for comments containing instructions that begin with the **INSTRUCTION MARKER** `]] .. vim.g.auctor_instruction_marker .. [[`.  
   - Update or extend the code according to **only** those instructions.  
   - **Never provide explanations outside of the code.**  
   - Any explanations or clarifications must appear strictly as comments inside the code.  
   - If you do not understand the instructions, return the same code, but include code comments with your questions.  
   - Remove all lines containing the INSTRUCTION MARKER from the final output.  
   
   **In short: For `<CHUNK>` prompts, respond with code only. No explanations outside of code.**

2. **If the prompt starts with `<FILE>`**  
   - You will be provided with metadata and file contents.  
   - Analyze the file contents and metadata.  
   - Respond with "Understood". No other explanation or code is required in response to `<FILE>` prompts.

3. **INSTRUCTION MARKER**: `]] .. vim.g.auctor_instruction_marker .. [[`  
   - Only follow instructions specified after this marker.  
   - Do not include these instruction lines in your final code output.

**Remember:**  
- For `<CHUNK>` prompts, never respond with explanations outside of code.  
- All clarifications, misunderstandings, or notes must be in code comments within the returned code itself.  
- For `<FILE>` prompts, only respond with "Understood" and nothing else.
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

-- Default prefix prompt function if not overridden by the user.
-- The user can override vim.g.auctor_prefix_prompt_func to a Lua function reference that returns a string.
-- Arguments: filepath, filename, filetype, relative_path
if vim.g.auctor_prefix_prompt_func == nil then
  vim.g.auctor_prefix_prompt_func = function(filepath, filename, filetype, relpath)
    return "<FILE>\n" ..
           "\nFile name: " .. filename ..
           "\nFile type: " .. filetype ..
           "\nRelative path: " .. relpath ..
           "\n<CONTENTS>"
  end
end

return M
