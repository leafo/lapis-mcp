import build_parser, run_parsed_args from require "lapis.mcp.cli"

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

-- Command-line interface for the MCP server
{
  argparser: ->
    build_parser {
      name: "lapis mcp"
      description: "Run an MCP server over stdin/out that can communicate with details of Lapis app"
      setup_parser: (parser) ->
        parser\argument "server_module", "Name of the MCP server module to load", "lapis.mcp.lapis_server"
    }

  (args, lapis_args) =>
    config = @get_config lapis_args.environment

    ServerClass = require args.server_module

    server = ServerClass {
      debug: args.debug
      app: find_lapis_application(config)
    }

    run_parsed_args server, args
}
