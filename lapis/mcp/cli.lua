local json = require("cjson.safe")
local CLIENT_NAME = "lapis-mcp-cli"
local run_cli
run_cli = function(ServerClass, config)
  if config == nil then
    config = { }
  end
  local argparse = require("argparse")
  local name = config.name or ServerClass.server_name or ServerClass.__name or "mcp-server"
  local parser = argparse(name, "Start an MCP server over stdin/stdout")
  parser:option("--send-message", "Send a raw message by name and exit (e.g. tools/list, initialize or a JSON object)")
  parser:option("--tool", "Immediately invoke a tool, print output and exit")
  parser:option("--tool-argument --arg", "Argument object to pass for tool cool (in JSON format)")
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
  if args.tool then
    server:skip_initialize()
    local tool_name = args.tool
    local arguments
    if args.tool_argument then
      arguments = assert(json.decode(args.tool_argument))
    end
    local message = {
      jsonrpc = "2.0",
      id = "cmd-line-" .. tostring(os.time()),
      method = "tools/call",
      params = {
        name = tool_name,
        arguments = arguments
      }
    }
    local response = server:send_message(message)
    if response.result and response.result.content then
      print(json.encode(response.result.content))
    else
      print(json.encode(response))
    end
    return 
  end
  if args.send_message then
    local message
    local _exp_0 = args.send_message
    if "tools/list" == _exp_0 then
      server:skip_initialize()
      message = {
        jsonrpc = "2.0",
        id = "cmd-line-" .. tostring(os.time()),
        method = "tools/list"
      }
    elseif "initialize" == _exp_0 then
      message = {
        jsonrpc = "2.0",
        id = "init-" .. tostring(os.time()),
        method = "initialize",
        params = {
          protocolVersion = "2025-06-18",
          capabilities = { },
          clientInfo = {
            name = CLIENT_NAME,
            version = "1.0.0"
          }
        }
      }
    else
      server:skip_initialize()
      message = assert(json.decode(args.send_message))
    end
    local response = server:send_message(message)
    print(json.encode(response))
    return 
  end
  if args.skip_initialize or args.tool then
    server:skip_initialize()
  end
  return server:run_stdio()
end
return {
  run_cli = run_cli
}
