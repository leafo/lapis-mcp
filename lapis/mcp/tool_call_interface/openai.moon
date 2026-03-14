import ToolCallInterface from require "lapis.mcp.tool_call_interface"
json = require "cjson.safe"

-- OpenAI-specific tool format conversion and execution
-- Reference: https://platform.openai.com/docs/guides/function-calling

class OpenAIToolCallInterface extends ToolCallInterface
  convert_tool: (tool) =>
    {
      type: "function"
      function: {
        name: tool.name
        description: tool.description
        parameters: @normalized_schema tool
      }
    }

  -- Normalize tool calls from an OpenAI assistant message
  extract_tool_calls: (message) =>
    return {} unless message.tool_calls

    tool_calls = {}
    for tool_call in *message.tool_calls
      func = tool_call.function
      args = {}
      decode_error = nil

      if func.arguments and func.arguments != ""
        args, decode_error = json.decode func.arguments
        unless args
          args = {}

      table.insert tool_calls, {
        id: tool_call.id
        name: func.name
        arguments: args
        error: if decode_error
          "Failed to decode tool arguments as JSON: #{decode_error}"
      }

    tool_calls

  build_tool_result_message: (tool_result) =>
    {
      role: "tool"
      tool_call_id: tool_result.tool_call.id
      content: tool_result.content
    }

{
  :OpenAIToolCallInterface
}
