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
      _with_0:option("--send-message", "Send a message by name and exit (e.g. list_tools, server_info, or a tool name)")
      _with_0:option("--tool", "Immediately invoke a tool, print output and exit (e.g. routes, models, schema)")
      return _with_0
    end
  end,
  function(self, args, lapis_args)
    if args.hello then
      print("Hello from Lapis MCP!")
      return 
    end
    local config = self:get_config(lapis_args.environment)
    local app = find_lapis_application(config)
    local server = McpServer(app)
    if args.tool then
      local tool_name = args.tool
      local message = {
        type = "tool_call",
        id = "cmd-line-" .. tostring(os.time()),
        tool_call = {
          name = tool_name,
          parameters = { }
        }
      }
      local response = server:send_message(message)
      if response.type == "tool_result" and response.tool_result then
        print(json.encode(response.tool_result))
      else
        print(json.encode(response))
      end
      return 
    elseif args.send_message then
      local message_type = args.send_message
      local message = nil
      if message_type == "list_tools" then
        message = {
          type = "list_tools"
        }
      elseif message_type == "server_info" then
        print(json.encode(server:get_server_info()))
        return 
      else
        message = {
          type = "tool_call",
          id = "cmd-line-" .. tostring(os.time()),
          tool_call = {
            name = message_type,
            parameters = { }
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
