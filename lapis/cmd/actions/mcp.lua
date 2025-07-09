local McpServer
McpServer = require("lapis.mcp.server").McpServer
local json = require("cjson")
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
      _with_0:option("--send-message", "Send a raw message by name and exit (e.g. tools/list, initialize)")
      _with_0:option("--tool", "Immediately invoke a tool, print output and exit (e.g. routes, models, schema)")
      _with_0:flag("--debug", "Enable debug logging to stderr")
      return _with_0
    end
  end,
  function(self, args, lapis_args)
    local config = self:get_config(lapis_args.environment)
    local app = find_lapis_application(config)
    local server = McpServer(app, args.debug)
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
            name = "lapis-mcp-cli",
            version = "0.1.0"
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
            name = "lapis-mcp-cli",
            version = "0.1.0"
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
}
