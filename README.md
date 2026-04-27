# Lapis MCP

A libray for developing MCP servers or definining LLM tool calls in
Lua/MoonScript. Also contains a default MCP server for communicating with Lapis
web applications.

## Installation

```bash
luarocks install lapis-mcp
```

## Lapis MCP Usage

This library provides a `lapis` subcommand, `mcp`, which can be used to start
an MCP server tied to the Lapis application in the current directory.

```
lapis mcp
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

### Composing MCP Server Classes

Use `@include` to build one `McpServer` class from the tools defined on other
server classes. This lets you keep tool groups modular and then assemble a
combined server for a specific application.

```moonscript
class SharedFileTools extends McpServer
  @add_tool {
    name: "read"
    description: "Read a file"
    inputSchema: {
      type: "object"
      properties: {
        path: { type: "string" }
      }
      required: {"path"}
    }
  }, (params) =>
    assert(io.open(params.path))\read "*a"

class SharedProjectTools extends McpServer
  @add_tool {
    name: "status"
    description: "Return project status"
    inputSchema: {
      type: "object"
      properties: {}
      required: {}
    }
  }, =>
    {
      project: @get_server_name!
      ok: true
    }

class AppServer extends McpServer
  @server_name: "app-server"

  @include SharedProjectTools
  @include SharedFileTools, prefix: "fs_"

  @add_tool {
    name: "ping"
    description: "Health check"
    inputSchema: {
      type: "object"
      properties: {}
      required: {}
    }
  }, -> "pong"
```

In that example, `AppServer` exposes:

- `status` from `SharedProjectTools`
- `fs_read` from `SharedFileTools`
- `ping` defined locally

Notes about composition:

- `prefix` prepends to the imported tool name, so `read` becomes `fs_read`.
- Included tools are registered onto the receiving class, so they work with `find_tool`, `execute_tool`, adapters, and `tools/list` the same way as locally defined tools.
- Handlers run with the receiving server instance as `self`, so included tools can call methods like `@get_server_name!` on the composed server.
- Included classes contribute inherited tools too, not just tools defined directly on that class.
- `@include` raises an error if the final tool name already exists on the receiving server or from another include. Use `prefix` to avoid collisions.

Visibility management uses the final included tool name, so call
`hide_tool("fs_read")`, `unhide_tool("fs_read")`, or
`set_tool_visibility("fs_read", true)` when working with prefixed tools.

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

### Using Tool Adapters with LLM APIs

The `tool_adapter` modules let you take the tools defined on an `McpServer`
class and expose them directly to LLM APIs. Each adapter does two jobs:

- convert your MCP tool definitions into the provider's tool schema format
- take the provider's tool call response shape, execute the matching MCP tools,
  and build the provider-specific tool result messages to send back

This means you can define your tools once on your MCP server and reuse that same
tool collection both for MCP clients and for direct LLM API integrations.

Available adapters:

- `lapis.mcp.tool_adapter.openai`
- `lapis.mcp.tool_adapter.anthropic`
- `lapis.mcp.tool_adapter.gemini`

#### OpenAI

The OpenAI example below uses `lua-openai`:
https://github.com/leafo/lua-openai

```moonscript
import McpServer from require "lapis.mcp.server"
OpenAIToolAdapter = require "lapis.mcp.tool_adapter.openai"

class MathServer extends McpServer
  @add_tool {
    name: "add_numbers"
    description: "Add two numbers"
    inputSchema: {
      type: "object"
      properties: {
        a: { type: "number" }
        b: { type: "number" }
      }
      required: {"a", "b"}
    }
  }, (params) =>
    params.a + params.b

server = MathServer {}
adapter = OpenAIToolAdapter server

tools = adapter\to_tools!
-- Use directly as the OpenAI `tools` parameter

response = {
  tool_calls: {
    {
      id: "call_123"
      function: {
        name: "add_numbers"
        arguments: '{"a": 4, "b": 7}'
      }
    }
  }
}

messages = adapter\process_tool_calls response
-- Returns OpenAI `role: "tool"` messages ready to append back to the conversation
```

See [`examples/tool_adapter_example.moon`](https://github.com/leafo/lapis-mcp/blob/master/examples/tool_adapter_example.moon) for a complete OpenAI loop.

#### Anthropic

```moonscript
AnthropicToolAdapter = require "lapis.mcp.tool_adapter.anthropic"

server = MathServer {}
adapter = AnthropicToolAdapter server

tools = adapter\to_tools!
-- Each MCP tool becomes an Anthropic tool definition with `input_schema`

response = {
  role: "assistant"
  content: {
    {
      type: "tool_use"
      id: "toolu_123"
      name: "add_numbers"
      input: {
        a: 4
        b: 7
      }
    }
  }
}

messages = adapter\process_tool_calls response
-- Returns a single Anthropic `role: "user"` message containing `tool_result` blocks
```

#### Gemini

```moonscript
GeminiToolAdapter = require "lapis.mcp.tool_adapter.gemini"

server = MathServer {}
adapter = GeminiToolAdapter server

tools = adapter\to_tools!
-- Use directly as the Gemini `tools` request field.
-- The adapter wraps your MCP tools in `functionDeclarations`.

response = {
  candidates: {
    {
      content: {
        role: "model"
        parts: {
          {
            functionCall: {
              name: "add_numbers"
              args: {
                a: 4
                b: 7
              }
            }
          }
        }
      }
    }
  }
}

contents = adapter\process_tool_calls response
-- Returns Gemini request-ready contents:
-- 1. the original model content with `functionCall`
-- 2. a `role: "user"` message with `functionResponse` parts
```

#### What Gets Converted

Each adapter reads the enabled tools from your MCP server and converts:

- `name`
- `description`
- `inputSchema`

into the provider's tool schema format.

The tool handler implementation stays on the MCP server. When the model asks to
call a tool, the adapter:

1. extracts the provider-specific tool call payload
2. calls `server:execute_tool(...)`
3. serializes the result or returned `nil, err`
4. builds the provider-specific tool result message shape

Unexpected tool implementation exceptions are not turned into model-visible
errors. They still fail fast so the tool implementation can be fixed.

### Running Your Server

This library supports two transport styles today:

- stdio, by running the server loop directly
- HTTP, by mounting an MCP route in a Lapis application

For stdio transport there are two interfaces to starting the server:

- `mcp_server:run_stdio()` - Instance method that immediately starts the server loop over stdin and writes to stdout. Input must follow the MCP protocol to be handled correctly.
- `McpServer:run_cli()` - Class method that will instantiate your MCP server with argparse based configuration and debug tools, then immediately starts the stdio loop via `run_stdio`. Use the `--help` command to learn more about what's available.

#### Programatic Execution

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

#### CLI Execution

The `run_cli` class method that exposes the server of stdio transport with argument based configuration.

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

The `run_cli` method provides several useful command-line options. You can view these by passiing `--help` to your CLI program.

- `--help` - Show all CLI options
- `--debug` - Enable debug logging to stderr
- `--skip-initialize` / `--skip-init` - Skip the initialize stage and listen for messages immediately
- `--dump-tools <adapter>` - Print tool adapter JSON for `openai`, `anthropic`, or `gemini`, then exit
- `--tool <tool_name>` - Immediately invoke a specific tool, print output and exit
- `--tool-argument <json>` / `--arg <json>` - Pass arguments to the tool (in JSON format)
- `--send-message <message>` - Send a raw message and exit
- `--tool-prefix <prefix>` - Prefix to prepend to all tool names
- `--instructions <text>` - Set the server instructions

#### CLI Examples

When using `run_cli` in a script called `my_server.lua` the following are examples of argument usage:

```bash
# Run server normally
./my_server.lua

# Run with debug logging
./my_server.lua --debug

# Print OpenAI tool definitions for all enabled tools
./my_server.lua --dump-tools openai

# Test a specific tool
./my_server.lua --tool list_files --arg '{"path": "/tmp"}'

# Send a raw MCP message
./my_server.lua --send-message tools/list

# Send the initialize message
./my_server.lua --send-message initialize

# Send a custom JSON message
./my_server.lua --send-message '{"jsonrpc":"2.0","id":"test","method":"tools/call","params":{"name":"hello","arguments":{"name":"World"}}}'
```

### Running Over HTTP

Use `lapis.mcp.http.mcp_handler` to mount an MCP endpoint in a Lapis
application. The handler creates a fresh `McpServer` instance for each request,
so HTTP mode is stateless unless you restore state yourself.

#### Lua

```lua
local lapis = require("lapis")
local McpServer = require("lapis.mcp.server").McpServer
local mcp_handler = require("lapis.mcp.http").mcp_handler

local MyMcpServer = McpServer:extend("MyMcpServer", {
  server_name = "my-http-server"
})

MyMcpServer:add_tool({
  name = "hello",
  description = "Returns a greeting",
  inputSchema = {
    type = "object",
    properties = {},
    required = {}
  }
}, function(self, params)
  return "world"
end)

local app = lapis.Application()

app:match("/mcp", mcp_handler(MyMcpServer, {
  allowed_origins = {
    "https://example.com"
  }
}))

return app
```

#### MoonScript

```moonscript
lapis = require "lapis"

import McpServer from require "lapis.mcp.server"
import mcp_handler from require "lapis.mcp.http"

class MyMcpServer extends McpServer
  @server_name: "my-http-server"

  @add_tool {
    name: "hello"
    description: "Returns a greeting"
    inputSchema: {
      type: "object"
      properties: {}
      required: {}
    }
  }, (params) =>
    "world"

class App extends lapis.Application
  "/mcp": mcp_handler MyMcpServer, {
    allowed_origins: {
      "https://example.com"
    }
  }
```

HTTP mode accepts `POST` requests for MCP messages and `OPTIONS` requests for
CORS preflight. Clients should send an `Accept` header that includes both
`application/json` and `text/event-stream`.

#### HTTP Handler Options

The second argument to `mcp_handler(ServerClass, opts)` accepts these options:

- `allowed_origins` - Either `"*"` or an array of allowed origins. If an `Origin` header is present and not allowed, the handler returns `403`.
- `server_options` - Passed to `ServerClass(...)` each time a request creates a new server instance.
- `load_session(req, server)` - Optional callback invoked after the server instance is created. Use this to restore per-session state, customize visibility, or apply authentication-derived state to the server.
- `create_session_id(req, server)` - Optional callback invoked for `initialize` requests. If it returns a value, it is written to the `Mcp-Session-Id` response header.

Because HTTP mode is stateless, any authentication or session persistence is up
to the surrounding Lapis application and these callbacks. For example, you can
perform your own auth checks before the route runs, then use `load_session` to
restore the server state associated with the current request.

#### HTTP serve

For the common case of serving a single MCP server class as a standalone Lapis
app, `lapis.mcp.http` provides a `serve(server_module, opts)` helper that
mirrors `lapis.serve`.

`server_module` is either a Lua module name that returns an MCP server class or
the class itself. The helper builds an anonymous Lapis application, mounts
`mcp_handler(ServerClass, opts)` at `opts.path` (default `"/"`), and hands the
app off to `lapis.serve`. Any other keys in `opts` (`allowed_origins`,
`server_options`, `load_session`, `create_session_id`) are forwarded to
`mcp_handler`.


With OpenResty: 

```nginx
location / {
  content_by_lua_block {
    require("lapis.mcp.http").serve("my.mcp.server")
  }
}
```

With golapis:

```sh
golapis --http -e 'require("lapis.mcp.http").serve("my.mcp.server")' --ngx
```

The MCP handler internally validates `Origin` and `Accept` headers and only
responds to `POST` (plus `OPTIONS` for CORS preflight), so it is safe to mount
at the root of a location block. If you would rather expose it under a path,
move the location (`location /mcp { ... }`) or pass `{path = "/mcp"}` to
`serve` and front it with a broader `location /`.

## License

MIT
