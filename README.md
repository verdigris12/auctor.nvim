# Auctor.nvim

Auctor is a Neovim plugin written in Lua that integrates with the OpenAI API to transform your code or text on the fly using AI completions. It provides two main commands:

1. `:AuctorUpdate`: Sends the visually selected text to OpenAI and replaces it with a transformed version as a code block.
2. `:AuctorAdd`: Uploads the current buffer to OpenAI for analysis without returning the transformed text.

Additionally, the plugin tracks costs of the operations performed using the OpenAI API and reports them after each call.

## Features

- **AuctorUpdate**:
  - Sends the currently selected text (in visual mode) to OpenAI.
  - On the very first call per session, a system prompt (default: `Replace text according to comments`) is prepended.
  - Replaces the selected text with the result wrapped in ``` code fences ```.
  - Prints cost spent on the last transaction and the total cost spent in the current session.

- **AuctorAdd**:
  - Uploads the entire current buffer to OpenAI with a prefix prompt.
  - Does not replace or return text, just logs cost.
  
- **AuctorAutoAddToggle**:
  - Toggles a mode that automatically calls `AuctorAdd` for each new buffer opened or file read.

## Installation

Use your favorite plugin manager. For example, with `packer`:

```lua
use {
  'verdigris12/auctor.nvim',
  config = function()
    -- No special config needed unless you want to set globals
  end
}
```

With lazy.nvim:

```lua
{
  'verdigris12/auctor.nvim',
  config = function()
    -- set configs here if needed
  end
}
```

## Configuration

Set the following global variables before requiring the plugin (e.g. in your init.lua):

| Global Variable                  | Description                                                                                                                                                          | Default                                      |
|----------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------|----------------------------------------------|
| `vim.g.auctor_api_key`           | The OpenAI API key. If not set, will check `OPENAI_API_KEY` environment variable. If neither is set, commands will error out.                                          | *None*                                       |
| `vim.g.auctor_prompt`            | The system prompt for the first `AuctorUpdate` call in a session.                                                                                                     | `"Replace text according to comments"`       |
| `vim.g.auctor_model`             | The OpenAI model to use.                                                                                                                                             | `"gpt-3.5-turbo"`                            |
| `vim.g.auctor_temperature`       | The temperature setting for the OpenAI completion.                                                                                                                   | `0.7`                                        |
| `vim.g.auctor_auto_add`          | A boolean flag indicating whether `AuctorAdd` should be automatically called for each new buffer. Toggle using `:AuctorAutoAddToggle`.                                | `false`                                      |
| `vim.g.auctor_prefix_prompt_func`| A Lua function that returns a prefix prompt string given (filepath, filename, filetype, relpath). By default, it provides file context without requesting a transform. | Provided default function (see README above) |

You can override this function to tailor the prompt:

vim.g.auctor_prefix_prompt_func = function(filepath, filename, filetype, relpath)
  return "Please just store this file's content in your memory. No changes needed.\nFile: " .. filename
end

## Usage

1. Set API Key:

```lua
vim.g.auctor_api_key = "sk-...."  -- or set environment variable OPENAI_API_KEY
```

2. Select Text and Transform:

   * Enter visual mode (e.g. v), select some code or text, then run:

```
:AuctorUpdate
```

    The selected text will be replaced with the completion result, formatted as a code block.

3. Upload File Content:

To simply upload the current buffer content without modifying it:
```
:AuctorAdd
```
This sends the data to OpenAI and logs the cost.

4. Toggle Auto Add:

To enable or disable automatic upload on opening files:
```
:AuctorAutoAddToggle
```

## Key Mappings

You can map these commands in your init.lua or Vim script:

``` lua
-- AuctorUpdate on selected text (visual mode)
vim.api.nvim_set_keymap('v', '<leader>au', ':AuctorUpdate<CR>', { noremap = true, silent = true })

-- AuctorAdd current buffer
vim.api.nvim_set_keymap('n', '<leader>aa', ':AuctorAdd<CR>', { noremap = true, silent = true })

-- Toggle auto add
vim.api.nvim_set_keymap('n', '<leader>at', ':AuctorAutoAddToggle<CR>', { noremap = true, silent = true })

-- Start instruction
vim.api.nvim_set_keymap('n', '<leader>ic', ':lua vim.fn.append(vim.fn.line("."), vim.g.auctor_instruction_marker .. " ")<CR>jA', { noremap = true, silent = true })
```

## Notes

Make sure you have curl and jq (if necessary) installed, as this plugin uses curl to interact with the OpenAI API.
Costs displayed assume GPT-3.5-turbo pricing. If you change models, adjust the cost calculation in util.lua accordingly.
The code block formatting added around the response can be adjusted in api.lua if needed.
