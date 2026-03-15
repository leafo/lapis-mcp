json = require "cjson"

-- ToolAdapter: Bridge between MCP servers and LLM API tool definitions
-- Base class providing shared logic for tool discovery and execution.
-- Subclass and implement convert_tool() for provider-specific format conversion.

class ToolAdapter
  subclass_responsibility: (method_name) =>
    error "subclass responsibility: implement #{method_name}"

  new: (mcp_server) =>
    unless mcp_server
      error "ToolAdapter requires an MCP server instance"
    @server = mcp_server

  -- Normalize an MCP tool schema for provider-specific wrappers
  normalized_schema: (tool) =>
    schema = {
      type: tool.inputSchema.type or "object"
      properties: tool.inputSchema.properties or {}
    }

    if type(tool.inputSchema.required) == "table" and #tool.inputSchema.required > 0
      schema.required = tool.inputSchema.required

    schema

  -- Convert a single MCP tool to the provider-specific format
  -- Subclasses must override this method
  convert_tool: (tool) =>
    @subclass_responsibility "convert_tool"

  -- Convert all available MCP tools to the provider-specific format
  to_tools: =>
    setmetatable [@convert_tool(tool) for tool in *@server\get_enabled_tools!], json.array_mt

  -- Decode provider-specific tool calls into a normalized shape
  extract_tool_calls: (message) =>
    @subclass_responsibility "extract_tool_calls"

  -- Wrap a serialized tool result in a provider-specific response message
  build_tool_result_message: (tool_result) =>
    @subclass_responsibility "build_tool_result_message"

  -- Build one or more provider-specific result messages
  build_tool_result_messages: (tool_results) =>
    [@build_tool_result_message(tool_result) for tool_result in *tool_results]

  -- Serialize a tool result for LLM APIs
  serialize_result: (result) =>
    if type(result) == "string"
      return result

    json.encode result

  -- Serialize a tool error for LLM APIs
  serialize_error: (err) =>
    json.encode error: tostring(err)

  -- Execute a normalized tool call and return serialized content
  execute_tool_call: (tool_call) =>
    if tool_call.error
      return {
        tool_call: tool_call
        content: @serialize_error(tool_call.error)
        is_error: true
      }

    result, err = @server\execute_tool tool_call.name, tool_call.arguments or {}
    if err
      return {
        tool_call: tool_call
        content: @serialize_error(err)
        is_error: true
      }

    {
      tool_call: tool_call
      content: @serialize_result result
      is_error: false
    }

  -- Process provider tool calls into provider-specific result messages
  process_tool_calls: (message) =>
    tool_calls = @extract_tool_calls message
    return {} unless tool_calls

    tool_results = [@execute_tool_call(tool_call) for tool_call in *tool_calls]
    @build_tool_result_messages tool_results
