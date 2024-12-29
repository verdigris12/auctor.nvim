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
  local buf = vim.api.nvim_get_current_buf()

  local _, ls, cs = unpack(vim.fn.getpos("'<"))
  local _, le, ce = unpack(vim.fn.getpos("'>"))

  -- Convert to zero-based indices
  local start_line = ls - 1
  local start_col = cs - 1
  local end_line = le - 1
  local end_col = ce - 1

  -- Normalize line/col ranges
  if end_line < start_line then
    start_line, end_line = end_line, start_line
  end
  if end_line == start_line and end_col < start_col then
    start_col, end_col = end_col, start_col
  end

  -- Get lines from buffer to validate column indices
  local lines = vim.api.nvim_buf_get_lines(buf, start_line, end_line + 1, false)
  if #lines == 0 then
    -- No lines selected, just return
    return
  end

  -- Clamp end_col if it exceeds the line length
  local last_line_len = #lines[#lines]
  if end_col > last_line_len then
    end_col = last_line_len
  end

  -- Convert new_text into a list of lines
  local new_lines = {}
  for line in string.gmatch(new_text, "([^\n]*)\n?") do
    table.insert(new_lines, line)
  end

  vim.api.nvim_buf_set_text(buf, start_line, start_col, end_line, end_col, new_lines)
end

-- New: Asynchronous call to OpenAI
-- callback(resp, err) where resp is the decoded JSON or nil
function M.call_openai_async(messages, model, temperature, callback)
  local api_key = M.get_api_key()
  if not api_key then
    callback(nil, "No API key set. Please set vim.g.auctor_api_key or OPENAI_API_KEY.")
    return
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

  local stdout_data = {}
  local stderr_data = {}

  local job_id = vim.fn.jobstart(cmd, {
    stdout_buffered = true,
    on_stdout = function(_, data, _)
      if data and #data > 0 then
        table.insert(stdout_data, table.concat(data, "\n"))
      end
    end,
    on_stderr = function(_, data, _)
      if data and #data > 0 then
        table.insert(stderr_data, table.concat(data, "\n"))
      end
    end,
    on_exit = function(_, exit_code, _)
      if exit_code ~= 0 then
        callback(nil, "Curl error: " .. table.concat(stderr_data, "\n"))
      else
        local raw_output = table.concat(stdout_data, "\n")
        local ok, resp = pcall(vim.fn.json_decode, raw_output)
        if not ok then
          callback(nil, "JSON decode error: " .. resp)
          return
        end
        if resp.error then
          callback(nil, "OpenAI API error: " .. resp.error.message)
          return
        end
        callback(resp, nil)
      end
    end,
  })

  if job_id <= 0 then
    callback(nil, "Failed to start job. cmd: " .. table.concat(cmd, " "))
  end
end

-- Calculate cost based on usage. Using GPT-4o:
-- prompt_tokens: $0.0025 / 1K tokens
-- completion_tokens: $0.01 / 1K tokens
function M.calculate_cost(usage, model)
  local prompt_tokens = usage.prompt_tokens or 0
  local completion_tokens = usage.completion_tokens or 0

  local cost = 0
  if model == "gpt-4o" then
    cost = (prompt_tokens * 0.0025/1000) + (completion_tokens * 0.01/1000)
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

