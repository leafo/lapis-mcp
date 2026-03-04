json = require "cjson.safe"

-- ToolCallInterface: Bridge between MCP servers and LLM API tool definitions
-- Base class providing shared logic for tool discovery and execution.
-- Subclass and implement convert_tool() for provider-specific format conversion.

class ToolCallInterface
  new: (mcp_server) =>
    unless mcp_server
      error "ToolCallInterface requires an MCP server instance"
    @server = mcp_server

  -- Get all non-hidden tools from the MCP server
  get_available_tools: =>
    all_tools = @server\get_all_tools!
    -- get_all_tools returns a map, convert to array
    tools_array = [tool for name, tool in pairs all_tools]
    [tool for tool in *tools_array when not tool.hidden]

  -- Convert a single MCP tool to the provider-specific format
  -- Subclasses must override this method
  convert_tool: (tool) =>
    error "convert_tool is not implemented, use a provider subclass"

  -- Convert all available MCP tools to the provider-specific format
  to_tools: =>
    [@convert_tool(tool) for tool in *@get_available_tools!]

  -- Execute a tool call from an LLM response
  -- @param tool_name: Name of the tool to execute
  -- @param arguments: Table of arguments to pass to the tool
  -- @return success (boolean), result (any) or error message (string)
  execute_tool_call: (tool_name, arguments={}) =>
    -- Find the tool
    tool = @server\find_tool(tool_name)
    unless tool
      return false, "Tool not found: #{tool_name}"

    -- Validate required parameters
    if tool.inputSchema.required
      if type(tool.inputSchema.required) == "table"
        for param_name in *tool.inputSchema.required
          unless arguments[param_name]
            return false, "Missing required parameter: #{param_name}"

    -- Execute the tool handler
    ok, result, user_error = pcall(tool.handler, @server, arguments)

    unless ok
      -- pcall error (system error)
      return false, "Tool execution error: #{result}"

    if user_error
      -- User-level error from handler (returned nil, error)
      return false, user_error

    -- Success
    return true, result

  -- Execute a tool call and format the result as JSON string
  -- Useful for returning results to LLM APIs that expect string responses
  execute_tool_call_json: (tool_name, arguments={}) =>
    success, result = @execute_tool_call(tool_name, arguments)

    unless success
      return false, result

    -- Format result as JSON
    if type(result) == "string"
      -- Already a string, return as-is
      return true, result

    -- Convert to JSON
    json_result, err = json.encode(result)
    unless json_result
      return false, "Failed to encode result as JSON: #{err}"

    return true, json_result

{
  :ToolCallInterface
}
