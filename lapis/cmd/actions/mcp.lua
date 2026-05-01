local build_parser, run_parsed_args
do
  local _obj_0 = require("lapis.mcp.cli")
  build_parser, run_parsed_args = _obj_0.build_parser, _obj_0.run_parsed_args
end
local find_lapis_application
find_lapis_application = function(config)
  local app_module = config and config.app_module or "app"
  local ok, app = pcall(require, app_module)
  if ok then
    return app
  end
  local lapis
  ok, lapis = pcall(require, "lapis")
  if ok then
    return lapis.Application()
  end
  return nil
end
return {
  argparser = function()
    return build_parser({
      name = "lapis mcp",
      description = "Run a Lua/MoonScript MCP server over stdin/stdout, with the current Lapis application injected as `app`",
      setup_parser = function(parser)
        return parser:argument("server_module", "Name of the MCP server module to load (e.g. lapis.mcp.lapis_server)")
      end
    })
  end,
  function(self, args, lapis_args)
    local ok, config = pcall(self.get_config, self, lapis_args.environment)
    if not (ok) then
      config = nil
    end
    local ServerClass = require(args.server_module)
    local server = ServerClass({
      debug = args.debug,
      app = find_lapis_application(config),
      config = config
    })
    return run_parsed_args(server, args)
  end
}
