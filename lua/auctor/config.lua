-- Default configuration values for Auctor. Users can override these
-- values by passing an options table to `require('auctor').setup()`.

local M = {}

-- The marker inserted into the buffer by :AuctorInsert. Update prompts
-- refer to this marker text. You can override this via setup() by
-- setting opts.instruction_marker.
M.default_instruction_marker = '|||'

-- Default system prompt for update requests. The marker placeholder
-- `%s` will be replaced with the actual instruction marker at runtime.
M.default_system_update_prompt = [[
The following string is called the INSTRUCTION_MARKER: "%s".
Update the provided code according to comments beginning with INSTRUCTION_MARKER.
Return the updated code as plain text (do not wrap it in code fences).
Remove all comments beginning with INSTRUCTION_MARKER.
If you need clarification, embed your questions into the code as comments.
]]

-- Default system prompt for add requests. This prompt is sent when
-- uploading an entire file via :AuctorAdd.
M.default_system_add_prompt = [[
This message will provide you with the contents of a file as plain text along with file metadata.
Analyze it and use your understanding to respond to future prompts.
If this file was provided before, assume this prompt includes the latest version.
Respond with "Understood". No other explanation or code is required.
]]

--- Build the system update prompt, substituting the marker.
-- @param marker string the instruction marker used for :AuctorInsert
-- @return string system prompt
function M.build_update_prompt(marker)
  return string.format(M.default_system_update_prompt, marker)
end

return M