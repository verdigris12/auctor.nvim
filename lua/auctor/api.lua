local util = require('auctor.util')
local config = require('auctor.config')

--------------------------------------------------------------------------------
-- Attempt to load nvim-notify
--------------------------------------------------------------------------------
local has_notify, notify = pcall(require, 'notify')

--------------------------------------------------------------------------------
-- Braille spinner frames
--------------------------------------------------------------------------------
local spinner_frames = {'⣷','⣯','⣟','⡿','⢿','⣻','⣽','⣾'}

--------------------------------------------------------------------------------
-- Fallback: command-line spinner
--------------------------------------------------------------------------------
local spinner_index = 1
local spinner_timer = nil

local function fallback_cmdline_spinner()
  vim.schedule(function()
    vim.api.nvim_echo({{spinner_frames[spinner_index], 'Normal'}}, false, {})
    spinner_index = (spinner_index % #spinner_frames) + 1
  end)
end

local function start_cmdline_spinner()
  if spinner_timer then
    spinner_timer:stop()
    spinner_timer:close()
    spinner_timer = nil
  end
  spinner_index = 1
  spinner_timer = vim.loop.new_timer()
  spinner_timer:start(0, 100, vim.schedule_wrap(fallback_cmdline_spinner))
end

local function stop_cmdline_spinner()
  if spinner_timer then
    spinner_timer:stop()
    spinner_timer:close()
    spinner_timer = nil
  end
  vim.schedule(function()
    vim.api.nvim_echo({{'', 'Normal'}}, false, {})
  end)
end

--------------------------------------------------------------------------------
-- nvim-notify-based spinner (if available)
--------------------------------------------------------------------------------
local notify_timer = nil
local notify_spinner_index = 1
local notify_spinner_notif_id = nil

local function start_notify_spinner(title_msg)
  if notify_timer then
    notify_timer:stop()
    notify_timer:close()
    notify_timer = nil
  end
  notify_spinner_index = 1
  notify_spinner_notif_id = nil

  notify_timer = vim.loop.new_timer()
  notify_timer:start(0, 100, function()
    local frame = spinner_frames[notify_spinner_index]
    notify_spinner_index = (notify_spinner_index % #spinner_frames) + 1

    vim.schedule(function()
      local opts = {}
      if notify_spinner_notif_id then
        opts.replace = notify_spinner_notif_id
      else
        opts.title = title_msg
        opts.timeout = false
      end

      local new_notif = notify(
        frame .. " Auctor",
        "info",
        opts
      )
      notify_spinner_notif_id = new_notif.id
    end)
  end)
end

local function stop_notify_spinner(final_title, final_msg)
  if notify_timer then
    notify_timer:stop()
    notify_timer:close()
    notify_timer = nil
  end

  if notify_spinner_notif_id then
    vim.schedule(function()
      notify(
        final_title,
        "info",
        {
          title = final_msg,
          replace = notify_spinner_notif_id,
          timeout = 3000
        }
      )
      notify_spinner_notif_id = nil
    end)
  end
end

--------------------------------------------------------------------------------
-- Spinner or notify helper
--------------------------------------------------------------------------------
local function start_spinner_or_notify(title_msg, fallback_msg)
  if has_notify then
    start_notify_spinner(title_msg)
  else
    -- Fallback spinner in cmdline
    print(fallback_msg)
    start_cmdline_spinner()
  end
end

-- Use vim.schedule for the final print so it doesn't get overwritten.
local function stop_spinner_or_notify(success_title, success_msg)
  if has_notify then
    stop_notify_spinner(success_title, success_msg)
  else
    -- Stop the spinner first
    stop_cmdline_spinner()

    -- Schedule the final print so it appears after the spinner is cleared
    vim.schedule(function()
      print(success_msg)
    end)
  end
end

--------------------------------------------------------------------------------
-- Main module
--------------------------------------------------------------------------------
local M = {}

--------------------------------------------------------------------------------
-- Auctor Update
-- Prepend if available: vim.g.auctor_update_prompt
-- Then: FILEPATH: ...
-- Then wrap selected text in a code block
--------------------------------------------------------------------------------
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

  local filetype = vim.bo.filetype
  local filename = vim.fn.expand("%:t")
  local filepath = vim.fn.expand("%:p")

  -- Build the user-content prompt
  local user_content = ""
  if vim.g.auctor_update_prompt and vim.g.auctor_update_prompt ~= "" then
    user_content = user_content .. vim.g.auctor_update_prompt .. "\n"
  end
  user_content = user_content
      .. "FILEPATH: " .. filepath .. "\n\n"
      .. "```" .. filetype .. "\n"
      .. selection
      .. "\n```\n"

  local messages = {}
  if not _G.auctor_session_first_update_called then
    table.insert(messages, {role="system", content=vim.g.auctor_prompt_func()})
    _G.auctor_session_first_update_called = true
  end

  table.insert(messages, {role="user", content=user_content})

  -- Start spinner/notify
  start_spinner_or_notify("Updating selection...", "Auctor: Updating selection...")

  util.call_openai_async(messages, vim.g.auctor_model, vim.g.auctor_temperature, function(resp, err)
    if err then
      stop_spinner_or_notify("Auctor Error", "Update failed")
      vim.api.nvim_err_writeln("AuctorUpdate error: " .. err)
      return
    end

    local content = resp.choices[1].message.content or ""


    ---------------------------------------------------------------------------
    -- Remove lines containing triple backticks, rather than partial substring
    ---------------------------------------------------------------------------
    do
      local lines = {}
      for line in content:gmatch("([^\n]*)\n?") do
        table.insert(lines, line)
      end

      local new_lines = {}
      for _, line in ipairs(lines) do
        -- Only keep lines that do NOT contain ```
        if not line:find("```", 1, true) then
          table.insert(new_lines, line)
        end
      end

      content = table.concat(new_lines, "\n")
    end

    util.replace_visual_selection(content)

    local cost = util.calculate_cost(resp.usage, vim.g.auctor_model)
    _G.auctor_session_total_cost = _G.auctor_session_total_cost + cost
    result_message = string.format("Selection updated. This transaction: $%.6f. This session: $%.6f", cost, _G.auctor_session_total_cost)

    -- Stop spinner/notify
    stop_spinner_or_notify("Auctor", result_message)
  end)
end

--------------------------------------------------------------------------------
-- Auctor Add
-- Prepend vim.g.auctor_update_prompt (if available)
-- Then: FILEPATH: ...
-- Wrap file content in a code block
--------------------------------------------------------------------------------
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
  local filename = vim.fn.expand("%:t")

  local user_content = ""
  if vim.g.auctor_update_prompt and vim.g.auctor_update_prompt ~= "" then
    user_content = user_content .. vim.g.auctor_update_prompt .. "\n"
  end
  user_content = user_content
      .. "FILEPATH: " .. filepath .. "\n\n"
      .. "```" .. filetype .. "\n"
      .. file_content
      .. "\n```\n"

  local messages = {
    {role="user", content=user_content}
  }

  -- Start spinner/notify
  start_spinner_or_notify("Uploading " .. filename .. "...", "Auctor: Uploading " .. filename .. "...")

  util.call_openai_async(messages, vim.g.auctor_model, vim.g.auctor_temperature, function(resp, err)
    if err then
      stop_spinner_or_notify("Auctor Error", "Upload failed")
      vim.api.nvim_err_writeln("AuctorAdd error: " .. err)
      return
    end

    local cost = util.calculate_cost(resp.usage, vim.g.auctor_model)
    _G.auctor_session_total_cost = _G.auctor_session_total_cost + cost
    result_message = string.format("File uploaded. This transaction: $%.6f. This session: $%.6f", cost, _G.auctor_session_total_cost)

    -- Stop spinner/notify
    stop_spinner_or_notify("Auctor", result_message)
  end)
end

--------------------------------------------------------------------------------
-- Auctor Insert
-- 1. Creates a new line with the instruction marker (or a default) as comment
-- 2. Moves cursor to that line, puts user into insert mode after the marker
--------------------------------------------------------------------------------
function M.auctor_insert()
  -- Use a global marker if defined, else a default string:
  local marker = vim.g.auctor_instruction_marker or "Auctor Instruction"

  -- If commentstring is nil or empty, default to "// %s"
  local cstring = vim.bo.commentstring
  if not cstring or cstring == "" then
    cstring = "// %s"
  end

  -- If the commentstring contains '%s', substitute our marker there
  if cstring:find("%%s") then
    -- Add a trailing space so user can start typing right away
    cstring = cstring:gsub("%%s", marker .. " ")
  else
    -- Otherwise, just append our marker text to the end
    cstring = cstring .. " " .. marker .. " "
  end

  -- Get current cursor location (1-based row, 0-based col)
  local row, _ = unpack(vim.api.nvim_win_get_cursor(0))
  -- Insert a line at the current row. (Because of how set_lines works,
  -- inserting at `row, row` means we place a new line *below* the current one.)
  vim.api.nvim_buf_set_lines(0, row, row, false, { cstring })

  -- Move the cursor to the newly inserted line. Remember that nvim_win_set_cursor
  -- uses 1-based line indexing, so the new line is at row+1.
  -- The column is #cstring, so the user ends up right after the inserted text.
  vim.api.nvim_win_set_cursor(0, { row + 1, #cstring })

  -- Finally, switch to insert mode
  vim.cmd("startinsert")
end


--------------------------------------------------------------------------------
-- Auctor Select
--------------------------------------------------------------------------------
function M.auctor_select()
  local model = vim.fn.input("Enter model name (e.g. gpt-4, gpt-3.5-turbo, etc.): ")
  if model and model ~= "" then
    vim.g.auctor_model = model
    print("Auctor model set to: " .. model)
  else
    print("Model selection canceled or empty.")
  end
end

--------------------------------------------------------------------------------
-- Auctor AutoAdd Toggle
--------------------------------------------------------------------------------
function M.auctor_auto_add_toggle()
  vim.g.auctor_auto_add = not vim.g.auctor_auto_add
  print("Auctor auto add is now " .. (vim.g.auctor_auto_add and "enabled" or "disabled"))
end

-- Auto-add on BufReadPost or BufNewFile, if enabled
function M.auto_add_if_enabled()
  if vim.g.auctor_auto_add then
    M.auctor_add()
  end
end

return M

