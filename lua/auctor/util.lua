local M = {}

-- Helper function to read API key
function M.get_api_key()
  if vim.g.auctor_api_key and vim.g.auctor_api_key ~= "" then
    return vim.g.auctor_api_key
  elseif os.getenv("OPENAI_API_KEY") then
    return os.getenv("OPENAI_API_KEY")
  else
    return nil
  end
end

function M.get_visual_selection()
  -- Get visually selected text
  local _, ls, cs = unpack(vim.fn.getpos("'<"))
  local _, le, ce = unpack(vim.fn.getpos("'>"))
  local lines = vim.fn.getline(ls, le)
  if #lines == 0 then
    return ""
  end
  lines[#lines] = string.sub(lines[#lines], 1, ce)
  lines[1] = string.sub(lines[1], cs)
  return table.concat(lines, "\n")
end

function M.replace_visual_selection(new_text)
  local _, ls, cs = unpack(vim.fn.getpos("'<"))
  local _, le, ce = unpack(vim.fn.getpos("'>"))

  local start_line = ls
  local start_col = cs
  local end_line = le
  local end_col = ce

  local buf = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(buf, start_line-1, end_line, false)
  if #lines == 0 then
    return
  end

  lines[#lines] = lines[#lines]:sub(1, end_col)
  lines[1] = lines[1]:sub(1, start_col-1) .. new_text .. lines[#lines]:sub(end_col+1)
  if #lines > 1 then
    for i = 2, #lines do
      lines[i] = nil
    end
  end

  -- It's simpler to just do a normal replacement:
  vim.api.nvim_buf_set_text(buf, start_line-1, start_col-1, end_line-1, end_col, {new_text})
end

-- Function to call OpenAI API. Returns the response table or nil, err
function M.call_openai(messages, model, temperature)
  local api_key = M.get_api_key()
  if not api_key then
    return nil, "No API key set. Please set vim.g.auctor_api_key or OPENAI_API_KEY."
  end

  local request_body = {
    model = model,
    messages = messages,
    temperature = temperature,
  }

  local json_str = vim.fn.json_encode(request_body)

  local cmd = {
    "curl", 
    "-s",
    "-X", "POST",
    "https://api.openai.com/v1/chat/completions",
    "-H", "Content-Type: application/json",
    "-H", "Authorization: Bearer " .. api_key,
    "-d", json_str
  }

  local result = vim.fn.system(cmd)
  if vim.v.shell_error ~= 0 then
    return nil, "Curl error: " .. result
  end

  local resp = vim.fn.json_decode(result)
  if resp.error then
    return nil, "OpenAI API error: " .. resp.error.message
  end

  return resp, nil
end

-- Calculate cost based on usage. Using GPT-3.5-turbo token prices:
-- prompt_tokens: $0.0015 / 1K tokens
-- completion_tokens: $0.002 / 1K tokens
function M.calculate_cost(usage, model)
  local prompt_tokens = usage.prompt_tokens or 0
  local completion_tokens = usage.completion_tokens or 0

  local cost = 0
  if model == "gpt-3.5-turbo" then
    cost = (prompt_tokens * 0.0015/1000) + (completion_tokens * 0.002/1000)
  else
    -- Default fallback if other models are used, adjust or add conditions as needed.
    cost = (prompt_tokens + completion_tokens) * 0.002/1000
  end

  return cost
end

-- Get file information for AuctorPrefixPrompt
function M.get_file_info()
  local filepath = vim.fn.expand("%:p")
  local filename = vim.fn.expand("%:t")
  local filetype = vim.bo.filetype
  local relpath = vim.fn.fnamemodify(filepath, ":.")
  return filepath, filename, filetype, relpath
end

return M
