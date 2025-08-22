-- FILE: lua/auctor/api.lua
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

local spinner_frames = {'⣷','⣯','⣟','⡿','⢿','⣻','⣽','⣾'}
local has_notify, notify_lib = pcall(require, 'notify')

local spinner = { timer = nil, frame = 1, notif_id = nil }

local function start_spinner(title_msg, fallback_msg)
  if spinner.timer then spinner.timer:stop(); spinner.timer:close(); spinner.timer = nil end
  spinner.frame = 1; spinner.notif_id = nil
  if has_notify then
    spinner.timer = vim.loop.new_timer()
    spinner.timer:start(0, 100, vim.schedule_wrap(function()
      local frame_char = spinner_frames[spinner.frame]
      spinner.frame = (spinner.frame % #spinner_frames) + 1
      local opts = {}
      if spinner.notif_id then opts.replace = spinner.notif_id else opts.timeout = false end
      opts.title = frame_char .. ' Auctor'
      local n = notify_lib(title_msg, 'info', opts)
      spinner.notif_id = n.id
    end))
  else
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

local function stop_spinner(final_title, final_msg)
  if spinner.timer then spinner.timer:stop(); spinner.timer:close(); spinner.timer = nil end
  if has_notify and spinner.notif_id then
    vim.schedule(function()
      notify_lib(final_msg, 'info', { title = final_title, replace = spinner.notif_id, timeout = 3000 })
      spinner.notif_id = nil
    end)
  else
    vim.schedule(function()
      vim.api.nvim_echo({{'', 'Normal'}}, false, {})
      print(final_msg:gsub('[\r\n]+', ' '))
    end)
  end
end

--------------------------------------------------------------------------------
-- Diff preview helper (scheduled to avoid E5560)
--------------------------------------------------------------------------------

--- Show unified diff in floating window, ask user y/n.
-- Entire function runs on main loop via vim.schedule in caller.
local function present_diff(diff_text, on_done)
  if not diff_text or diff_text == '' then
    on_done(true)
    return
  end

  -- ensure we are on main thread (defensive)
  if not vim.in_fast_event() then
    -- continue
  else
    return vim.schedule(function() present_diff(diff_text, on_done) end)
  end


  -- Build full line array first
  local header = {
    'Diff Preview – press y/Enter to apply, n/q/Esc to cancel',
    ''
  }
  local body = {}
  for s in diff_text:gmatch('[^\n]*\n?') do
    if s:sub(-1) == '\n' then
      table.insert(body, s:sub(1,-2))
    elseif s ~= '' then
      table.insert(body, s)
    end
  end
  vim.list_extend(header, body)


  local buf = vim.api.nvim_create_buf(false,true)
  vim.bo[buf].buftype, vim.bo[buf].bufhidden = 'nofile','wipe'
  vim.api.nvim_buf_set_lines(buf,0,-1,false,header) -- buffer still modifiable here
  vim.bo[buf].modifiable = false
  vim.bo[buf].filetype = 'diff'


  local ui = vim.api.nvim_list_uis()[1] or { width = 120, height = 40 }
  local W,H = ui.width, ui.height
  local win_w = math.floor(math.min(math.max(W-10,60), W*0.8))
  local win_h = math.floor(math.min(math.max(#header+2,10), H*0.8))
  local row = math.max(0, math.floor((H-win_h)/2-1))
  local col = math.max(0, math.floor((W-win_w)/2))


  local win = vim.api.nvim_open_win(buf,true,{relative='editor',style='minimal',border='single',row=row,col=col,width=win_w,height=win_h})


  local function finish(apply)
    if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win,true) end
    if on_done then on_done(apply) end
  end
  local opts={nowait=true,noremap=true,silent=true,buffer=buf}
  vim.keymap.set('n','q',function() finish(false) end,opts)
  vim.keymap.set('n','n',function() finish(false) end,opts)
  vim.keymap.set('n','<Esc>',function() finish(false) end,opts)
  vim.keymap.set('n','y',function() finish(true) end,opts)
  vim.keymap.set('n','<CR>',function() finish(true) end,opts)
end

--------------------------------------------------------------------------------
-- Core API functions
--------------------------------------------------------------------------------

local M = {}

function M.auctor_update()
  local text, start_pos, end_pos = util.get_visual_selection()
  if text == '' then
    util.notify('AuctorUpdate: No text selected.', 'error')
    return
  end

  local filepath = vim.fn.expand('%:p')
  local filetype = vim.bo.filetype or ''
  local provider = providers.get_active()

  local user_content = ''
  user_content = user_content .. 'FILEPATH: ' .. filepath .. '\n\n'
  user_content = user_content .. '```' .. filetype .. '\n' .. text .. '\n```\n'

  local messages = {}
  if not state.session_first_update_called then
    local marker = state.opts.instruction_marker or (config.default_instruction_marker or '|||')
    local system_prompt = state.opts.system_update_prompt
      or (config.build_update_prompt and config.build_update_prompt(marker))
      or ('Update the provided code according to comments starting with ' .. marker .. '. Return raw code only, no fences.')
    if provider and provider.update_prompt and provider.update_prompt ~= '' then
      system_prompt = system_prompt .. '\n' .. provider.update_prompt
    end
    table.insert(messages, { role = 'system', content = system_prompt })
    state.session_first_update_called = true
  end
  table.insert(messages, { role = 'user', content = user_content })

  start_spinner('Updating selection...', 'Auctor: Updating selection...')
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
    local inner = content:match('^%s*```[%w_]*%s*[\r\n](.*)[\r\n]```%s*$')
    if inner then content = inner end

    local diff = util.diff_unified(text, content)
    local usage = resp.usage or {}
    local cost = util.calculate_cost(usage)

    present_diff(diff, function(apply)
      if apply then
        util.replace_visual_selection(start_pos, end_pos, content)
        state.session_total_cost = (state.session_total_cost or 0) + cost
        util.notify(string.format('Selection updated.\nThis transaction: $%.6f\nThis session: $%.6f', cost, state.session_total_cost), 'info')
      else
        util.notify('Update canceled.', 'warn')
      end
    end)
  end)
end

function M.auctor_add()
  local buf = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local file_content = table.concat(lines, '\n')
  local filepath = vim.fn.expand('%:p')
  local filetype = vim.bo.filetype or ''
  local provider = providers.get_active()

  local user_content = ''
  user_content = user_content .. 'FILEPATH: ' .. filepath .. '\n\n'
  user_content = user_content .. '```' .. filetype .. '\n' .. file_content .. '\n```\n'

  local messages = {}
  local system_prompt = state.opts.system_add_prompt
    or (config.default_system_add_prompt or 'Respond with "Understood". No other text.')
  if provider and provider.add_prompt and provider.add_prompt ~= '' then
    system_prompt = system_prompt .. '\n' .. provider.add_prompt
  end
  table.insert(messages, { role = 'system', content = system_prompt })
  table.insert(messages, { role = 'user', content = user_content })

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
    state.session_total_cost = (state.session_total_cost or 0) + cost
    util.notify(string.format('File uploaded.\nThis transaction: $%.6f\nThis session: $%.6f', cost, state.session_total_cost), 'info')
  end)
end

function M.auctor_insert()
  local marker_text = state.opts.instruction_marker or (config.default_instruction_marker or 'Auctor Instruction')
  local ok, nvim_comment = pcall(require, 'nvim_comment')
  local buf = vim.api.nvim_get_current_buf()
  local row, _ = unpack(vim.api.nvim_win_get_cursor(0))
  if ok then
    vim.api.nvim_buf_set_lines(buf, row, row, false, { '' })
    vim.api.nvim_win_set_cursor(0, { row + 1, 0 })
    nvim_comment.comment_toggle_linewise_op()
    local commented = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1]
    commented = commented .. ' ' .. marker_text .. ' '
    vim.api.nvim_buf_set_lines(buf, row, row + 1, false, { commented })
    vim.api.nvim_win_set_cursor(0, { row + 1, #commented })
    vim.cmd('startinsert')
  else
    local cstring = vim.bo.commentstring
    if not cstring or cstring == '' then cstring = '// %s' end
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

function M.auctor_auto_add_toggle()
  state.opts.auto_add = not state.opts.auto_add
  util.notify('Auctor auto add is now ' .. (state.opts.auto_add and 'enabled' or 'disabled'), 'info')
end

function M.auto_add_if_enabled()
  if state.opts.auto_add then
    M.auctor_add()
  end
end

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

function M.auctor_abort()
  if state.current_job then
    util.cancel_current_job()
    util.notify('Auctor request aborted.', 'warn')
  else
    util.notify('No active Auctor request to abort.', 'info')
  end
end

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
  table.insert(lines, string.format(' Session cost: $%.6f', state.session_total_cost or 0))
  util.notify(table.concat(lines, '\n'), 'info')
end

return M
