import McpServer from require "lapis.mcp.server"
json = require "cjson.safe"

types = require "lapis.validate.types"

class SomeServer extends McpServer
  @server_name: "some-mcp"
  @instructions: [[Just some random tools]]

  @add_tool {
    name: "set_title"
    description: "Set the title of an object"
    inputShape: types.shape {
      object_id: types.db_id
      path: types.limited_text 255
    }
  }, (params) =>
    "hello world"

SomeServer\run_cli!
