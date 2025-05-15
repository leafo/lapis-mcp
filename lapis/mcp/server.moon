json = require "cjson"
import insert from table

-- MCP server implementation for Lapis
-- Follows Model Context Protocol spec: https://modelcontextprotocol.io/

class McpServer
  new: (@app) =>
    @setup_tools!

  -- Setup available tools
  setup_tools: =>
    @tools = {
      routes: {
        description: "Lists all named routes in the Lapis application"
        parameters: {}
        handler: (params) =>
          @list_routes!
      }

      models: {
        description: "Lists all database models defined in the application"
        parameters: {}
        handler: (params) =>
          @list_models!
      }

      schema: {
        description: "Shows the schema for a specific database model"
        parameters: {
          model_name: {
            type: "string"
            description: "Name of the model to inspect"
            required: true
          }
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
    if message.type == "tool_call"
      tool_name = message.tool_call.name
      params = message.tool_call.parameters

      unless @tools[tool_name]
        return {
          type: "tool_result"
          id: message.id
          tool_result: {
            error: "Unknown tool: #{tool_name}"
          }
        }

      tool = @tools[tool_name]

      -- Validate required parameters
      for param_name, param_def in pairs(tool.parameters)
        if param_def.required and not params[param_name]
          return {
            type: "tool_result"
            id: message.id
            tool_result: {
              error: "Missing required parameter: #{param_name}"
            }
          }

      -- Call the tool handler
      result = nil
      ok, result_or_error = pcall(tool.handler, @, params)

      if not ok
        return {
          type: "tool_result"
          id: message.id
          tool_result: {
            error: "Error executing tool: #{result_or_error}"
          }
        }

      return {
        type: "tool_result"
        id: message.id
        tool_result: result_or_error
      }
    elseif message.type == "list_tools"
      return @get_tools_list!
    else
      return {
        type: "error"
        error: "Unsupported message type: #{message.type}"
      }

  -- Get tools list response (for API and testing)
  get_tools_list: =>
    tools_list = {}

    for name, tool in pairs(@tools)
      insert tools_list, {
        name: name
        description: tool.description
        parameters: tool.parameters
      }

    {
      type: "tools_list"
      tools: tools_list
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
    -- Send server info
    @write_json_chunk(@get_server_info!)

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
