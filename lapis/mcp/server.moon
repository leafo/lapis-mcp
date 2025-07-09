json = require "cjson"
import insert from table

-- MCP server implementation for Lapis
-- Follows Model Context Protocol spec: https://modelcontextprotocol.io/

class McpServer
  new: (@app) =>
    @setup_tools!
    @protocol_version = "2025-06-18"
    @server_capabilities = {
      tools: {}
    }
    @client_capabilities = {}
    @initialized = false

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
          required: {}
        }
        handler: (params) =>
          @list_routes!
      }

      models: {
        name: "models"
        title: "List Models"
        description: "Lists all database models defined in the application"
        inputSchema: {
          type: "object"
          properties: {}
          required: {}
        }
        handler: (params) =>
          @list_models!
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
          schema, err = @get_model_schema(params.model_name)
          if not schema
            return {
              error: err
            }
          schema
      }
    }

  -- IO and message handling
  read_json_chunk: =>
    size_line = io.read("*line")
    return nil unless size_line
    size = tonumber(size_line)
    return nil unless size

    chunk = io.read(size)
    return nil unless chunk

    delimiter = io.read(1)
    return nil unless delimiter == "\n"

    json.decode(chunk)

  write_json_chunk: (obj) =>
    data = json.encode(obj)
    io.write(#data .. "\n")
    io.write(data .. "\n")
    io.flush()

  -- Tool implementations
  list_routes: =>
    routes = {}
    assert @app, "Missing app class"
    router = @.app!.router
    router\build!

    tuples = [{k,v} for k,v in pairs router.named_routes]
    table.sort tuples, (a,b) -> a[1] < b[1]

    tuples

  list_models: =>
    models = {}
    error("not implemented yet")
    return models

  get_model_schema: (model_name) =>
    -- Try to load the model
    ok, db = pcall(require, "models")
    if not ok or type(db) != "table" or not db[model_name]
      return nil, "Model not found: #{model_name}"

    model = db[model_name]

    error "TODO"
    return {}

  -- Message handler
  handle_message: (message) =>
    if message.method == "initialize"
      return @handle_initialize(message)
    elseif message.method == "tools/call"
      -- Check if server is initialized
      unless @initialized
        return {
          jsonrpc: "2.0"
          id: message.id
          error: {
            code: -32002
            message: "Server not initialized. Call initialize first."
          }
        }

      tool_name = message.params.name
      params = message.params.arguments or {}

      unless @tools[tool_name]
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

      tool = @tools[tool_name]

      -- Validate required parameters
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
      ok, result_or_error = pcall(tool.handler, @, params)

      if not ok
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

      -- Handle error result from tool
      if result_or_error.error
        return {
          jsonrpc: "2.0"
          id: message.id
          result: {
            content: {
              {
                type: "text"
                text: result_or_error.error
              }
            }
            isError: true
          }
        }

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
    elseif message.method == "tools/list"
      return @get_tools_list!
    else
      return {
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

    -- Store client capabilities
    @client_capabilities = client_capabilities

    -- Check protocol version compatibility
    if requested_version != @protocol_version
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

    return {
      jsonrpc: "2.0"
      id: message.id
      result: {
        protocolVersion: @protocol_version
        capabilities: @server_capabilities
        serverInfo: {
          name: "lapis-mcp"
          version: "0.1.0"
          vendor: "Lapis"
        }
      }
    }

  -- Get tools list response (for API and testing)
  get_tools_list: =>
    -- Check if server is initialized
    unless @initialized
      return {
        jsonrpc: "2.0"
        error: {
          code: -32002
          message: "Server not initialized. Call initialize first."
        }
      }

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
      result: {
        tools: tools_list
      }
    }

  -- Server info response
  get_server_info: =>
    {
      type: "server_info"
      server: {
        name: "lapis-mcp"
        version: "0.1.0"
        vendor: "Lapis"
      }
    }

  -- Send a single message and get response
  send_message: (message) =>
    response = @handle_message(message)
    return response

  -- Server main loop
  run: =>
    -- Process messages
    while true
      message = @read_json_chunk!
      break unless message

      response = @handle_message(message)
      @write_json_chunk(response)

-- Helper functions outside the class
find_lapis_application = (config) ->
  -- Try to load the main application module
  app_module = "app"
  if config and config.app_module
    app_module = config.app_module

  ok, app = pcall(require, app_module)
  if ok
    return app

  -- Fall back to loading a default Lapis application
  ok, lapis = pcall(require, "lapis")
  if ok
    return lapis.Application()

  error("Could not find a Lapis application")

{:McpServer, :find_lapis_application}
