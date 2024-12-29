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
-- nvim-notify-based spinner
--------------------------------------------------------------------------------
-- We repeatedly call notify(..., { replace = ... }) to update the same notification.
--------------------------------------------------------------------------------
local notify_timer = nil
local notify_spinner_index = 1
local notify_spinner_notif_id = nil

--- Start a spinner notification that updates every 100ms.
--- @param title_msg string  The text shown in the "title" field of the notification
local function start_notify_spinner(title_msg)
  -- If there's already a timer, close it first
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
        -- Update the existing notification
        opts.replace = notify_spinner_notif_id
      else
        -- First time creating the notification
        opts.title = title_msg
        opts.timeout = false
      end

      local new_notif = notify(
        -- Notification message: we embed the spinner in the "main text"
        frame .. " Auctor",
        -- Notification level
        "info",
        opts
      )
      notify_spinner_notif_id = new_notif.id
    end)
  end)
end

--- Stop the spinner and replace it with a final message
--- @param final_title string  Notification text
--- @param final_msg string    Notification title (the "header")
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
          timeout = 3000 -- show final message for 3s
        }
      )
      notify_spinner_notif_id = nil
    end)
  end
end

--------------------------------------------------------------------------------
-- Helper: start spinner or notify
--------------------------------------------------------------------------------
local function start_spinner_or_notify(title_msg, fallback_msg)
  if has_notify then
    start_notify_spinner(title_msg)
  else
    print(fallback_msg) -- immediate fallback print
    start_cmdline_spinner()
  end
end

local function stop_spinner_or_notify(success_title, success_msg)
  if has_notify then
    stop_notify_spinner(success_title, success_msg)
  else
    stop_cmdline_spinner()
    print(success_msg)
  end
end

--------------------------------------------------------------------------------
-- Main Module
--------------------------------------------------------------------------------
local M = {}

-- Auctor Update
-- 1. Asynchronously call the API
-- 2. If nvim-notify is available, use notification spinner; otherwise fallback
-- 3. Prepend vim.g.auctor_update_prompt if set
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

  -- Prepend custom prompt if available
  if vim.g.auctor_update_prompt and vim.g.auctor_update_prompt ~= "" then
    selection = vim.g.auctor_update_prompt .. "\n" .. selection
  end

  local messages = {}
  if not _G.auctor_session_first_update_called then
    table.insert(messages, {role="system", content=vim.g.auctor_prompt_func()})
    _G.auctor_session_first_update_called = true
  end

  table.insert(messages, {role="user", content=selection})

  -- Start spinner (or notify)
  start_spinner_or_notify("Updating selection...", "Auctor: Updating selection...")

  util.call_openai_async(messages, vim.g.auctor_model, vim.g.auctor_temperature, function(resp, err)
    -- Stop spinner/notify
    if err then
      stop_spinner_or_notify("Auctor Error", "Update failed")
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

    -- Show final success
    stop_spinner_or_notify("Auctor", "Selection updated")

    print(string.format("Auctor: Spent $%.6f this transaction. Total: $%.6f this session.",
      cost, _G.auctor_session_total_cost))
  end)
end

-- AuctorAdd:
-- 1. Uploads the current buffer with a prefix prompt
-- 2. Prints cost and accumulates total
-- 3. Prepend vim.g.auctor_add_prompt if set
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
  local relpath = (filepath == "") and "NEW_FILE" or vim.fn.fnamemodify(filepath, ":.")

  -- Construct the prompt
  local prompt = ""
  if vim.g.auctor_add_prompt and vim.g.auctor_add_prompt ~= "" then
    prompt = vim.g.auctor_add_prompt .. "\n"
  end
  prompt = prompt .. relpath .. "\n" .. filetype .. "\n" .. file_content

  local messages = {
    {role="user", content=prompt}
  }

  -- Start spinner/notify
  start_spinner_or_notify("Uploading " .. filename .. "...", "Auctor: Uploading " .. filename .. "...")

  util.call_openai_async(messages, vim.g.auctor_model, vim.g.auctor_temperature, function(resp, err)
    -- Stop spinner/notify
    if err then
      stop_spinner_or_notify("Auctor Error", "Upload failed")
      vim.api.nvim_err_writeln("AuctorAdd error: " .. err)
      return
    end

    local cost = util.calculate_cost(resp.usage, vim.g.auctor_model)
    _G.auctor_session_total_cost = _G.auctor_session_total_cost + cost

    -- Show final success
    stop_spinner_or_notify("Auctor", "File uploaded")

    print(string.format("AuctorAdd: Spent $%.6f this transaction. Total: $%.6f this session.",
      cost, _G.auctor_session_total_cost))
  end)
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

