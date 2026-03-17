local build_parser, run_parsed_args
do
  local _obj_0 = require("lapis.mcp.cli")
  build_parser, run_parsed_args = _obj_0.build_parser, _obj_0.run_parsed_args
end
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
    return build_parser({
      name = "lapis mcp",
      description = "Run an MCP server over stdin/out that can communicate with details of Lapis app",
      setup_parser = function(parser)
        return parser:argument("server_module", "Name of the MCP server module to load", "lapis.mcp.lapis_server")
      end
    })
  end,
  function(self, args, lapis_args)
    local config = self:get_config(lapis_args.environment)
    local ServerClass = require(args.server_module)
    local server = ServerClass({
      debug = args.debug,
      app = find_lapis_application(config)
    })
    return run_parsed_args(server, args)
  end
}
