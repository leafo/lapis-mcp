import McpServer, find_lapis_application from require "lapis.mcp.server"
json = require "cjson"

-- Command-line interface for the MCP server
{
  argparser: ->
    with require("argparse") "lapis mcp", "Run an MCP server over stdin/out that can communicate with details of Lapis app"
      \option "--send-message", "Send a message by name and exit (e.g. list_tools, server_info, or a tool name)"
      \option "--tool", "Immediately invoke a tool, print output and exit (e.g. routes, models, schema)"

  (args, lapis_args) =>
    config = @get_config lapis_args.environment
    app = find_lapis_application(config)

    server = McpServer(app)

    -- Handle --tool argument
    if args.tool
      tool_name = args.tool

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

      -- Create message based on type
      message = nil
      if message_type == "list_tools"
        message = {
          jsonrpc: "2.0"
          id: "cmd-line-#{os.time!}"
          method: "tools/list"
        }
      elseif message_type == "server_info"
        -- Skip sending message and directly return server info
        print json.encode(server\get_server_info!)
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
