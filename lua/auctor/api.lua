local util = require('auctor.util')
local config = require('auctor.config')

local M = {}

-- AuctorUpdate:
-- 1. If first call in session, prepend with prompt (vim.g.auctor_prompt)
-- 2. Send selected text to API
-- 3. Replace it with a code block in response
-- 4. Print transaction cost and total sum
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
    table.insert(messages, {role="system", content=vim.g.auctor_prompt})
    _G.auctor_session_first_update_called = true
  end

  table.insert(messages, {role="user", content=selection})

  local resp, err = util.call_openai(messages, vim.g.auctor_model, vim.g.auctor_temperature)
  if err then
    vim.api.nvim_err_writeln("AuctorUpdate error: " .. err)
    return
  end

  local content = resp.choices[1].message.content or ""
  -- Replace selection with a code block (assuming content is code or we just put triple backticks)
  content = "```\n" .. content .. "\n```"
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

  local filepath, filename, filetype, relpath = util.get_file_info()
  local prefix_prompt = vim.g.auctor_prefix_prompt_func(filepath, filename, filetype, relpath)

  local messages = {
    {role="system", content=prefix_prompt},
    {role="user", content=file_content}
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
