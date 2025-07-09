import McpServer, find_lapis_application from require "lapis.mcp.server"
json = require "cjson"

-- Command-line interface for the MCP server
{
  argparser: ->
    with require("argparse") "lapis mcp", "Run an MCP server over stdin/out that can communicate with details of Lapis app"
      \option "--send-message", "Send a raw message by name and exit (e.g. tools/list, initialize, server_info)"
      \option "--tool", "Immediately invoke a tool, print output and exit (e.g. routes, models, schema)"

  (args, lapis_args) =>
    config = @get_config lapis_args.environment
    app = find_lapis_application(config)

    server = McpServer(app)

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

      -- Handle special cases that don't require initialization
      if message_type == "server_info"
        print json.encode(server\get_server_info!)
        return

      -- For all other messages, initialize first
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
    server\run!
}
