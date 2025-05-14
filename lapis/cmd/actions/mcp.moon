json = require "cjson"
import insert from table

-- MCP server implementation for Lapis
-- Follows Model Context Protocol spec: https://modelcontextprotocol.io/

read_json_chunk = ->
  size_line = io.read("*line")
  return nil unless size_line
  size = tonumber(size_line)
  return nil unless size

  chunk = io.read(size)
  return nil unless chunk

  delimiter = io.read(1)
  return nil unless delimiter == "\n"

  json.decode(chunk)

write_json_chunk = (obj) ->
  data = json.encode(obj)
  io.write(#data .. "\n")
  io.write(data .. "\n")
  io.flush()

find_lapis_application = (config) ->
  -- Try to load the main application module
  app_module = "app"
  if config.app_module
    app_module = config.app_module

  ok, app = pcall(require, app_module)
  if ok
    return app

  -- Fall back to loading a default Lapis application
  lapis = require "lapis"
  io.stderr\write "Warning: Loading empty Lapis application\n"
  lapis.Application()

list_routes = (app) ->
  routes = {}

  if app.router and app.router.named_routes
    for name, route in pairs(app.router.named_routes)
      insert routes, {
        name: name
        path: route[1]
        method: route[2] or "GET"
      }

  return routes

list_models = ->
  models = {}

  -- Attempt to discover models in standard locations
  ok, db = pcall(require, "models")
  if ok and type(db) == "table"
    for name, model in pairs(db)
      if type(model) == "table" and model.__base
        insert models, name

  return models

get_model_schema = (model_name) ->
  -- Try to load the model
  ok, db = pcall(require, "models")
  if not ok or type(db) != "table" or not db[model_name]
    return nil, "Model not found: #{model_name}"

  model = db[model_name]

  -- Extract schema information if available
  schema = {}

  if model.columns
    for name, type in pairs(model.columns)
      schema[name] = {
        type: type
      }

  if model.relations
    schema._relations = model.relations

  return schema

-- MCP tools implementation
tools = {
  routes: {
    description: "Lists all named routes in the Lapis application"
    parameters: {}
    handler: (app, params) ->
      list_routes(app)
  }

  models: {
    description: "Lists all database models defined in the application"
    parameters: {}
    handler: (app, params) ->
      list_models()
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
    handler: (app, params) ->
      schema, err = get_model_schema(params.model_name)
      if not schema
        return {
          error: err
        }
      schema
  }
}

handle_message = (app, message) ->
  if message.type == "tool_call"
    tool_name = message.tool_call.name
    params = message.tool_call.parameters

    unless tools[tool_name]
      return {
        type: "tool_result"
        id: message.id
        tool_result: {
          error: "Unknown tool: #{tool_name}"
        }
      }

    tool = tools[tool_name]

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
    ok, result_or_error = pcall(tool.handler, app, params)

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
    tools_list = {}

    for name, tool in pairs(tools)
      insert tools_list, {
        name: name
        description: tool.description
        parameters: tool.parameters
      }

    return {
      type: "tools_list"
      tools: tools_list
    }
  else
    return {
      type: "error"
      error: "Unsupported message type: #{message.type}"
    }

run_mcp_server = (app) ->
  -- Send server info
  write_json_chunk {
    type: "server_info"
    server: {
      name: "lapis-mcp"
      version: "0.1.0"
      vendor: "Lapis"
    }
  }

  -- Process messages
  while true
    message = read_json_chunk()
    break unless message

    response = handle_message(app, message)
    write_json_chunk(response)

{
  argparser: ->
    require("argparse") "lapis mcp", "Run an MCP server over stdin/out that can communicate with details of Lapis app"

  (args, lapis_args) =>
    if args.hello
      print "Hello from Lapis MCP!"
      return

    config = @get_config lapis_args.environment
    app = find_lapis_application(config)
    run_mcp_server(app)
}
