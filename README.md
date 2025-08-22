# Auctor

Auctor is a Neovim plugin that lets you update code with the help of
large language models. Highlight a region of text, run a command, and
Auctor will ask your configured provider to transform the selection
according to inline instructions. It then shows you a diff preview
before applying the changes.

## Quick start

1. Install with your favourite plugin manager. For example, with
   **lazy.nvim**:

   ```lua
   {
     "verdigris12/auctor.nvim",
     config = function()
       require("auctor").setup({})
     end,
   }
   ```

2. Set an API key in your shell environment. By default Auctor looks for
   `OPENAI_API_KEY` when talking to the `default` provider. You can
   configure other providers and keys via a `.auctor.toml` file (see
   below).

3. In Neovim, visually select some code and run `:AuctorUpdate`. A
   diff preview will appear; press `y` to accept or `q` to cancel. The
   plugin keeps track of token costs and shows the cost of each
   transaction.

## Commands

- `:AuctorUpdate` – send the visual selection to the model and apply
  its modifications. A diff preview is shown before applying.
- `:AuctorAdd` – upload the current buffer so the model has broader
  context. The file contents are sent along with metadata but are not
  modified.
- `:AuctorInsert` – insert an instruction comment below the current
  line. The marker text is configurable (default `|||`).
- `:AuctorAutoAddToggle` – toggle automatically calling `AuctorAdd`
  when reading or creating buffers.
- `:AuctorUse` **{name}** – switch to another provider from your
  configuration.
- `:AuctorConfigUI` – open a simple floating UI to view, add, delete
  and select providers, and to save them to a `.auctor.toml` file.
- `:AuctorStatus` – show the active provider, model and accumulated
  session cost.
- `:AuctorAbort` – cancel an in‑flight request.

## Configuration

Call `require('auctor').setup({ ... })` once to configure the plugin.
All options are optional:

- `instruction_marker` – the token inserted by `:AuctorInsert`.
- `system_update_prompt` – system prompt used on the first update.
- `system_add_prompt` – system prompt used when uploading files.
- `auto_add` – boolean, call `AuctorAdd` automatically on buffer read.
- `providers` – table of provider definitions to register at startup.

If a `.auctor.toml` file exists in your working directory it will be
loaded automatically. The first provider with `active = true` becomes
active. Providers are defined under `[providers.NAME]` sections. Example:

```
[providers.default]
base_url = "https://api.openai.com/v1/chat/completions"
model = "gpt-4o"
temperature = 0.2
api_key_env = "OPENAI_API_KEY"
update_prompt = ""
add_prompt = ""
active = true

[providers.myrouter]
base_url = "https://openrouter.ai/api/v1/chat/completions"
model = "anthropic/claude-3.5-sonnet"
temperature = 0.2
api_key_env = "OPENROUTER_API_KEY"
update_prompt = ""
add_prompt = ""
```

You can manage providers from inside Neovim via `:AuctorConfigUI`. It
lists the configured providers, lets you add new ones (prompts for
required fields), delete existing ones and switch the active provider.
Saving writes a `.auctor.toml` into your current directory.

## Requirements

- Neovim 0.10 or newer (for `vim.system` and the diff API).
- `curl` available in your `PATH`.
- Optionally, [nvim‑notify](https://github.com/rcarriga/nvim-notify) for
  nicer progress messages and [nvim‑comment](https://github.com/terrortylor/nvim-comment)
  for inserting instruction comments.

## Notes

Auctor does not execute any returned code. It simply inserts the text
provided by your selected model. Always review the diff before
applying changes. Costs are calculated using OpenAI GPT‑4o prices as a
baseline; other providers may differ.