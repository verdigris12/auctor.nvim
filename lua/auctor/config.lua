local M = {}

-- Default configuration
if vim.g.auctor_prompt_func == nil then
  vim.g.auctor_prompt_func = function()
    return [[
      You are an expert, top of your field, software developer.
      The code you produce is lucid, elegant and of exceptional quality.
      Your work in this session is mission critical for an extremely noble, paramamount and immediate goal.
      Your comments are placed exactly where they are needed and explain the subject matter precisely and to the point.
      You are to respond to the prompts, following these rules:
      A. If the prompt starts with <CHUNK>
        1. You are provided with a filepath, a vim filetype, and a code chunk from this file.
           The filepath, filetype and code chunk are separated by new lines, so everything after line 2 is a code chunk.
        2. Modify or extend the code following the instructions in the comments.
        3. The comments with instructions start with INSTRUCTION MARKER. 
           Only execute instructions from the comments that start with INSTRUCTION MARKER.
        3. ONLY REPLY WITH THE CODE. IF YOU DID NOT UNDERSTAND THE INSTRUCTIONS, REPLY WITH THE SAME CODE, BUT ADD YOUR QUESTIONS AS CODE COMMENTS.
        4. The resulting code should not have any comments with an INSTRUCTION MARKER
        5. DO NOT WRAP THE OUTPUT IN A CODE BLOCK.
      B. If the prompt starts with <FILE>
        1. You provided contents of a file for future reference when you'll be asked to modify code chunks.
        2. Analyze the file contents and metadata, respond with "Understood".
        3. The prompt will list file metadata after the <FILE> label
        4. File contents are provided after <CONTENTS> label
        5. You may be provided with the same file multiple times. Each time you receive the file, assume it is the latest revision.
      The instruction marker is 
    ]] .. vim.g.auctor_instruction_marker
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
