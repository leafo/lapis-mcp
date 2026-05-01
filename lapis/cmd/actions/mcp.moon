import build_parser, run_parsed_args from require "lapis.mcp.cli"

-- Best-effort lookup of the current Lapis application. Returns nil if the
-- project doesn't expose one — custom MCP servers may not need an app at all.
find_lapis_application = (config) ->
  app_module = config and config.app_module or "app"

  ok, app = pcall require, app_module
  return app if ok

  ok, lapis = pcall require, "lapis"
  return lapis.Application! if ok

  nil

-- Command-line interface for running an MCP server in the context of a Lapis
-- project. The chosen server module is loaded, instantiated with the project's
-- application (when one is available) and started over stdio.
{
  argparser: ->
    build_parser {
      name: "lapis mcp"
      description: "Run a Lua/MoonScript MCP server over stdin/stdout, with the current Lapis application injected as `app`"
      setup_parser: (parser) ->
        parser\argument "server_module", "Name of the MCP server module to load (e.g. lapis.mcp.lapis_server)"
    }

  (args, lapis_args) =>
    ok, config = pcall @get_config, @, lapis_args.environment
    config = nil unless ok

    ServerClass = require args.server_module

    server = ServerClass {
      debug: args.debug
      app: find_lapis_application config
      config: config
    }

    run_parsed_args server, args
}
