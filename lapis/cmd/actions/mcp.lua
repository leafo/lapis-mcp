local McpServer, find_lapis_application
do
  local _obj_0 = require("lapis.mcp.server")
  McpServer, find_lapis_application = _obj_0.McpServer, _obj_0.find_lapis_application
end
local json = require("cjson")
return {
  argparser = function()
    do
      local _with_0 = require("argparse")("lapis mcp", "Run an MCP server over stdin/out that can communicate with details of Lapis app")
      _with_0:option("--send-message", "Send a raw message by name and exit (e.g. tools/list, initialize)")
      _with_0:option("--tool", "Immediately invoke a tool, print output and exit (e.g. routes, models, schema)")
      return _with_0
    end
  end,
  function(self, args, lapis_args)
    local config = self:get_config(lapis_args.environment)
    local app = find_lapis_application(config)
    local server = McpServer(app)
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
    return server:run()
  end
}
