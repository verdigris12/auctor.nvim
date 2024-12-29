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

--- Start spinner using nvim-notify. The "body_msg" is the main message,
--- while each frame of the spinner goes in the "title".
local function start_notify_spinner(body_msg)
  if notify_timer then
    notify_timer:stop()
    notify_timer:close()
    notify_timer = nil
  end
  notify_spinner_index = 1
  notify_spinner_notif_id = nil

  -- Repeatedly update the title with the next spinner frame
  notify_timer = vim.loop.new_timer()
  notify_timer:start(0, 100, function()
    local frame = spinner_frames[notify_spinner_index]
    notify_spinner_index = (notify_spinner_index % #spinner_frames) + 1

    vim.schedule(function()
      local opts = {}
      if notify_spinner_notif_id then
        opts.replace = notify_spinner_notif_id
      else
        opts.timeout = false
      end

      -- The spinner is shown in the title
      opts.title = frame .. " Auctor"

      local new_notif = notify(
        body_msg,   -- The body of the notification
        "info",
        opts
      )
      notify_spinner_notif_id = new_notif.id
    end)
  end)
end

--- Stop spinner and replace it with a final title and body (message).
--- final_title -> goes in opts.title
--- final_message -> is the body
local function stop_notify_spinner(final_title, final_message)
  if notify_timer then
    notify_timer:stop()
    notify_timer:close()
    notify_timer = nil
  end

  if notify_spinner_notif_id then
    vim.schedule(function()
      notify(
        final_message,  -- body
        "info",
        {
          title = final_title,
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

--- Begin spinner or fallback in cmdline.
--- @param msg string The body message for the notification or fallback print
--- @param fallback_msg string The message to print if notify isn't available
local function start_spinner_or_notify(msg, fallback_msg)
  if has_notify then
    start_notify_spinner(msg)
  else
    print(fallback_msg)
    start_cmdline_spinner()
  end
end

--- End spinner or fallback, showing a final title and body.
--- @param final_title string Title for the final notification
--- @param final_message string Body for the final notification (or print)
local function stop_spinner_or_notify(final_title, final_message)
  if has_notify then
    stop_notify_spinner(final_title, final_message)
  else
    stop_cmdline_spinner()
    vim.schedule(function()
      print(final_message)
    end)
  end
end

--------------------------------------------------------------------------------
-- Main module
--------------------------------------------------------------------------------
local M = {}

--------------------------------------------------------------------------------
-- Auctor Update
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

  -- Start spinner or fallback (the "body" of the notification, if available)
  start_spinner_or_notify("Updating selection...", "Auctor: Updating selection...")

  util.call_openai_async(messages, vim.g.auctor_model, vim.g.auctor_temperature, function(resp, err)
    if err then
      stop_spinner_or_notify("Auctor Error", "Update failed")
      vim.api.nvim_err_writeln("AuctorUpdate error: " .. err)
      return
    end

    local content = resp.choices[1].message.content or ""

    ---------------------------------------------------------------------------
    -- Remove lines containing triple backticks
    ---------------------------------------------------------------------------
    do
      local lines = {}
      for line in content:gmatch("([^\n]*)\n?") do
        table.insert(lines, line)
      end

      local new_lines = {}
      for _, line in ipairs(lines) do
        if not line:find("```", 1, true) then
          table.insert(new_lines, line)
        end
      end

      content = table.concat(new_lines, "\n")
    end

    util.replace_visual_selection(content)

    local cost = util.calculate_cost(resp.usage, vim.g.auctor_model)
    _G.auctor_session_total_cost = _G.auctor_session_total_cost + cost

    local result_message = string.format(
      "Selection updated. This transaction: $%.6f. This session: $%.6f",
      cost,
      _G.auctor_session_total_cost
    )

    stop_spinner_or_notify("Auctor", result_message)
  end)
end

--------------------------------------------------------------------------------
-- Auctor Add
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

  start_spinner_or_notify(
    "Uploading " .. filename .. "...",
    "Auctor: Uploading " .. filename .. "..."
  )

  util.call_openai_async(messages, vim.g.auctor_model, vim.g.auctor_temperature, function(resp, err)
    if err then
      stop_spinner_or_notify("Auctor Error", "Upload failed")
      vim.api.nvim_err_writeln("AuctorAdd error: " .. err)
      return
    end

    local cost = util.calculate_cost(resp.usage, vim.g.auctor_model)
    _G.auctor_session_total_cost = _G.auctor_session_total_cost + cost

    local result_message = string.format(
      "File uploaded. This transaction: $%.6f. This session: $%.6f",
      cost,
      _G.auctor_session_total_cost
    )

    stop_spinner_or_notify("Auctor", result_message)
  end)
end

--------------------------------------------------------------------------------
-- Auctor Insert
--------------------------------------------------------------------------------
function M.auctor_insert()
  -- We'll try to load nvim-comment
  local has_nvim_comment, nvim_comment = pcall(require, 'nvim_comment')

  -- We'll use this marker text if user sets it
  local marker_text = vim.g.auctor_instruction_marker or "Auctor Instruction"

  -- Get the current buffer and cursor position
  local buf = vim.api.nvim_get_current_buf()
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))

  if has_nvim_comment then
    ---------------------------------------------------------------------------
    -- If nvim-comment is installed, we:
    --   1. Insert a new, blank line below the current line
    --   2. Move the cursor to that line
    --   3. Toggle a line comment there
    --   4. Append our marker text
    --   5. Place the cursor in insert mode
    ---------------------------------------------------------------------------
    vim.api.nvim_buf_set_lines(buf, row, row, false, { "" })
    vim.api.nvim_win_set_cursor(0, { row + 1, 0 })

    nvim_comment.comment_toggle_linewise_op()

    local commented_line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1]
    commented_line = commented_line .. " " .. marker_text .. " "
    vim.api.nvim_buf_set_lines(buf, row, row + 1, false, { commented_line })

    vim.api.nvim_win_set_cursor(0, { row + 1, #commented_line })
    vim.cmd("startinsert")

  else
    ---------------------------------------------------------------------------
    -- Fallback if nvim-comment is NOT installed
    --   1. Build the comment from vim.bo.commentstring if available, else "// %s"
    --   2. Insert a new line below the current line
    --   3. Place the cursor in insert mode after the marker
    ---------------------------------------------------------------------------
    local cstring = vim.bo.commentstring
    if not cstring or cstring == "" then
      cstring = "// %s"
    end

    if cstring:find("%%s") then
      cstring = cstring:gsub("%%s", marker_text .. " ")
    else
      cstring = cstring .. " " .. marker_text .. " "
    end

    vim.api.nvim_buf_set_lines(buf, row, row, false, { cstring })
    vim.api.nvim_win_set_cursor(0, { row + 1, #cstring })
    vim.cmd("startinsert")
  end
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
