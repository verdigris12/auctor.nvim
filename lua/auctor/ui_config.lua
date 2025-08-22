-- Provider configuration UI for Auctor. Presents a floating list of
-- providers with basic actions to add, delete, select and save
-- providers. This UI intentionally keeps editing simple to avoid
-- complex input handling; adding a provider prompts for required
-- fields using vim.ui.input().

local state = require('auctor.state')
local providers = require('auctor.providers')
local util = require('auctor.util')

local M = {}

-- Sorting helper
local function sorted_provider_names()
  local names = {}
  for name in pairs(state.providers) do
    table.insert(names, name)
  end
  table.sort(names)
  return names
end

-- UI state for the current session
local ui_state = {
  buf = nil,
  win = nil,
  idx = 1, -- currently highlighted provider index (1-based)
  lines = {},
}

-- Render the provider list into the buffer. Active provider is
-- indicated with '*'. The cursor position is updated based on
-- ui_state.idx.
local function render()
  if not ui_state.buf or not vim.api.nvim_buf_is_valid(ui_state.buf) then
    return
  end
  local names = sorted_provider_names()
  local lines = {}
  table.insert(lines, 'Auctor Providers')
  table.insert(lines, '-----------------')
  for i, name in ipairs(names) do
    local marker = (state.active_provider == name) and '*' or ' '
    table.insert(lines, string.format(' %s %s', marker, name))
  end
  table.insert(lines, '')
  table.insert(lines, 'Commands: j/k to move, Enter/u to select, a to add, d to delete, s to save, q to quit')
  ui_state.lines = lines
  vim.api.nvim_buf_set_option(ui_state.buf, 'modifiable', true)
  vim.api.nvim_buf_set_lines(ui_state.buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(ui_state.buf, 'modifiable', false)
  -- Move cursor to current idx line (offset by 2 header lines)
  local target_line = 2 + ui_state.idx
  if vim.api.nvim_win_is_valid(ui_state.win) then
    vim.api.nvim_win_set_cursor(ui_state.win, { target_line, 0 })
  end
end

-- Close the UI and clean up
local function close_ui()
  if ui_state.win and vim.api.nvim_win_is_valid(ui_state.win) then
    vim.api.nvim_win_close(ui_state.win, true)
  end
  if ui_state.buf and vim.api.nvim_buf_is_valid(ui_state.buf) then
    vim.api.nvim_buf_delete(ui_state.buf, { force = true })
  end
  ui_state.win = nil
  ui_state.buf = nil
end

-- Add a new provider by prompting the user for fields.
local function add_provider()
  vim.ui.input({ prompt = 'Provider name: ' }, function(name)
    if not name or name == '' then return end
    if state.providers[name] then
      util.notify('Provider already exists: ' .. name, 'error')
      return
    end
    -- Prompt sequentially for fields; some can be blank
    local fields = {}
    local function ask_field(field_key, prompt_text, default, cb)
      vim.ui.input({ prompt = prompt_text, default = default or '' }, function(value)
        fields[field_key] = value or ''
        cb()
      end)
    end
    -- Sequence of prompts
    ask_field('base_url', 'Base URL: (e.g. https://api.openai.com/v1/chat/completions)', providers.default_providers().default.base_url, function()
      ask_field('model', 'Model name: ', providers.default_providers().default.model, function()
        ask_field('temperature', 'Temperature (0.0–1.0): ', tostring(providers.default_providers().default.temperature), function()
          ask_field('api_key_env', 'API key env var name: ', providers.default_providers().default.api_key_env, function()
            ask_field('update_prompt', 'Provider update prompt (optional): ', '', function()
              ask_field('add_prompt', 'Provider add prompt (optional): ', '', function()
                -- Finalise and add provider
                local temp_num = tonumber(fields.temperature)
                if temp_num then fields.temperature = temp_num end
                providers.add_provider(name, {
                  base_url = fields.base_url,
                  model = fields.model,
                  temperature = fields.temperature,
                  api_key_env = fields.api_key_env,
                  update_prompt = fields.update_prompt or '',
                  add_prompt = fields.add_prompt or '',
                })
                -- Refresh list and position cursor on new entry
                ui_state.idx = #sorted_provider_names()
                render()
              end)
            end)
          end)
        end)
      end)
    end)
  end)
end

-- Delete the currently selected provider (except default). Confirm
-- deletion via input().
local function delete_provider()
  local names = sorted_provider_names()
  local name = names[ui_state.idx]
  if not name then return end
  if name == 'default' then
    util.notify('Cannot delete the default provider.', 'warn')
    return
  end
  vim.ui.input({ prompt = 'Delete provider ' .. name .. '? (y/n): ' }, function(answer)
    if answer and answer:lower() == 'y' then
      providers.delete_provider(name)
      -- Adjust idx
      ui_state.idx = math.max(1, ui_state.idx - 1)
      render()
    end
  end)
end

-- Set the currently selected provider as active
local function use_selected_provider()
  local names = sorted_provider_names()
  local name = names[ui_state.idx]
  if name then
    providers.set_active(name)
    util.notify('Active provider set to: ' .. name, 'info')
    render()
  end
end

-- Save providers to .auctor.toml in the current working directory
local function save_providers()
  local path = vim.fn.getcwd() .. '/.auctor.toml'
  providers.save_to_file(path)
  util.notify('Providers saved to ' .. path, 'info')
end

--- Public entrypoint. Opens the UI floating window. If the window is
-- already open, it is refreshed instead.
function M.show_config_ui()
  -- If already open, bring to focus and refresh
  if ui_state.win and vim.api.nvim_win_is_valid(ui_state.win) then
    render()
    vim.api.nvim_set_current_win(ui_state.win)
    return
  end
  -- Ensure providers exist
  providers.ensure_default()
  -- Initialise UI state
  ui_state.idx = 1
  ui_state.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[ui_state.buf].buftype = 'nofile'
  vim.bo[ui_state.buf].bufhidden = 'wipe'
  vim.bo[ui_state.buf].modifiable = false
  -- Determine size and position
  local ui = vim.api.nvim_list_uis()[1]
  local width = math.max(40, math.floor(ui.width * 0.4))
  local height = math.max(10, math.floor(ui.height * 0.4))
  local row = math.floor((ui.height - height) / 2 - 1)
  local col = math.floor((ui.width - width) / 2)
  ui_state.win = vim.api.nvim_open_win(ui_state.buf, true, {
    relative = 'editor',
    style = 'minimal',
    row = row,
    col = col,
    width = width,
    height = height,
    border = 'single',
  })
  -- Key mappings
  local opts = { nowait = true, noremap = true, silent = true, buffer = ui_state.buf }
  vim.keymap.set('n', 'j', function()
    local names = sorted_provider_names()
    ui_state.idx = math.min(#names, ui_state.idx + 1)
    render()
  end, opts)
  vim.keymap.set('n', 'k', function()
    ui_state.idx = math.max(1, ui_state.idx - 1)
    render()
  end, opts)
  vim.keymap.set('n', '<Down>', function()
    local names = sorted_provider_names()
    ui_state.idx = math.min(#names, ui_state.idx + 1)
    render()
  end, opts)
  vim.keymap.set('n', '<Up>', function()
    ui_state.idx = math.max(1, ui_state.idx - 1)
    render()
  end, opts)
  vim.keymap.set('n', 'u', function()
    use_selected_provider()
  end, opts)
  vim.keymap.set('n', '<CR>', function()
    use_selected_provider()
  end, opts)
  vim.keymap.set('n', 'a', function()
    add_provider()
  end, opts)
  vim.keymap.set('n', 'd', function()
    delete_provider()
  end, opts)
  vim.keymap.set('n', 's', function()
    save_providers()
  end, opts)
  vim.keymap.set('n', 'q', function()
    close_ui()
  end, opts)
  vim.keymap.set('n', '<Esc>', function()
    close_ui()
  end, opts)
  -- Render initial contents
  render()
end

return M