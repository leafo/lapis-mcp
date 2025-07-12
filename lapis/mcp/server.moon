json = require "cjson.safe"
colors = require "ansicolors"
import insert from table

-- MCP server implementation for Lapis
-- Follows Model Context Protocol spec: https://modelcontextprotocol.io/

class StdioTransport
  -- IO and message handling
  read_json_chunk: =>
    chunk = io.read "*l"
    unless chunk
      return false

    message = json.decode chunk
    unless message
      return nil, "Failed to decode JSON chunk"

    message

  write_json_chunk: (obj) =>
    data = assert json.encode(obj)
    io.write data .. "\n"
    io.flush!

class StdioTransportWithDebugLog
  new: =>
    @file_log = io.open "/tmp/lapis-mcp.log", "a"
    @file_log\write "START SESSION: " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n"

  -- IO and message handling
  read_json_chunk: =>
    chunk = io.read "*l"
    unless chunk
      return false

    @file_log\write "READ: " .. chunk .. "\n"
    @file_log\flush!

    message = json.decode chunk
    unless message
      return nil, "Failed to decode JSON chunk"

    message

  write_json_chunk: (obj) =>
    data = assert json.encode(obj)

    @file_log\write "WRITE: " .. data .. "\n"
    @file_log\flush!

    io.write data .. "\n"
    io.flush!

class StreamableHttpTransport
  read_json_chunk: =>
    error "TODO"

  write_json_chunk: =>
    error "TODO"

with_initialized = (fn) ->
  (message) =>
    unless @initialized
      return {
        jsonrpc: "2.0"
        id: message.id
        error: {
          code: -32002
          message: "Server not initialized. Call initialize first."
        }
      }

    fn @, message

-- Base MCP server class that can be extended
class McpServer
  -- @server_name: "lapis-mcp"
  @server_version: "1.0.0"
  @server_vendor: "Lapis"

  -- Generic CLI runner using argparse
  @run_cli: (config) =>
    import run_cli from require "lapis.mcp.cli"
    run_cli @, config

  -- utility for creating sub class when in Lua
  @extend: (name, tbl) =>
    lua = require "lapis.lua"

    if type(name) == "table"
      tbl = name
      name = nil

    class_fields = { }

    cls = lua.class name or "McpServer", tbl, @
    cls, cls.__base

  -- add tool to the server
  -- https://modelcontextprotocol.io/docs/concepts/tools#tool-definition-structure
  @add_tool: (details, call_fn) =>
    -- Initialize tools registry on this class if it doesn't exist
    unless rawget(@, "tools")
      rawset(@, "tools", {})

    tool_def = {
      name: details.name
      description: details.description
      inputSchema: details.inputSchema
      annotations: details.annotations
      handler: call_fn
    }

    -- Insert tool into array
    table.insert(rawget(@, "tools"), tool_def)

  new: (options = {}) =>
    @debug = options.debug or false
    @protocol_version = "2025-06-18"
    @server_capabilities = {
      tools: {}
    }
    @client_capabilities = {}
    @initialized = false

  -- Debug logging helper
  debug_log: (level, message) =>
    return unless @debug

    color = switch level
      when "info" then "%{cyan}"
      when "success" then "%{green}"
      when "warning" then "%{yellow}"
      when "error" then "%{red}"
      when "debug" then "%{dim white}"
      else "%{white}"

    timestamp = os.date("%H:%M:%S")
    io.stderr\write colors "#{color}[#{timestamp}] #{level\upper!}: #{message}%{reset}\n"

  -- Skip initialization and mark server as initialized
  skip_initialize: =>
    return nil, "Server already initialized" if @initialized
    @initialized = true
    @debug_log "info", "Skipping initialization"
    @initialized

  find_tool: (name) =>
    -- Search up the inheritance chain for the tool
    current_class = @.__class
    while current_class
      tools = rawget(current_class, "tools")
      if tools
        -- Search through the array for the tool by name
        for tool in *tools
          if tool.name == name
            return tool
      current_class = current_class.__parent
    nil

  -- IO and message handling
  read_json_chunk: =>
    @transport\read_json_chunk!

  write_json_chunk: (obj) =>
    @transport\write_json_chunk obj

  -- Message handler
  handle_message: (message) =>
    @debug_log "info", "Received message: #{message.method}"

    switch message.method
      when "initialize"
        @handle_initialize message
      when "notifications/initialized"
        @debug_log "info", "Client notified initialized"
        @client_initialized = true
      when "notifications/cancelled"
        @handle_notifications_canceled message
      when "tools/list"
        @debug_log "info", "Listing available tools"
        @handle_tools_list message
      when "tools/call"
        @handle_tools_call message
      when "ping"
        @handle_ping message
      else
        @debug_log "warning", "Unknown method: #{message.method}"
        {
          jsonrpc: "2.0"
          id: message.id
          error: {
            code: -32601
            message: "Method not found: #{message.method}"
          }
        }

  -- Handle initialization message
  handle_initialize: (message) =>
    params = message.params or {}

    -- Extract client info
    client_info = params.clientInfo or {}
    client_capabilities = params.capabilities or {}
    requested_version = params.protocolVersion or "2025-06-18"

    @debug_log "info", "Initializing server with protocol version: #{requested_version}"
    if client_info.name
      @debug_log "debug", "Client: #{client_info.name} v#{client_info.version or 'unknown'}"

    -- Store client capabilities
    @client_capabilities = client_capabilities

    -- Check protocol version compatibility
    if requested_version != @protocol_version
      @debug_log "error", "Protocol version mismatch: server=#{@protocol_version}, client=#{requested_version}"
      return {
        jsonrpc: "2.0"
        id: message.id
        error: {
          code: -32602
          message: "Protocol version mismatch. Server supports: #{@protocol_version}, client requested: #{requested_version}"
        }
      }

    @initialized = true
    @debug_log "success", "Server initialized"

    {
      jsonrpc: "2.0"
      id: message.id
      result: @server_specification!
    }

  get_server_name: =>
    @@server_name or @@__name

  server_specification: =>
    {
      protocolVersion: @protocol_version
      capabilities: @server_capabilities
      serverInfo: {
        name: @get_server_name!
        version: @@server_version
        vendor: @@server_vendor
      }
      instructions: @@instructions
    }


  handle_tools_call: with_initialized (message) =>
    tool_name = message.params.name
    params = message.params.arguments or {}

    @debug_log "info", "Executing tool: #{tool_name}"

    tool = @find_tool tool_name

    unless tool
      return {
        jsonrpc: "2.0"
        id: message.id
        result: {
          content: {
            {
              type: "text"
              text: "Unknown tool: #{tool_name}"
            }
          }
          isError: true
        }
      }

    -- Validate required parameters
    -- it might not be a table if it's json.empty_array
    if type(tool.inputSchema.required) == "table"
      for param_name in *tool.inputSchema.required
        if not params[param_name]
          return {
            jsonrpc: "2.0"
            id: message.id
            result: {
              content: {
                {
                  type: "text"
                  text: "Missing required parameter: #{param_name}"
                }
              }
              isError: true
            }
          }

    -- Call the tool handler
    ok, result_or_error, user_error = pcall(tool.handler, @, params)

    if not ok
      @debug_log "error", "Tool execution failed: #{result_or_error}"
      return {
        jsonrpc: "2.0"
        id: message.id
        result: {
          content: {
            {
              type: "text"
              text: "Error executing tool: #{result_or_error}"
            }
          }
          isError: true
        }
      }

    -- wrap nil, err into object
    if result_or_error == nil
      @debug_log "warning", "Tool returned error: #{user_error or "Unknown error"}"
      return {
        jsonrpc: "2.0"
        id: message.id
        result: {
          content: {
            {
              type: "text"
              text: "Error executing tool: #{user_error or "Unknown error"}"
            }
          }
          isError: true
        }
      }

    @debug_log "success", "Tool executed successfully: #{tool_name}"
    return {
      jsonrpc: "2.0"
      id: message.id
      result: {
        content: {
          {
            type: "text"
            text: json.encode(result_or_error)
          }
        }
        isError: false
      }
    }

  -- Get all tools from the inheritance chain
  get_all_tools: =>
    all_tools = {}
    current_class = @__class
    while current_class
      if tools = rawget(current_class, "tools")
        for tool in *tools
          unless all_tools[tool.name]  -- Don't override tools from parent classes
            all_tools[tool.name] = tool

      current_class = current_class.__parent
    all_tools

  -- Get tools list response (for API and testing)
  handle_tools_list: with_initialized (message) =>
    tools_list = for name, tool in pairs @get_all_tools!
      {
        name: tool.name
        description: tool.description
        inputSchema: tool.inputSchema
        annotations: tool.annotations
      }

    table.sort tools_list, (a, b) -> a.name < b.name

    {
      jsonrpc: "2.0"
      id: message.id
      result: {
        tools: tools_list
      }
    }

  -- Handle ping message
  handle_ping: (message) =>
    @debug_log "debug", "Received ping request"
    {
      jsonrpc: "2.0"
      id: message.id
      result: {}
    }

  --- called to cancel a running job
  -- {"jsonrpc":"2.0","method":"notifications/cancelled","params":{"requestId":1,"reason":"McpError: MCP error -32001: Request timed out"}}
  handle_notifications_canceled: (message) =>
    id = message.params.requestId
    -- we ignore this now, there's nothing we can do without async tasks
    nil

  -- alias for handle_message that's used for direct invocation via CLI
  send_message: (message) =>
    @handle_message message

  -- Server main loop
  run_stdio: =>
    @debug_log "info", table.concat {
      "Starting MCP server #{@get_server_name!} in stdio mode"
      if @initialized
        ", ready for messages"
      else
        ", waiting for initialization..."
    }

    unless @transport
      @transport = StdioTransport!

    -- Process messages
    while true
      message = @read_json_chunk!
      if message == false
        @debug_log "info", "io closed, exiting..."
        break

      unless message
        @debug_log "warning", "Malformed message received: not valid JSON, ignoring..."
        continue

      response = @handle_message message
      if response
        @write_json_chunk response

{:McpServer, :StdioTransport}
