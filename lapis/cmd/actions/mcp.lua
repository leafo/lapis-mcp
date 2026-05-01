local build_parser, run_parsed_args
do
  local _obj_0 = require("lapis.mcp.cli")
  build_parser, run_parsed_args = _obj_0.build_parser, _obj_0.run_parsed_args
end
return {
  argparser = function()
    return build_parser({
      name = "lapis mcp",
      description = "Load a Lua/MoonScript MCP server module and run it over stdin/stdout",
      setup_parser = function(parser)
        return parser:argument("server_module", "Name of the MCP server module to load (e.g. lapis.mcp.lapis_server)")
      end
    })
  end,
  function(self, args, lapis_args)
    local ServerClass = require(args.server_module)
    local server = ServerClass({
      debug = args.debug
    })
    return run_parsed_args(server, args)
  end
}
