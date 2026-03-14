import ToolCallInterface from require "lapis.mcp.tool_call_interface"

-- Anthropic-specific tool format conversion
-- Reference: https://docs.anthropic.com/claude/docs/tool-use

class AnthropicToolCallInterface extends ToolCallInterface
  convert_tool: (tool) =>
    {
      name: tool.name
      description: tool.description
      input_schema: @normalized_schema tool
    }

  -- Normalize tool_use blocks from an Anthropic assistant message
  extract_tool_calls: (message) =>
    return {} unless type(message.content) == "table"

    tool_calls = {}
    for block in *message.content
      continue unless block.type == "tool_use"

      table.insert tool_calls, {
        id: block.id
        name: block.name
        arguments: if type(block.input) == "table"
          block.input
        else
          {}
        error: if block.input != nil and type(block.input) != "table"
          "Expected tool_use input to be an object"
      }

    tool_calls

  build_tool_result_message: =>
    error "AnthropicToolCallInterface does not support individual tool result messages, use build_tool_result_messages instead"

  -- Anthropic expects tool results to be grouped into a single user message
  build_tool_result_messages: (tool_results) =>
    return {} unless #tool_results > 0

    content = {}
    for tool_result in *tool_results
      block = {
        type: "tool_result"
        tool_use_id: tool_result.tool_call.id
        content: tool_result.content
      }

      block.is_error = true if tool_result.is_error
      table.insert content, block

    {
      {
        role: "user"
        :content
      }
    }

{
  :AnthropicToolCallInterface
}
