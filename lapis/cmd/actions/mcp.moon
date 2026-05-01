import build_parser, run_parsed_args from require "lapis.mcp.cli"

{
  argparser: ->
    build_parser {
      name: "lapis mcp"
      description: "Load a Lua/MoonScript MCP server module and run it over stdin/stdout"
      setup_parser: (parser) ->
        parser\argument "server_module", "Name of the MCP server module to load (e.g. lapis.mcp.lapis_server)"
    }

  (args, lapis_args) =>
    ServerClass = require args.server_module

    server = ServerClass {
      debug: args.debug
    }

    run_parsed_args server, args
}
