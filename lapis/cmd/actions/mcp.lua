local json = require("cjson.safe")
local CLIENT_NAME = "lapis-mcp-cli"
local find_lapis_application
find_lapis_application = function(config)
  local app_module = "app"
  if config and config.app_module then
    app_module = config.app_module
  end
  local ok, app = pcall(require, app_module)
  if ok then
    return app
  end
  local lapis
  ok, lapis = pcall(require, "lapis")
  if ok then
    return lapis.Application()
  end
  return error("Could not find a Lapis application")
end
return {
  argparser = function()
    do
      local _with_0 = require("argparse")("lapis mcp", "Run an MCP server over stdin/out that can communicate with details of Lapis app")
      _with_0:argument("server_module", "Name of the MCP server module to load", "lapis.mcp.lapis_server")
      _with_0:option("--send-message", "Send a raw message by name and exit (e.g. tools/list, resources/list, initialize or a JSON object)")
      _with_0:option("--tool", "Immediately invoke a tool, print output and exit")
      _with_0:option("--tool-argument --arg", "Argument object to pass for tool call (in JSON format)")
      _with_0:option("--resource", "Immediately fetch a resource by URI, print output and exit")
      _with_0:flag("--debug", "Enable debug logging to stderr")
      _with_0:flag("--skip-initialize --skip-init", "Skip the initialize stage and listen for messages immediately")
      return _with_0
    end
  end,
  function(self, args, lapis_args)
    local config = self:get_config(lapis_args.environment)
    local ServerClass = require(args.server_module)
    local server = ServerClass({
      debug = args.debug,
      app = find_lapis_application(config)
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
    if args.resource then
      server:skip_initialize()
      local resource_uri = args.resource
      local message = {
        jsonrpc = "2.0",
        id = "cmd-line-" .. tostring(os.time()),
        method = "resources/read",
        params = {
          uri = resource_uri
        }
      }
      local response = server:send_message(message)
      if response.result and response.result.contents then
        print(json.encode(response.result.contents))
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
      elseif "resources/list" == _exp_0 then
        server:skip_initialize()
        message = {
          jsonrpc = "2.0",
          id = "cmd-line-" .. tostring(os.time()),
          method = "resources/list"
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
    if args.skip_initialize or args.tool or args.resource then
      server:skip_initialize()
    end
    return server:run_stdio()
  end
}
