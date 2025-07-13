-- CLI utilities for MCP servers
json = require "cjson.safe"

CLIENT_NAME = "lapis-mcp-cli"

-- Generic CLI runner using argparse
run_cli = (ServerClass, config={}) ->
  argparse = require "argparse"

  name = config.name or ServerClass.server_name or ServerClass.__name or "mcp-server"
  
  -- Create argument parser
  parser = argparse name, "Start an MCP server over stdin/stdout"
  parser\option "--send-message", "Send a raw message by name and exit (e.g. tools/list, resources/list, initialize or a JSON object)"
  parser\option "--tool", "Immediately invoke a tool, print output and exit"
  parser\option "--tool-argument --arg", "Argument object to pass for tool call (in JSON format)"
  parser\option "--resource", "Immediately fetch a resource by URI, print output and exit"

  parser\flag "--debug", "Enable debug logging to stderr"
  parser\flag "--skip-initialize --skip-init", "Skip the initialize stage and listen for messages immediately"
  
  -- Parse arguments
  args = parser\parse [v for _, v in ipairs _G.arg]
  
  -- Set debug mode
  server = ServerClass {
    debug: args.debug
  }

  -- Handle --tool immediate invocation
  if args.tool
    server\skip_initialize!
    tool_name = args.tool

    arguments = if args.tool_argument
      assert json.decode args.tool_argument

    -- Create a tool call message
    message = {
      jsonrpc: "2.0"
      id: "cmd-line-#{os.time!}"
      method: "tools/call"
      params: {
        name: tool_name
        :arguments
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

  -- Handle --resource immediate invocation
  if args.resource
    server\skip_initialize!
    resource_uri = args.resource

    -- Create a resource read message
    message = {
      jsonrpc: "2.0"
      id: "cmd-line-#{os.time!}"
      method: "resources/read"
      params: {
        uri: resource_uri
      }
    }

    -- Send message and get response
    response = server\send_message(message)

    -- Output just the resource contents, not the full response
    if response.result and response.result.contents
      print json.encode(response.result.contents)
    else
      print json.encode(response)
    return

  -- Handle --send-message argument
  if args.send_message
    message = switch args.send_message
      when "tools/list"
        server\skip_initialize!
        {
          jsonrpc: "2.0"
          id: "cmd-line-#{os.time!}"
          method: "tools/list"
        }
      when "resources/list"
        server\skip_initialize!
        {
          jsonrpc: "2.0"
          id: "cmd-line-#{os.time!}"
          method: "resources/list"
        }
      when "initialize"
        -- Handle initialize message specially
        {
          jsonrpc: "2.0"
          id: "init-#{os.time!}"
          method: "initialize"
          params: {
            protocolVersion: "2025-06-18"
            capabilities: {}
            clientInfo: {
              name: CLIENT_NAME
              version: "1.0.0"
            }
          }
        }
      else
        server\skip_initialize!
        -- try to parse message as JSON objectd
        assert json.decode args.send_message

    -- Send message and get response
    response = server\send_message message
    print json.encode response
    return

  -- Skip initialization when using immediate invocation flags or when explicitly requested
  if args.skip_initialize or args.tool or args.resource
    server\skip_initialize!

  -- Run server normally
  server\run_stdio!

{:run_cli}
