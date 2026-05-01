json = require "cjson.safe"
import McpServer from require "lapis.mcp.server"

-- Lapis-specific MCP server implementation
class LapisMcpServer extends McpServer
  @server_name: "lapis-mcp"
  @instructions: [[Tools to query information about the Lapis web application located in the current directory]]

  new: (options={}) =>
    @app = options.app
    @config = options.config
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

  -- The `schema` tool depends on `lapis-annotate`, which is not declared as a
  -- hard dependency. Only register the tool when the module is available.
  ok, pg_schema = pcall require, "lapis.annotate.pg_schema"
  if ok
    @add_tool {
      name: "schema"
      description: "Returns the SQL schema (CREATE TABLE, indexes, constraints) for one or more database models, dumped live from the project's PostgreSQL database via pg_dump."
      inputSchema: {
        type: "object"
        properties: {
          models: {
            type: "array"
            items: { type: "string" }
            description: "Model class names to dump (e.g. [\"Users\", \"Posts\"])"
          }
        }
        required: {"models"}
      }
      annotations: {
        title: "Get Model Schema"
      }
    }, (params) =>
      return nil, "schema tool requires Lapis project config (none was provided when starting the server)" unless @config

      import autoload from require "lapis.util"
      loader = autoload "models"

      results = {}
      for model_name in *params.models
        model = loader[model_name]
        unless model
          results[model_name] = { error: "Model not found: #{model_name}" }
          continue

        ok, schema_lines = pcall pg_schema.extract_schema_sql, @config, model
        unless ok
          results[model_name] = { error: tostring schema_lines }
          continue

        results[model_name] = { schema: table.concat schema_lines, "\n" }

      results
