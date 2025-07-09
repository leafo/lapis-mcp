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

class McpServer
  @server_name: "lapis-mcp"
  @server_version: "1.0.0"
  @server_vendor: "Lapis"

  new: (@app, @debug = false) =>
    @setup_tools!
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

  -- Setup available tools
  setup_tools: =>
    @tools = {
      routes: {
        name: "routes"
        title: "List Routes"
        description: "Lists all named routes in the Lapis application"
        inputSchema: {
          type: "object"
          properties: {}
          required: json.empty_array
        }
        handler: (params) =>
          routes = {}
          assert @app, "Missing app class"
          router = @.app!.router
          router\build!

          tuples = [{k,v} for k,v in pairs router.named_routes]
          table.sort tuples, (a,b) -> a[1] < b[1]

          tuples
      }

      models: {
        name: "models"
        title: "List Models"
        description: "Lists all database models defined in the application"
        inputSchema: {
          type: "object"
          properties: {}
          required: json.empty_array
        }
        handler: (params) =>
          models = {}
          error("not implemented yet")
          models
      }

      schema: {
        name: "schema"
        title: "Get Model Schema"
        description: "Shows the schema for a specific database model"
        inputSchema: {
          type: "object"
          properties: {
            model_name: {
              type: "string"
              description: "Name of the model to inspect"
            }
          }
          required: {"model_name"}
        }
        handler: (params) =>
          model_name = params.model_name

          ok, db = pcall(require, "models")
          if not ok or type(db) != "table" or not db[model_name]
            return nil, "Model not found: #{model_name}"

          model = db[model_name]
          error "not implemented yet"
      }
    }

  find_tool: (name) =>
    @tools[name]

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

    -- Set up server capabilities based on available tools
    @server_capabilities.tools = {}
    for name, tool in pairs(@tools)
      @server_capabilities.tools[name] = true

    @initialized = true
    @debug_log "success", "Server initialized successfully with #{table.getn([k for k,v in pairs(@tools)])} tools"

    {
      jsonrpc: "2.0"
      id: message.id
      result: {
        protocolVersion: @protocol_version
        capabilities: @server_capabilities
        serverInfo: {
          name: @@server_name
          version: @@server_version
          vendor: @@server_vendor
        }
      }
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

  -- Get tools list response (for API and testing)
  handle_tools_list: with_initialized (message) =>
    tools_list = {}

    for name, tool in pairs(@tools)
      insert tools_list, {
        name: tool.name
        title: tool.title
        description: tool.description
        inputSchema: tool.inputSchema
      }

    {
      jsonrpc: "2.0"
      id: message.id
      result: {
        tools: tools_list
      }
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
    @debug_log "info", "Starting MCP server in stdio mode, waiting for initialization..."
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
