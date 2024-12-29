# Auctor

Auctor is a neovim LLM plugin for updating code based on comments.

## Usage 

Select text and execute `:AuctorUpdate`. 
The selected text will be transformed according to the comments starting with `vim.g.auctor_instruction_marker` (by default `|||`).

### Example

This goes in

```c
int main() {
    /*||| calculate the first five fibbonacci numbers*/
	return -1;
}
```

and this comes out

```c
#include <stdio.h>

int main() {
    int fib[5]; // Array to store the first five Fibonacci numbers
    fib[0] = 0; // First Fibonacci number
    fib[1] = 1; // Second Fibonacci number

    // Calculate the next three Fibonacci numbers
    for (int i = 2; i < 5; i++) {
        fib[i] = fib[i - 1] + fib[i - 2];
    }

    // Print the first five Fibonacci numbers
    for (int i = 0; i < 5; i++) {
        printf("%d ", fib[i]);
    }
    printf("\n");

    return 0;
}
```

### Uploading entire file

If you want LLM to have your entire file as a context execute `:AuctorAdd` to send the current buffer and the path to its file.
This will not alter any text, but will give LLM an idea about your code structure.

### Creating instruction comments with one command

It is convenient to insert instructions with a keybind. Map `AuctorInsert` for that:

```lua
vim.api.nvim_set_keymap('n', '<leader>ai', ':AuctorInsert<CR>', { noremap = true, silent = true })
```

This will start a new line with an instruction comment and will drop you into the insert mode.


## Requirements

- **Neovim** 0.7+ (due to async job usage).  
- **curl** must be available in your `$PATH`, as the plugin invokes `curl` to contact OpenAI’s API.  
- Optionally, **[nvim-notify](https://github.com/rcarriga/nvim-notify)** for better notifications.  
- Optionally, **[nvim-comment](https://github.com/terrortylor/nvim-comment)** for smoother `AuctorInsert`

## Installation


### Packer

```lua
use("verdigris12/auctor.nvim")
```

### lazy.nvim

```lua
{
  "verdigris12/auctor.nvim",
  config = function()
    require("auctor").setup()
  end
}
```

 ### Nixvim

 (pick a revision for your liking)

 ```nix
  programs.nixvim.extraPlugins = [
    (pkgs.vimUtils.buildVimPlugin {
       name = "auctor";
       src = pkgs.fetchFromGitHub {
         owner = "verdigris12";
         repo = "auctor.nvim";
         rev = "7ccadc1fddfb7e3784e61a3e5e5853e6c1c1d7b3";
         sha256 = "oJ2NnpFkOKFI3f+kpSS0n61f8NLqi8VlK81BwJrzjCU=";
     };
    })
  ];
 ```


## Configuration

Auctor uses some global variables to manage configuration:

- `vim.g.auctor_api_key`  
  - OpenAI API key. If not set, the plugin looks in the environment variable `OPENAI_API_KEY`. 
- `vim.g.auctor_model`  
  - The model to use, e.g. `"gpt-4"` or `"gpt-3.5-turbo"`. Defaults to `"gpt-4o"`.  
- `vim.g.auctor_prompt_func`  
  - A Lua function returning a string. This string is used for the system-level instruction on the **first** call of `AuctorUpdate`.  
- `vim.g.auctor_temperature`  
  - The OpenAI temperature, defaults to `0.7`.  
- `vim.g.auctor_update_prompt`  
  - Prepend to updates. By default, it includes logic about an `INSTRUCTION_MARKER`.  
- `vim.g.auctor_add_prompt`  
  - Prepend to the content when calling `AuctorAdd`.  
- `vim.g.auctor_auto_add`  
  - Boolean toggle to automatically call `AuctorAdd` on buffer read or new file creation. Default is `false`.  
- `vim.g.auctor_instruction_marker`  
  - Default is `"|||"`. Used in `AuctorInsert` to create special comment lines.  

All defaults are set in **config.lua**.

### Example

```lua
vim.g.auctor_api_key = "YOUR_OPENAI_API_KEY_HERE"
vim.g.auctor_model = "gpt-3.5-turbo"
vim.g.auctor_auto_add = true
vim.g.auctor_instruction_marker = "|||"
```

## Commands

- `:AuctorUpdate` (Visual-range command)  
  - Sends selected text to the AI for modification or guidance.  
- `:AuctorAdd`  
  - "Uploads" the current buffer to the AI for context in future calls.  
- `:AuctorAutoAddToggle`  
  - Toggles whether new buffers will automatically call `AuctorAdd`.  
- `:AuctorSelect`  
  - Prompts you for a model name and sets `vim.g.auctor_model`.  
- `:AuctorInsert`  
  - Inserts an instruction line (comment) in your file. If [nvim-comment](https://github.com/terrortylor/nvim-comment) is installed, it uses that to format the comment.  

## Frequently asked questions

* Does it support other APIs?

No. This is made for personal use, and so far I'm okay with 4o. Pull requests are welcome, of course.

* Does this work with [molten](https://github.com/benlubas/molten-nvim)/[quarto](https://github.com/quarto-dev/quarto-nvim)?
Oh hell yes.
