import McpServer from require "lapis.mcp.server"
json = require "cjson.safe"

class FileSystemMcpServer extends McpServer
  @server_name: "filesystem-mcp"
  @instructions: [[Tools to interact with the local filesystem]]

  @add_tool {
    name: "list_files"
    description: "Lists files in a directory"
    inputSchema: {
      type: "object"
      properties: {
        path: {
          type: "string"
          description: "Directory path to list"
          default: "."
        }
      }
      -- Note: must serialize to an empty array in JSON
      required: setmetatable {}, json.array_mt
    }
  }, (params) =>
    path = params.path or "."
    files = {}

    for file in io.popen("ls -la '#{path}'")\lines()
      table.insert(files, file)

    files

-- Usage
server = FileSystemMcpServer {
  debug: true
}
server\run_stdio!
