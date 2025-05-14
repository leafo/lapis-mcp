import McpServer, find_lapis_application from require "lapis.mcp.server"

-- Command-line interface for the MCP server
{
  argparser: ->
    with require("argparse") "lapis mcp", "Run an MCP server over stdin/out that can communicate with details of Lapis app"
      \flag("--hello", "Print a hello message and exit")

  (args, lapis_args) =>
    if args.hello
      print "Hello from Lapis MCP!"
      return

    config = @get_config lapis_args.environment
    app = find_lapis_application(config)

    server = McpServer(app)
    server\run!
}
