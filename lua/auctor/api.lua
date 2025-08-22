-- High-level commands implementing the Auctor user interface. These
-- functions coordinate selection handling, prompt construction,
-- asynchronous API calls, diff preview and result application.

local state = require('auctor.state')
local providers = require('auctor.providers')
local util = require('auctor.util')
local config = require('auctor.config')

--------------------------------------------------------------------------------
-- Spinner helpers
--------------------------------------------------------------------------------

-- We reuse the braille spinner frames from the original implementation.
local spinner_frames = {'⣷','⣯','⣟','⡿','⢿','⣻','⣽','⣾'}
local has_notify, notify_lib = pcall(require, 'notify')

-- Internal spinner state
local spinner = {
  timer = nil,
  frame = 1,
  notif_id = nil,
}

-- Start a spinner. When nvim-notify is available the spinner is shown
-- in the title of a persistent notification. Otherwise the spinner is
-- echoed on the command line. Returns immediately.
local function start_spinner(title_msg, fallback_msg)
  -- Cancel any existing spinner
  if spinner.timer then
    spinner.timer:stop()
    spinner.timer:close()
    spinner.timer = nil
  end
  spinner.frame = 1
  spinner.notif_id = nil
  if has_notify then
    spinner.timer = vim.loop.new_timer()
    spinner.timer:start(0, 100, vim.schedule_wrap(function()
      local frame_char = spinner_frames[spinner.frame]
      spinner.frame = (spinner.frame % #spinner_frames) + 1
      local opts = {}
      if spinner.notif_id then
        opts.replace = spinner.notif_id
      else
        opts.timeout = false
      end
      opts.title = frame_char .. ' Auctor'
      local n = notify_lib(title_msg, 'info', opts)
      spinner.notif_id = n.id
    end))
  else
    -- Fallback: print message once and update spinner on status line
    local msg = fallback_msg:gsub('[\r\n]+', ' ')
    print(msg)
    spinner.timer = vim.loop.new_timer()
    spinner.timer:start(0, 100, vim.schedule_wrap(function()
      local frame_char = spinner_frames[spinner.frame]
      spinner.frame = (spinner.frame % #spinner_frames) + 1
      vim.api.nvim_echo({{frame_char .. ' Auctor', 'Normal'}}, false, {})
    end))
  end
end

-- Stop the spinner. If using nvim-notify, replace the spinner with a
-- final message. Otherwise clear the command line and print the message.
local function stop_spinner(final_title, final_msg)
  if spinner.timer then
    spinner.timer:stop()
    spinner.timer:close()
    spinner.timer = nil
  end
  if has_notify and spinner.notif_id then
    vim.schedule(function()
      notify_lib(final_msg, 'info', { title = final_title, replace = spinner.notif_id, timeout = 3000 })
      spinner.notif_id = nil
    end)
  else
    vim.schedule(function()
      -- Clear spinner echo
      vim.api.nvim_echo({{'', 'Normal'}}, false, {})
      local single = final_msg:gsub('[\r\n]+', ' ')
      print(single)
    end)
  end
end

--------------------------------------------------------------------------------
-- Diff preview helper
--------------------------------------------------------------------------------

--- Display a unified diff in a floating window and ask the user
-- whether to apply it. The callback receives true to apply or false
-- to discard. The diff string should include newlines.
local function present_diff(diff_text, on_done)
  -- If diff is nil or empty, skip preview and apply immediately
  if not diff_text or diff_text == '' then
    on_done(true)
    return
  end
  -- Create a scratch buffer
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].modifiable = false
  vim.bo[buf].filetype = 'diff'
  -- Split diff into lines and set them
  local lines = {}
  for s in diff_text:gmatch('[^\n]*\n?') do
    if s:sub(-1) == '\n' then
      table.insert(lines, s:sub(1, -2))
    elseif s ~= '' then
      table.insert(lines, s)
    end
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  -- Calculate size; ensure at least 20x60 and at most 80% of screen
  local ui = vim.api.nvim_list_uis()[1]
  local total_cols = ui.width
  local total_rows = ui.height
  local width = math.min(math.max(total_cols - 10, 60), total_cols * 0.8)
  local height = math.min(math.max(#lines + 4, 10), total_rows * 0.8)
  local row = math.floor((total_rows - height) / 2 - 1)
  local col = math.floor((total_cols - width) / 2)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    style = 'minimal',
    row = row,
    col = col,
    width = math.floor(width),
    height = math.floor(height),
    border = 'single',
  })
  -- Add instructions
  vim.api.nvim_buf_set_option(buf, 'modifiable', true)
  vim.api.nvim_buf_set_lines(buf, 0, 0, false, {
    'Diff Preview – press y/Enter to apply, n/q/Esc to cancel',
    ''
  })
  vim.api.nvim_buf_set_option(buf, 'modifiable', false)
  -- Define finish function
  local function finish(apply)
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
    if on_done then on_done(apply) end
  end
  -- Keymaps
  local opts = { nowait = true, noremap = true, silent = true, buffer = buf }
  vim.keymap.set('n', 'q', function() finish(false) end, opts)
  vim.keymap.set('n', 'n', function() finish(false) end, opts)
  vim.keymap.set('n', '<Esc>', function() finish(false) end, opts)
  vim.keymap.set('n', 'y', function() finish(true) end, opts)
  vim.keymap.set('n', '<CR>', function() finish(true) end, opts)
end

--------------------------------------------------------------------------------
-- Core API functions
--------------------------------------------------------------------------------

local M = {}

--- Update the selected region using the active provider. Shows a diff
-- preview before applying the result. Accumulates cost in the session
-- state and notifies the user of the cost.
function M.auctor_update()
  -- Retrieve selection
  local text, start_pos, end_pos = util.get_visual_selection()
  if text == '' then
    util.notify('AuctorUpdate: No text selected.', 'error')
    return
  end
  -- Build user content: include filepath and filetype for context
  local filepath = vim.fn.expand('%:p')
  local filetype = vim.bo.filetype or ''
  local user_content = ''
  local provider = providers.get_active()
  -- Append provider-specific update prompt after the system prompt later
  user_content = user_content .. 'FILEPATH: ' .. filepath .. '\n\n'
  user_content = user_content .. '```' .. filetype .. '\n' .. text .. '\n```\n'
  -- Build messages
  local messages = {}
  -- On first update send system prompt
  if not state.session_first_update_called then
    -- Determine instruction marker
    local marker = state.opts.instruction_marker or config.default_instruction_marker
    local system_prompt = state.opts.system_update_prompt or config.build_update_prompt(marker)
    -- Append provider-specific update prompt
    if provider.update_prompt and provider.update_prompt ~= '' then
      system_prompt = system_prompt .. '\n' .. provider.update_prompt
    end
    table.insert(messages, { role = 'system', content = system_prompt })
    state.session_first_update_called = true
  end
  table.insert(messages, { role = 'user', content = user_content })
  -- Start spinner
  start_spinner('Updating selection...', 'Auctor: Updating selection...')
  -- Perform request
  util.call_api_async(messages, function(resp, err)
    stop_spinner('Auctor', err and 'Update failed' or 'Update completed')
    if err then
      util.notify('AuctorUpdate error: ' .. err, 'error')
      return
    end
    local choice = resp.choices and resp.choices[1]
    if not choice or not choice.message then
      util.notify('AuctorUpdate error: invalid response', 'error')
      return
    end
    local content = choice.message.content or ''
    -- Unwrap a single fenced code block if present
    local inner = content:match('^%s*```[%w_]*%s*[\r\n](.*)[\r\n]```%s*$')
    if inner then
      content = inner
    end
    -- Compute diff
    local diff = util.diff_unified(text, content)
    local usage = resp.usage or {}
    local cost = util.calculate_cost(usage)
    -- Present diff
    present_diff(diff, function(apply)
      if apply then
        util.replace_visual_selection(start_pos, end_pos, content)
        state.session_total_cost = state.session_total_cost + cost
        util.notify(string.format('Selection updated.\nThis transaction: $%.6f\nThis session: $%.6f', cost, state.session_total_cost), 'info')
      else
        util.notify('Update canceled.', 'warn')
      end
    end)
  end)
end

--- Upload the entire current buffer to the active provider. This
-- function sends an "add" request (system prompt + provider add prompt)
-- to prime the model with the file contents. No diff preview is used.
function M.auctor_add()
  local buf = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local file_content = table.concat(lines, '\n')
  local filepath = vim.fn.expand('%:p')
  local filetype = vim.bo.filetype or ''
  local provider = providers.get_active()
  -- Build user message
  local user_content = ''
  user_content = user_content .. 'FILEPATH: ' .. filepath .. '\n\n'
  user_content = user_content .. '```' .. filetype .. '\n' .. file_content .. '\n```\n'
  -- Build messages
  local messages = {}
  -- Always send the system add prompt on add operations
  local system_prompt = state.opts.system_add_prompt or config.default_system_add_prompt
  if provider.add_prompt and provider.add_prompt ~= '' then
    system_prompt = system_prompt .. '\n' .. provider.add_prompt
  end
  table.insert(messages, { role = 'system', content = system_prompt })
  table.insert(messages, { role = 'user', content = user_content })
  -- Show spinner
  local filename = vim.fn.expand('%:t')
  start_spinner('Uploading ' .. filename .. '...', 'Auctor: Uploading ' .. filename .. '...')
  util.call_api_async(messages, function(resp, err)
    stop_spinner('Auctor', err and 'Upload failed' or 'Upload completed')
    if err then
      util.notify('AuctorAdd error: ' .. err, 'error')
      return
    end
    local usage = resp.usage or {}
    local cost = util.calculate_cost(usage)
    state.session_total_cost = state.session_total_cost + cost
    util.notify(string.format('File uploaded.\nThis transaction: $%.6f\nThis session: $%.6f', cost, state.session_total_cost), 'info')
  end)
end

--- Insert an instruction marker comment below the current line. If
-- nvim-comment is installed it is used to respect comment formatting;
-- otherwise vim.bo.commentstring is consulted. Places the cursor in
-- insert mode ready to type the instruction.
function M.auctor_insert()
  local marker_text = state.opts.instruction_marker or config.default_instruction_marker or 'Auctor Instruction'
  -- Attempt to load nvim-comment
  local ok, nvim_comment = pcall(require, 'nvim_comment')
  local buf = vim.api.nvim_get_current_buf()
  local row, _ = unpack(vim.api.nvim_win_get_cursor(0))
  if ok then
    -- Insert blank line and toggle comment
    vim.api.nvim_buf_set_lines(buf, row, row, false, { '' })
    vim.api.nvim_win_set_cursor(0, { row + 1, 0 })
    nvim_comment.comment_toggle_linewise_op()
    local commented = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1]
    commented = commented .. ' ' .. marker_text .. ' '
    vim.api.nvim_buf_set_lines(buf, row, row + 1, false, { commented })
    vim.api.nvim_win_set_cursor(0, { row + 1, #commented })
    vim.cmd('startinsert')
  else
    -- Fallback using commentstring
    local cstring = vim.bo.commentstring
    if not cstring or cstring == '' then
      cstring = '// %s'
    end
    if cstring:find('%%s') then
      cstring = cstring:gsub('%%s', marker_text .. ' ')
    else
      cstring = cstring .. ' ' .. marker_text .. ' '
    end
    vim.api.nvim_buf_set_lines(buf, row, row, false, { cstring })
    vim.api.nvim_win_set_cursor(0, { row + 1, #cstring })
    vim.cmd('startinsert')
  end
end

--- Toggle the auto-add behaviour. When enabled, Auctor will call
-- :AuctorAdd automatically on BufReadPost and BufNewFile events.
function M.auctor_auto_add_toggle()
  state.opts.auto_add = not state.opts.auto_add
  util.notify('Auctor auto add is now ' .. (state.opts.auto_add and 'enabled' or 'disabled'), 'info')
end

--- Conditionally invoke auctor_add() if auto-add is enabled.
function M.auto_add_if_enabled()
  if state.opts.auto_add then
    M.auctor_add()
  end
end

--- Select a different provider. Prompts the user for a provider name
-- and sets it active. See :AuctorConfigUI for a UI alternative.
function M.auctor_use(name)
  if not name or name == '' then
    name = vim.fn.input('Enter provider name: ')
  end
  if providers.set_active(name) then
    util.notify('Auctor provider set to: ' .. name, 'info')
  else
    util.notify('Unknown provider: ' .. name, 'error')
  end
end

--- Abort the currently running API call, if any.
function M.auctor_abort()
  if state.current_job then
    util.cancel_current_job()
    util.notify('Auctor request aborted.', 'warn')
  else
    util.notify('No active Auctor request to abort.', 'info')
  end
end

--- Report the current status, including active provider, model and
-- session cost. The output is printed to the command line.
function M.auctor_status()
  local p = providers.get_active()
  local lines = {}
  table.insert(lines, 'Auctor Status:')
  if state.active_provider then
    table.insert(lines, ' Active provider: ' .. state.active_provider)
  else
    table.insert(lines, ' Active provider: default')
  end
  if p then
    table.insert(lines, ' Endpoint: ' .. (p.base_url or ''))
    table.insert(lines, ' Model: ' .. (p.model or ''))
    table.insert(lines, ' Temperature: ' .. tostring(p.temperature or ''))
    table.insert(lines, ' API key env: ' .. (p.api_key_env or ''))
  end
  table.insert(lines, string.format(' Session cost: $%.6f', state.session_total_cost))
  util.notify(table.concat(lines, '\n'), 'info')
end

return M