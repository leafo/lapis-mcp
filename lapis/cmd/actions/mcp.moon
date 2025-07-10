import LapisMcpServer  from require "lapis.mcp.lapis_server"
json = require "cjson"

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
    with require("argparse") "lapis mcp", "Run an MCP server over stdin/out that can communicate with details of Lapis app"
      \option "--send-message", "Send a raw message by name and exit (e.g. tools/list, initialize)"
      \option "--tool", "Immediately invoke a tool, print output and exit (e.g. list_routes, list_models, schema)"
      \flag "--debug", "Enable debug logging to stderr"
      \flag "--skip-initialize --skip-init", "Skip the initialize stage and listen for messages immediately"

  (args, lapis_args) =>
    config = @get_config lapis_args.environment
    app = find_lapis_application(config)

    server = LapisMcpServer(app, {debug: args.debug})

    if args.skip_initialize
      server.initialized = true

    -- Handle --tool argument
    if args.tool
      tool_name = args.tool

      -- First initialize the server
      init_message = {
        jsonrpc: "2.0"
        id: "init-#{os.time!}"
        method: "initialize"
        params: {
          protocolVersion: "2025-06-18"
          capabilities: {}
          clientInfo: {
            name: "lapis-mcp-cli"
            version: "0.1.0"
          }
        }
      }

      init_response = server\send_message(init_message)
      if init_response.error
        print "Error initializing server: #{json.encode(init_response.error)}"
        return

      -- Create a tool call message
      message = {
        jsonrpc: "2.0"
        id: "cmd-line-#{os.time!}"
        method: "tools/call"
        params: {
          name: tool_name
          arguments: {}
        }
      }

      -- Send message and get response
      response = server\send_message(message)

      -- Output just the tool result, not the full response
      if response.result and response.result.content
        print json.encode(response.result.content)
      else
        print json.encode(response)
      return

    -- Handle --send-message argument
    elseif args.send_message
      message_type = args.send_message

      -- Initialize first for all messages
      init_message = {
        jsonrpc: "2.0"
        id: "init-#{os.time!}"
        method: "initialize"
        params: {
          protocolVersion: "2025-06-18"
          capabilities: {}
          clientInfo: {
            name: "lapis-mcp-cli"
            version: "0.1.0"
          }
        }
      }

      init_response = server\send_message(init_message)
      if init_response.error
        print "Error initializing server: #{json.encode(init_response.error)}"
        return

      -- Create message based on type
      message = nil
      if message_type == "tools/list"
        message = {
          jsonrpc: "2.0"
          id: "cmd-line-#{os.time!}"
          method: "tools/list"
        }
      elseif message_type == "initialize"
        -- Already handled above, just return the init response
        print json.encode(init_response)
        return
      else
        -- Assume it's a tool call
        message = {
          jsonrpc: "2.0"
          id: "cmd-line-#{os.time!}"
          method: "tools/call"
          params: {
            name: message_type
            arguments: {}
          }
        }

      -- Send message and get response
      response = server\send_message(message)

      -- Output response as JSON
      print json.encode(response)
      return

    -- Run server normally
    server\run_stdio!
}
