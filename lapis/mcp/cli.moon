-- CLI utilities for MCP servers
json = require "cjson"

-- Generic CLI runner using argparse
run_cli = (ServerClass, config={}) ->
  argparse = require "argparse"

  name = config.name or ServerClass.server_name or ServerClass.__name or "mcp-server"
  
  -- Create argument parser
  parser = argparse name, "Start an MCP server over stdin/stdout"
  parser\option "--send-message", "Send a raw message by name and exit (e.g. tools/list, initialize)"
  parser\option "--tool", "Immediately invoke a tool, print output and exit"
  parser\flag "--debug", "Enable debug logging to stderr"
  parser\flag "--skip-initialize --skip-init", "Skip the initialize stage and listen for messages immediately"
  
  -- Parse arguments
  args = parser\parse [v for _, v in ipairs _G.arg]
  
  -- Set debug mode
  server = ServerClass {
    debug: args.debug
  }

  if args.skip_initialize
    server.initialized = true
    @debug_log "info", "Skipping initialization"

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
          name: "mcp-cli"
          version: "1.0.0"
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
          name: "mcp-cli"
          version: "1.0.0"
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

{:run_cli}
