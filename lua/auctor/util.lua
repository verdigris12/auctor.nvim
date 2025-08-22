-- FILE: lua/auctor/util.lua
-- Utility functions for Auctor. These helpers handle reading and
-- replacing visual selections, performing HTTP requests via curl,
-- computing token costs and displaying notifications. All mutable
-- session state is stored in the `auctor.state` module.

local state = require('auctor.state')
local providers = require('auctor.providers')

local M = {}

--------------------------------------------------------------------------------
-- Selection helpers
--------------------------------------------------------------------------------

--- Get the currently selected text in visual mode as a string.
-- This function is resilient to reversed selections (backwards visual
-- selection) and both character- and line-wise modes. For block
-- selections the behaviour falls back to a line-wise selection.
-- It also returns the start and end positions for later replacement.
-- @return string text: the selected text
-- @return table start_pos: {line0, col0}
-- @return table end_pos: {line0, col0}
function M.get_visual_selection()
  -- Getpos returns {bufnum, lnum, col, off}
  local _, ls, cs = unpack(vim.fn.getpos("'<"))
  local _, le, ce = unpack(vim.fn.getpos("'>"))

  -- Convert to zero-based indices
  local start_line = ls - 1
  local start_col = cs - 1
  local end_line = le - 1
  local end_col = ce - 1

  -- Normalise reversed selections
  if end_line < start_line or (end_line == start_line and end_col < start_col) then
    start_line, end_line = end_line, start_line
    start_col, end_col = end_col, start_col
  end

  local buf = vim.api.nvim_get_current_buf()
  -- Retrieve lines between start_line and end_line inclusive
  local lines = vim.api.nvim_buf_get_lines(buf, start_line, end_line + 1, false)
  if #lines == 0 then
    return '', {start_line, start_col}, {end_line, end_col}
  end
  -- Adjust the first and last lines based on columns
  lines[1] = string.sub(lines[1], start_col + 1)
  local last_line_len = #lines[#lines]
  -- Clamp end_col
  if end_col > last_line_len then
    end_col = last_line_len
  end
  lines[#lines] = string.sub(lines[#lines], 1, end_col)
  return table.concat(lines, '\n'), {start_line, start_col}, {end_line, end_col}
end

--- Replace the text in the given visual selection range with new text.
-- @param start_pos table {line0, col0}
-- @param end_pos table {line0, col0}
-- @param new_text string: replacement text
function M.replace_visual_selection(start_pos, end_pos, new_text)
  local buf = vim.api.nvim_get_current_buf()
  local start_line, start_col = start_pos[1], start_pos[2]
  local end_line, end_col = end_pos[1], end_pos[2]
  -- Normalise reversed positions
  if end_line < start_line or (end_line == start_line and end_col < start_col) then
    start_line, end_line = end_line, start_line
    start_col, end_col = end_col, start_col
  end
  -- Split new_text into lines
  local new_lines = {}
  for s in tostring(new_text):gmatch('([^\n]*)\n?') do
    table.insert(new_lines, s)
  end
  -- Replace text
  vim.api.nvim_buf_set_text(buf, start_line, start_col, end_line, end_col, new_lines)
end

--------------------------------------------------------------------------------
-- HTTP helpers
--------------------------------------------------------------------------------

--- Perform an asynchronous HTTP POST to the active provider's endpoint.
-- The job handle is stored in state.current_job so it can be cancelled.
-- IMPORTANT: the user callback is *scheduled* onto the main loop to
-- avoid E5560 (UI calls inside libuv callbacks).
-- @param messages table list of chat messages
-- @param callback function(resp, err) called on completion
function M.call_api_async(messages, callback)
  local provider = providers.get_active()
  if not provider then
    vim.schedule(function()
      callback(nil, 'No active provider')
    end)
    return
  end
  -- Build request body
  local body = {
    model = provider.model,
    messages = messages,
    temperature = provider.temperature,
  }
  local ok, json
  if vim.json and vim.json.encode then
    ok, json = pcall(vim.json.encode, body)
  end
  if not ok or not json then
    json = vim.fn.json_encode(body)
  end
  -- Build command
  local cmd = { 'curl', '-sS', '-X', 'POST', provider.base_url, '--max-time', '60' }
  -- Prepare headers
  local function add_header(k, v)
    table.insert(cmd, '-H'); table.insert(cmd, string.format('%s: %s', k, v))
  end
  add_header('Content-Type', 'application/json')
  if provider.api_key_env then
    local key = os.getenv(provider.api_key_env)
    if not key or key == '' then
      vim.schedule(function()
        callback(nil, string.format('Environment variable %s is not set', provider.api_key_env))
      end)
      return
    end
    add_header('Authorization', 'Bearer ' .. key)
  end
  if provider.headers then
    for k, v in pairs(provider.headers) do
      add_header(k, v)
    end
  end
  -- Payload
  table.insert(cmd, '-d'); table.insert(cmd, json)

  local handle
  handle = vim.system(cmd, { text = true }, function(obj)
    -- Ensure callback runs on the main thread
    local function done(resp, err)
      vim.schedule(function()
        -- Clear tracked handle when delivering result
        if state.current_job == handle then
          state.current_job = nil
        end
        callback(resp, err)
      end)
    end

    if obj.code ~= 0 then
      return done(nil, 'HTTP request failed: ' .. tostring(obj.stderr or ''))
    end

    local raw = obj.stdout or ''
    local ok2, decoded = pcall(function()
      if vim.json and vim.json.decode then
        return vim.json.decode(raw)
      else
        return vim.fn.json_decode(raw)
      end
    end)
    if not ok2 then
      return done(nil, 'Failed to decode JSON: ' .. tostring(decoded))
    end
    if decoded and decoded.error then
      local err = decoded.error.message or 'Unknown API error'
      return done(nil, err)
    end
    return done(decoded, nil)
  end)

  if handle then
    state.current_job = handle
  else
    vim.schedule(function()
      callback(nil, 'Failed to start curl process')
    end)
  end
end

--- Cancel the currently running HTTP job if one is in progress.
function M.cancel_current_job()
  local job = state.current_job
  if job and type(job) == 'userdata' and job.is_closing == nil then
    pcall(job.kill, job, 15) -- SIGTERM
    state.current_job = nil
  end
end

--------------------------------------------------------------------------------
-- Misc helpers
--------------------------------------------------------------------------------

--- Compute the estimated cost of an API call based on token usage.
-- Costs are derived from OpenAI GPT-4o pricing as a baseline.
function M.calculate_cost(usage)
  local prompt_tokens = (usage and usage.prompt_tokens) or 0
  local completion_tokens = (usage and usage.completion_tokens) or 0
  return (prompt_tokens * 0.0025 / 1000) + (completion_tokens * 0.01 / 1000)
end

--- Compute a unified diff between two strings. Returns nil if the
-- built-in vim.diff is unavailable (prior to Neovim 0.10).
function M.diff_unified(orig, new)
  if not vim.diff then
    return nil
  end
  return vim.diff(orig, new, { result_type = 'unified', ctxlen = 3 })
end

--- Display a notification. Uses vim.notify if available, otherwise
-- falls back to print(). Accepts the same interface as vim.notify.
function M.notify(msg, level, opts)
  level = level or 'info'
  if vim.notify then
    local o = opts or {}
    if not o.title then o.title = 'Auctor' end
    vim.notify(msg, level, o)
  else
    print(msg)
  end
end

return M
