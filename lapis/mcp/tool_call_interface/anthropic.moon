import ToolCallInterface from require "lapis.mcp.tool_call_interface"

-- Anthropic-specific tool format conversion
-- Reference: https://docs.anthropic.com/claude/docs/tool-use

class AnthropicToolCallInterface extends ToolCallInterface
  convert_tool: (tool) =>
    anthropic_tool = {
      name: tool.name
      description: tool.description
      input_schema: {
        type: tool.inputSchema.type or "object"
        properties: tool.inputSchema.properties or {}
      }
    }

    if tool.inputSchema.required
      if type(tool.inputSchema.required) == "table" and #tool.inputSchema.required > 0
        anthropic_tool.input_schema.required = tool.inputSchema.required

    anthropic_tool

{
  :AnthropicToolCallInterface
}
