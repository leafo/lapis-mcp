json = require "cjson.safe"
import McpServer from require "lapis.mcp.server"

-- Lapis-specific MCP server implementation
class LapisMcpServer extends McpServer
  @server_name: "lapis-mcp"
  @instructions: [[Tools to query information about the Lapis web application located in the current directory]]

  new: (options={}) =>
    @app = options.app
    super options

  -- Register the built-in Lapis tools
  @add_tool {
    name: "list_routes"
    description: "Lists all named routes in the Lapis application"
    inputSchema: {
      type: "object"
      properties: {}
      required: setmetatable {}, json.array_mt
    }
    annotations: {
      title: "List Routes"
    }
  }, (params) =>
    routes = {}
    assert @app, "Missing app class"
    router = @.app!.router
    router\build!

    tuples = [{k,v} for k,v in pairs router.named_routes]
    table.sort tuples, (a,b) -> a[1] < b[1]

    tuples

  @add_tool {
    name: "list_models"
    description: "Lists all database models defined in the application. A model is a class that represents a database table."
    inputSchema: {
      type: "object"
      properties: {}
      required: setmetatable {}, json.array_mt
    }
    annotations: {
      title: "List Models"
    }
  }, (params) =>
    import shell_escape from require "lapis.cmd.path"
    import autoload from require "lapis.util"

    loader = autoload "models"

    models = {}

    for file in io.popen("find models/ -type f \\( -name '*.lua' -o -name '*.moon' \\)")\lines!
      model_name = file\match("([^/]+)%.%w+$")
      model = loader[model_name]

      if model_name and not models[model_name]
        models[model_name] = {
          name: model_name
        }

    models

  @add_tool {
    name: "schema"
    description: "Shows the SQl schema for a specific database model"
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
    annotations: {
      title: "Get Model Schema"
    }
  }, (params) =>
    model_name = params.model_name

    ok, db = pcall(require, "models")
    if not ok or type(db) != "table" or not db[model_name]
      return nil, "Model not found: #{model_name}"

    model = db[model_name]
    error "not implemented yet"
