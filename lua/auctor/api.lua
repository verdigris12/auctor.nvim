local util = require('auctor.util')
local config = require('auctor.config')

local M = {}


function M.auctor_update()
  local api_key = util.get_api_key()
  if not api_key then
    vim.api.nvim_err_writeln("Auctor: No API key set. Please set vim.g.auctor_api_key or OPENAI_API_KEY.")
    return
  end

  local selection = util.get_visual_selection()
  if selection == "" then
    vim.api.nvim_err_writeln("AuctorUpdate: No text selected.")
    return
  end

  local messages = {}
  if not _G.auctor_session_first_update_called then
    table.insert(messages, {role="system", content=vim.g.auctor_prompt_func()})
    _G.auctor_session_first_update_called = true
  end

  table.insert(messages, {role="user", content=selection})

  local resp, err = util.call_openai(messages, vim.g.auctor_model, vim.g.auctor_temperature)
  if err then
    vim.api.nvim_err_writeln("AuctorUpdate error: " .. err)
    return
  end

  local content = resp.choices[1].message.content or ""

  -- Remove only the first and last occurrences of ```
  local first = content:find("```", 1, true)
  if first then
    -- Find the last occurrence of ``` by searching from the end
    local lastPos = nil
    local startPos = 1
    while true do
      local found = content:find("```", startPos, true)
      if not found then break end
      lastPos = found
      startPos = found + 3
    end

    -- If we have both a first and a last occurrence (and they differ)
    if lastPos and lastPos ~= first then
      -- Remove the last occurrence
      content = content:sub(1, lastPos - 1) .. content:sub(lastPos + 3)
    end

    -- Remove the first occurrence
    content = content:sub(1, first - 1) .. content:sub(first + 3)
  end

  util.replace_visual_selection(content)

  local cost = util.calculate_cost(resp.usage, vim.g.auctor_model)
  _G.auctor_session_total_cost = _G.auctor_session_total_cost + cost
  print(string.format("Auctor: Spent $%.6f this transaction. Total: $%.6f this session.", cost, _G.auctor_session_total_cost))
end

-- AuctorAdd:
-- 1. Uploads the current buffer with a prefix prompt
-- 2. Does not return the resulting prompt
-- 3. Prints cost and accumulate total
function M.auctor_add()
  local api_key = util.get_api_key()
  if not api_key then
    vim.api.nvim_err_writeln("Auctor: No API key set. Please set vim.g.auctor_api_key or OPENAI_API_KEY.")
    return
  end

  local buf = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local file_content = table.concat(lines, "\n")

  local filepath = vim.fn.expand("%:p")
  local filetype = vim.bo.filetype
  local relpath = (filepath == "") and "NEW_FILE" or vim.fn.fnamemodify(filepath, ":.")

  -- Construct the prompt as per the requested structure
  -- 1. Relative file path (or NEW_FILE)
  -- 2. Buffer filetype
  -- 3. Buffer contents
  local prompt = relpath .. "\n" .. filetype .. "\n" .. file_content

  local messages = {
    {role="user", content=prompt}
  }

  local resp, err = util.call_openai(messages, vim.g.auctor_model, vim.g.auctor_temperature)
  if err then
    vim.api.nvim_err_writeln("AuctorAdd error: " .. err)
    return
  end

  local cost = util.calculate_cost(resp.usage, vim.g.auctor_model)
  _G.auctor_session_total_cost = _G.auctor_session_total_cost + cost
  print(string.format("AuctorAdd: Spent $%.6f this transaction. Total: $%.6f this session.", cost, _G.auctor_session_total_cost))
end


-- AuctorSelect:
-- Prompts the user to choose a model and updates vim.g.auctor_model.
function M.auctor_select()
  local model = vim.fn.input("Enter model name (e.g. gpt-4, gpt-3.5-turbo, etc.): ")
  if model and model ~= "" then
    vim.g.auctor_model = model
    print("Auctor model set to: " .. model)
  else
    print("Model selection canceled or empty.")
  end
end

-- Toggle autorun of AuctorAdd for each new buffer opened
function M.auctor_auto_add_toggle()
  vim.g.auctor_auto_add = not vim.g.auctor_auto_add
  print("Auctor auto add is now " .. (vim.g.auctor_auto_add and "enabled" or "disabled"))
end

-- Function to be called by autocmd on BufReadPost or BufNewFile to auto run AuctorAdd if enabled
function M.auto_add_if_enabled()
  if vim.g.auctor_auto_add then
    M.auctor_add()
  end
end

return M

