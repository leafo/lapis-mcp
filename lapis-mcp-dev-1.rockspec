package = "lapis-mcp"
version = "dev-1"

source = {
  url = "git+https://github.com/leafo/lapis-mcp.git"
}

description = {
  summary = "Model Context Protocol (MCP) server for the Lapis web framework",
  detailed = [[
    A base class and toolset for developing Model Context Protocol (MCP)
    servers in Lua/Moonscript. Includes MCP server for the Lapis web framework
    that provides information about the current Lapis application to AI agents.
  ]],
  homepage = "https://github.com/leafo/lapis-mcp",
  license = "MIT"
}

dependencies = {
  "lua >= 5.1",
  "lapis"
}

build = {
  type = "builtin",
  modules = {
    ["lapis.cmd.actions.mcp"] = "lapis/cmd/actions/mcp.lua",
    ["lapis.mcp.server"] = "lapis/mcp/server.lua",
    ["lapis.mcp.cli"] = "lapis/mcp/cli.lua",
    ["lapis.mcp.lapis_server"] = "lapis/mcp/lapis_server.lua"
  }
}
