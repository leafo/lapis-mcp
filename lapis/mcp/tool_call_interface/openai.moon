import ToolCallInterface from require "lapis.mcp.tool_call_interface"

-- OpenAI-specific tool format conversion
-- Reference: https://platform.openai.com/docs/guides/function-calling

class OpenAIToolCallInterface extends ToolCallInterface
  convert_tool: (tool) =>
    schema = {
      type: tool.inputSchema.type or "object"
      properties: tool.inputSchema.properties or {}
    }

    if tool.inputSchema.required
      if type(tool.inputSchema.required) == "table" and #tool.inputSchema.required > 0
        schema.required = tool.inputSchema.required

    {
      type: "function"
      function: {
        name: tool.name
        description: tool.description
        parameters: schema
      }
    }

{
  :OpenAIToolCallInterface
}
