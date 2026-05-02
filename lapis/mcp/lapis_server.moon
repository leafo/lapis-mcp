json = require "cjson.safe"
import McpServer from require "lapis.mcp.server"

unpack = table.unpack or unpack
pack = table.pack or (...) -> {n: select("#", ...), ...}

-- Run `cb` while tracking which modules get pulled into `package.loaded`,
-- and return a function that purges those modules. The callback's own
-- return value is discarded; pass results out via closure if needed.
--
-- If `cb` errors, modules loaded before the error are auto-purged before
-- the error is re-raised, so the caller never sees half-loaded state.
track_package_loaded = (cb) ->
  before = {}
  for k in pairs package.loaded
    before[k] = true

  ok, err = pcall cb

  added = [k for k in pairs(package.loaded) when not before[k]]

  reset = ->
    for k in *added
      package.loaded[k] = nil

  unless ok
    reset!
    error err, 2

  reset

-- Lapis-specific MCP server implementation
class LapisMcpServer extends McpServer
  @server_name: "lapis-mcp"
  @instructions: [[Tools to query information about the Lapis web application located in the current directory]]

  new: (options={}) =>
    @_initial_app = options.app
    @cookie_jar = {}
    super options

  -- Merge incoming cookie headers into the cookie jar
  -- Empty values clear the cookie (typical logout flow).
  apply_cookies: (response_headers) =>
    import extract_cookies from require "lapis.spec.request"
    parsed = extract_cookies response_headers
    return unless parsed

    for name, val in pairs parsed
      if val == nil or val == ""
        @cookie_jar[name] = nil
      else
        @cookie_jar[name] = val

  -- load the app in a way that required modules can be cleared so that code
  -- changes can be picked up in subsequent calls to mcp tools
  with_fresh_app: (cb) =>
    -- explicit-app mode: caller manages app lifecycle, skip all reload work
    return cb @_initial_app if @_initial_app

    -- purge modules loaded during the previous call
    if @_loaded_reset
      @_loaded_reset!
      @_loaded_reset = nil

    -- lapis.config caches merged configs in its own table; flush it so
    -- edits to a config file are picked up on the next require.
    lapis_config = require "lapis.config"
    lapis_config.reset true

    app_module = lapis_config.get!.app_class or "app"

    -- run the load + callback inside the tracker so anything required
    -- transitively (the app, its models/views, lazy framework deps) is
    -- captured for purging next call
    local results, load_err
    @_loaded_reset = track_package_loaded ->
      ok, app = pcall require, app_module
      unless ok
        load_err = "Could not load Lapis application '#{app_module}': #{app}"
        return
      results = pack cb app

    return nil, load_err if load_err
    unpack results, 1, results.n

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
    @with_fresh_app (app) ->
      router = app!.router
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
    models = {}

    for file in io.popen("find models/ -type f \\( -name '*.lua' -o -name '*.moon' \\)")\lines!
      model_name = file\match("([^/]+)%.%w+$")
      if model_name and not models[model_name]
        models[model_name] = { name: model_name }

    models

  @add_tool {
    name: "simulate"
    description: "Simulate an HTTP request against the Lapis application without starting a server. Returns the response status, headers, and body."
    inputSchema: {
      type: "object"
      properties: {
        path: {
          type: "string"
          description: "Request path, may include query string (e.g. /users?id=1)"
        }
        method: {
          type: "string"
          enum: {"GET", "POST", "PUT", "DELETE", "OPTIONS", "HEAD", "PATCH"}
          description: "HTTP method (defaults to GET)"
        }
        body: {
          type: "string"
          description: "Raw request body"
        }
        headers: {
          type: "object"
          additionalProperties: { type: "string" }
          description: "Request headers as a name->value map"
        }
        host: {
          type: "string"
          description: "Override Host header (default localhost)"
        }
        scheme: {
          type: "string"
          enum: {"http", "https"}
          description: "Request scheme (default http)"
        }
      }
      required: {"path"}
    }
    annotations: {
      title: "Simulate Request"
    }
  }, (params) =>
    @with_fresh_app (app) ->
      import simulate_request from require "lapis.spec.request"

      opts = {
        method: params.method
        body: params.body
        headers: params.headers
        host: params.host
        scheme: params.scheme
        cookies: @cookie_jar
        allow_error: true
      }

      ok, status, body, headers = pcall simulate_request, app, params.path, opts
      return nil, "simulate_request failed: #{status}" unless ok

      @apply_cookies headers

      { :status, :headers, :body }

  @add_tool {
    name: "list_cookies"
    description: "Returns the current contents of the cookie jar as an array of [name, value] pairs. The jar is populated automatically from Set-Cookie response headers on each `simulate` call and replayed on subsequent requests."
    inputSchema: {
      type: "object"
      properties: {}
      required: setmetatable {}, json.array_mt
    }
    annotations: {
      title: "List Cookies"
    }
  }, (params) =>
    tuples = [{k, v} for k, v in pairs @cookie_jar]
    table.sort tuples, (a, b) -> a[1] < b[1]
    tuples

  @add_tool {
    name: "clear_cookies"
    description: "Empties the cookie jar. Subsequent `simulate` calls start with no cookies until the app sets new ones."
    inputSchema: {
      type: "object"
      properties: {}
      required: setmetatable {}, json.array_mt
    }
    annotations: {
      title: "Clear Cookies"
    }
  }, (params) =>
    @cookie_jar = {}
    { cleared: true }

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
      config = require("lapis.config").get!

      import autoload from require "lapis.util"
      loader = autoload "models"

      results = {}
      for model_name in *params.models
        model = loader[model_name]
        unless model
          results[model_name] = { error: "Model not found: #{model_name}" }
          continue

        ok, schema_lines = pcall pg_schema.extract_schema_sql, config, model
        unless ok
          results[model_name] = { error: tostring schema_lines }
          continue

        results[model_name] = { schema: table.concat schema_lines, "\n" }

      results
