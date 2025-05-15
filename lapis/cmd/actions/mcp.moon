import McpServer, find_lapis_application from require "lapis.mcp.server"
json = require "cjson"

-- Command-line interface for the MCP server
{
  argparser: ->
    with require("argparse") "lapis mcp", "Run an MCP server over stdin/out that can communicate with details of Lapis app"
      \option "--send-message", "Send a message by name and exit (e.g. list_tools, server_info, or a tool name)"
      \option "--tool", "Immediately invoke a tool, print output and exit (e.g. routes, models, schema)"

  (args, lapis_args) =>
    if args.hello
      print "Hello from Lapis MCP!"
      return

    config = @get_config lapis_args.environment
    app = find_lapis_application(config)

    server = McpServer(app)

    -- Handle --tool argument
    if args.tool
      tool_name = args.tool

      -- Create a tool call message
      message = {
        type: "tool_call"
        id: "cmd-line-#{os.time!}"
        tool_call: {
          name: tool_name
          parameters: {}
        }
      }

      -- Send message and get response
      response = server\send_message(message)

      -- Output just the tool result, not the full response
      if response.type == "tool_result" and response.tool_result
        print json.encode(response.tool_result)
      else
        print json.encode(response)
      return

    -- Handle --send-message argument
    elseif args.send_message
      message_type = args.send_message

      -- Create message based on type
      message = nil
      if message_type == "list_tools"
        message = { type: "list_tools" }
      elseif message_type == "server_info"
        -- Skip sending message and directly return server info
        print json.encode(server\get_server_info!)
        return
      else
        -- Assume it's a tool call
        message = {
          type: "tool_call"
          id: "cmd-line-#{os.time!}"
          tool_call: {
            name: message_type
            parameters: {}
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
