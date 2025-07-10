local json = require("cjson")
local run_cli
run_cli = function(ServerClass, config)
  if config == nil then
    config = { }
  end
  local argparse = require("argparse")
  local name = config.name or ServerClass.server_name or ServerClass.__name or "mcp-server"
  local parser = argparse(name, "Start an MCP server over stdin/stdout")
  parser:option("--send-message", "Send a raw message by name and exit (e.g. tools/list, initialize)")
  parser:option("--tool", "Immediately invoke a tool, print output and exit")
  parser:flag("--debug", "Enable debug logging to stderr")
  parser:flag("--skip-initialize --skip-init", "Skip the initialize stage and listen for messages immediately")
  local args = parser:parse((function()
    local _accum_0 = { }
    local _len_0 = 1
    for _, v in ipairs(_G.arg) do
      _accum_0[_len_0] = v
      _len_0 = _len_0 + 1
    end
    return _accum_0
  end)())
  local server = ServerClass({
    debug = args.debug
  })
  if args.skip_initialize then
    server.initialized = true
  end
  if args.tool then
    local tool_name = args.tool
    local init_message = {
      jsonrpc = "2.0",
      id = "init-" .. tostring(os.time()),
      method = "initialize",
      params = {
        protocolVersion = "2025-06-18",
        capabilities = { },
        clientInfo = {
          name = "mcp-cli",
          version = "1.0.0"
        }
      }
    }
    local init_response = server:send_message(init_message)
    if init_response.error then
      print("Error initializing server: " .. tostring(json.encode(init_response.error)))
      return 
    end
    local message = {
      jsonrpc = "2.0",
      id = "cmd-line-" .. tostring(os.time()),
      method = "tools/call",
      params = {
        name = tool_name,
        arguments = { }
      }
    }
    local response = server:send_message(message)
    if response.result and response.result.content then
      print(json.encode(response.result.content))
    else
      print(json.encode(response))
    end
    return 
  elseif args.send_message then
    local message_type = args.send_message
    local init_message = {
      jsonrpc = "2.0",
      id = "init-" .. tostring(os.time()),
      method = "initialize",
      params = {
        protocolVersion = "2025-06-18",
        capabilities = { },
        clientInfo = {
          name = "mcp-cli",
          version = "1.0.0"
        }
      }
    }
    local init_response = server:send_message(init_message)
    if init_response.error then
      print("Error initializing server: " .. tostring(json.encode(init_response.error)))
      return 
    end
    local message = nil
    if message_type == "tools/list" then
      message = {
        jsonrpc = "2.0",
        id = "cmd-line-" .. tostring(os.time()),
        method = "tools/list"
      }
    elseif message_type == "initialize" then
      print(json.encode(init_response))
      return 
    else
      message = {
        jsonrpc = "2.0",
        id = "cmd-line-" .. tostring(os.time()),
        method = "tools/call",
        params = {
          name = message_type,
          arguments = { }
        }
      }
    end
    local response = server:send_message(message)
    print(json.encode(response))
    return 
  end
  return server:run_stdio()
end
return {
  run_cli = run_cli
}
