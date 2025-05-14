local McpServer, find_lapis_application
do
  local _obj_0 = require("lapis.mcp.server")
  McpServer, find_lapis_application = _obj_0.McpServer, _obj_0.find_lapis_application
end
return {
  argparser = function()
    do
      local _with_0 = require("argparse")("lapis mcp", "Run an MCP server over stdin/out that can communicate with details of Lapis app")
      _with_0:flag("--hello", "Print a hello message and exit")
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
    return server:run()
  end
}
