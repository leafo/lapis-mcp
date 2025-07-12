# Lapis MCP

A libray for developing MCP servers in Lua/MoonScript. Also contains a default
MCP server for communicating with Lapis web applications.


## Installation

```bash
luarocks install lapis-mcp
```

## Lapis MCP Usage

This library provides a `lapis` subcommand, `mcp`, which can be used to start
an MCP server tied to the Lapis application in the current directory.

```
lapis _ mcp
```

### Available Tools

- **list_routes** - Lists all named routes in the Lapis application
- **list_models** - Lists all database models defined in the application (classes that represent database tables)
- **schema** - Shows the SQL schema for a specific database model (requires model_name parameter)

The server automatically discovers routes from your application's router and models from the `models/` directory.

## Creating Your Own MCP Server

This project provides a reusable `McpServer` base class that you can extend to create your own MCP servers. Here's how to implement your own:

### Key Features

- **Inheritance-based tool registration** - Tools are inherited from parent classes, with the ability for subclasses to override tools by name
- **Error handling** - Both exceptions and explicit error returns are handled
- **Debug logging** - Optional debug output with colored console logging
- **MCP protocol compliance** - Follows the MCP 2025-06-18 specification

### Full Example: File System MCP Server

#### Lua

```lua
local McpServer = require("lapis.mcp.server").McpServer
local json = require("cjson.safe")

local FileSystemMcpServer = McpServer:extend("FileSystemMcpServer", {
  server_name = "filesystem-mcp",
  instructions = "Tools to interact with the local filesystem"
})

FileSystemMcpServer:add_tool({
  name = "list_files",
  description = "Lists files in a directory", 
  inputSchema = {
    type = "object",
    properties = {
      path = {
        type = "string",
        description = "Directory path to list",
        default = "."
      }
    },
    -- Note: must serialize to an empty array in JSON
    required = setmetatable({}, json.array_mt)
  }
}, function(self, params)
  local path = params.path or "."
  local files = {}
  
  for file in io.popen("ls -la '" .. path .. "'"):lines() do
    table.insert(files, file)
  end
  
  return files
end)

-- Usage
local server = FileSystemMcpServer({
  debug = true
})
server:run_stdio()
```

#### MoonScript

```moonscript
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
```

### Basic Structure

#### Lua

```lua
-- Import the base class
local McpServer = require("lapis.mcp.server").McpServer

-- Create your custom server class
local MyMcpServer = McpServer:extend("MyMcpServer", {
  server_name = "my-mcp-server",
  server_version = "1.0.0", 
  server_vendor = "Your Company",
  instructions = "Your server description here"
})

-- Usage
local server = MyMcpServer({debug = true})
server:run_stdio()
```

#### MoonScript

```moonscript
-- Import the base class
import McpServer from require "lapis.mcp.server"

-- Create your custom server class
class MyMcpServer extends McpServer
  @server_name: "my-mcp-server"
  @server_version: "1.0.0"
  @server_vendor: "Your Company"
  @instructions: [[Your server description here]]

  new: (options = {}) =>
    super(options)
    -- Initialize your server-specific state
```

### Adding Tools

Use the `@add_tool` class method to register tools:

#### Lua

```lua
-- Add a simple tool
MyMcpServer:add_tool({
  name = "hello",
  description = "Returns a greeting message",
  inputSchema = {
    type = "object",
    properties = {
      name = {
        type = "string",
        description = "Name to greet"
      }
    },
    required = {"name"}
  },
  annotations = {
    title = "Say Hello"
  }
}, function(self, params)
  return "Hello, " .. params.name .. "!"
end)

-- Add a tool with no parameters
MyMcpServer:add_tool({
  name = "status",
  description = "Returns server status",
  inputSchema = {
    type = "object",
    properties = {},
    required = setmetatable({}, json.array_mt)  -- Empty array for no required params
  },
  annotations = {
    title = "Server Status"
  }
}, function(self, params)
  return {
    status = "running",
    timestamp = os.time()
  }
end)
```

#### MoonScript

```moonscript
-- Add a simple tool
@add_tool {
  name: "hello"
  description: "Returns a greeting message"
  inputSchema: {
    type: "object"
    properties: {
      name: {
        type: "string"
        description: "Name to greet"
      }
    }
    required: {"name"}
  }
  annotations: {
    title: "Say Hello"
  }
}, (params) =>
  "Hello, #{params.name}!"

-- Add a tool with no parameters
@add_tool {
  name: "status"
  description: "Returns server status"
  inputSchema: {
    type: "object"
    properties: {}
    required: setmetatable {}, json.array_mt  -- Empty array for no required params
  }
  annotations: {
    title: "Server Status"
  }
}, (params) =>
  {
    status: "running"
    timestamp: os.time()
  }
```

### Error Handling

Tools can return errors using the `nil, error_message` pattern:

#### Lua

```lua
MyMcpServer:add_tool({
  name = "divide",
  description = "Divides two numbers",
  inputSchema = {
    type = "object",
    properties = {
      a = { type = "number" },
      b = { type = "number" }
    },
    required = {"a", "b"}
  }
}, function(self, params)
  if params.b == 0 then
    return nil, "Division by zero is not allowed"
  end
  
  return params.a / params.b
end)
```

#### MoonScript

```moonscript
@add_tool {
  name: "divide"
  description: "Divides two numbers"
  inputSchema: {
    type: "object"
    properties: {
      a: { type: "number" }
      b: { type: "number" }
    }
    required: {"a", "b"}
  }
}, (params) =>
  if params.b == 0
    return nil, "Division by zero is not allowed"

  params.a / params.b
```

### Running Your Server

You can run your MCP server in two ways: directly using `run_stdio()` or with a CLI interface using the `run_cli` class method.

#### Direct Execution

##### Lua

```lua
-- Create and run your server
local server = MyMcpServer({debug = true})
server:run_stdio()
```

##### MoonScript

```moonscript
-- Create and run your server
server = MyMcpServer({debug: true})
server\run_stdio()
```

#### CLI Interface with `run_cli`

The `run_cli` class method provides a command-line interface with argument parsing for your MCP server:

##### Lua

```lua
-- Run your server with CLI interface
MyMcpServer:run_cli({
  name = "my-custom-server"  -- Optional: override the CLI program name
})
```

##### MoonScript

```moonscript
-- Run your server with CLI interface
MyMcpServer\run_cli {
  name: "my-custom-server"  -- Optional: override the CLI program name
}
```

#### CLI Options

The `run_cli` method provides several useful command-line options:


- `--help` - Show all CLI options
- `--debug` - Enable debug logging to stderr
- `--skip-initialize` / `--skip-init` - Skip the initialize stage and listen for messages immediately
- `--tool <tool_name>` - Immediately invoke a specific tool, print output and exit
- `--tool-argument <json>` / `--arg <json>` - Pass arguments to the tool (in JSON format)
- `--send-message <message>` - Send a raw message and exit

#### Examples

```bash
# Run server normally
./my_server.lua

# Run with debug logging
./my_server.lua --debug

# Test a specific tool
./my_server.lua --tool list_files --arg '{"path": "/tmp"}'

# Send a raw MCP message
./my_server.lua --send-message tools/list

# Send the initialize message
./my_server.lua --send-message initialize

# Send a custom JSON message
./my_server.lua --send-message '{"jsonrpc":"2.0","id":"test","method":"tools/call","params":{"name":"hello","arguments":{"name":"World"}}}'
```

## License

MIT
