# Lapis MCP

A library for building Model Context Protocol (MCP) servers and defining LLM
tool calls in Lua/MoonScript. Provides a base class for authoring servers,
adapters that expose those servers' tools to OpenAI/Anthropic/Gemini APIs,
stdio and HTTP transports, an OAuth shim for protected endpoints, and a `lapis`
subcommand for running a server inside a Lapis project. A small bundled server
for introspecting Lapis applications is included as a starting point.

## Installation

```bash
luarocks install lapis-mcp
```

## Creating Your Own MCP Server

This project provides a reusable `McpServer` base class that you can extend to
create your own MCP servers. Here's how to implement your own:

### Full Example: File System MCP Server

#### Lua

```lua
local McpServer = require("lapis.mcp.server").McpServer
local json = require("cjson.safe")

local FileSystemMcpServer = McpServer:extend("FileSystemMcpServer", {
  server_name = "filesystem-mcp",
  instructions = "Tools to interact with the local filesystem"

  -- optional fields:
  -- server_version = "1.0.0", 
  -- server_vendor = "Your Company",
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

  -- optional fields:
  -- @server_version: "1.0.0"
  -- @server_vendor: "Your Company"

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

#### Tool Handler Semantics

Every tool registered with `@add_tool` follows the same contract:

- Handlers are called with the `McpServer` instance as `self` and a single `params` argument (`function(self, params)` in Lua, `(params) =>` in MoonScript). `params` is the JSON-decoded `arguments` table from the tool call.
- A returned string becomes a single text content block. Any other return value (table, array, number, boolean) is JSON-encoded into a single text block. If the tool declares an `outputSchema` and the handler returns a table, that table is also attached as `structuredContent` on the response.
- Return `nil, error_message` to signal a tool error. The error string is sent back to the client as an MCP error result (`isError: true`). Uncaught exceptions are not converted into tool errors and will fail the request loudly so that bugs are visible.

#### Defining Input Schemas with `inputShape`

Writing `inputSchema` by hand as a JSON-schema-shaped Lua table is verbose and
gives you no runtime validation: you have to check required fields and types
yourself inside the handler. As an alternative, pass an `inputShape` built from
[tableshape](https://github.com/leafo/tableshape) types and the server will:

1. Compile the shape into a JSON Schema and use that as the tool's `inputSchema` for `tools/list` and adapter output.
2. Validate and transform the incoming `arguments` against the shape on every `tools/call`. If validation fails, the call returns an MCP error result (`isError: true`) with the tableshape error message and the handler is never invoked.
3. Pass the transformed value (with defaults filled in and any tableshape transformations applied) to your handler as `params`.

##### MoonScript

```moonscript
import types from require "tableshape"

@add_tool {
  name: "set_title"
  description: "Set the title of an object"
  inputShape: types.shape {
    object_id: types.number
    title: types.string
    published: types.boolean\is_optional!
  }
}, (params) =>
  -- params.object_id and params.title are guaranteed to be the right types
  -- params.published is either a boolean or nil
  update_title params.object_id, params.title, params.published
  "ok"
```

##### Lua

```lua
local types = require("tableshape").types

MyMcpServer:add_tool({
  name = "set_title",
  description = "Set the title of an object",
  inputShape = types.shape({
    object_id = types.number,
    title = types.string,
    published = types.boolean:is_optional()
  })
}, function(self, params)
  update_title(params.object_id, params.title, params.published)
  return "ok"
end)
```

Notes:

- `inputShape` and `inputSchema` are mutually exclusive in practice. If both are present, `inputShape` wins and the manually written `inputSchema` is ignored.
- Use `types.shape` (a closed object) for the top-level schema. `types.shape` translates to `additionalProperties: false`, which matches what MCP clients expect.
- Add a `description` to any inner type with `types.string\describe("...")` to surface a per-field description in the generated JSON Schema; the LLM sees these descriptions when deciding how to fill arguments.
- `outputShape` works the same way for declaring the structured-output schema. When set, the generated JSON Schema is exposed as the tool's `outputSchema`, and a handler returning a table will have that table attached as `structuredContent`.

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
- `exclude` takes a list of source tool names (before `prefix` is applied) to skip, eg. `@include SharedFileTools, exclude: {"read"}`. Naming a tool the source doesn't have raises an error.
- `group` sets `tool.group` on every included tool, overriding any group the source tool had. `@add_tool` also accepts `group`. It is server-side metadata for organizing tools (eg. toggling a set of tools in a UI) and is not sent to MCP clients.
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

OpenAI tool schemas preserve the original MCP schema shape by default. To emit
schemas with OpenAI strict mode enabled, pass `strict: true`:

```moonscript
adapter = OpenAIToolAdapter server, strict: true
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

#### Programmatic Execution

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
- `--list-tools` - List all enabled tool names (one per line) and exit
- `--dump-tools <adapter>` / `--tool-schema <adapter>` - Print tool adapter JSON for `openai`, `anthropic`, or `gemini`, then exit. Combine with `--tool <name>` to dump just one tool's schema.
- `--tool <tool_name>` - Immediately invoke a specific tool, print output and exit
- `--tool-argument <json>` / `--arg <json>` - Pass arguments to the tool (in JSON format)
- `--resource <uri>` - Immediately fetch a resource by URI, print output and exit
- `--send-message <message>` - Send a raw message and exit
- `--tag <tag>` - Only expose tools matching this tag (can be specified multiple times)
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

# List the names of all enabled tools
./my_server.lua --list-tools

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

Use `lapis.mcp.http.McpHttpRouter` to mount one or more MCP endpoints in a
Lapis application. The router installs the MCP route and any OAuth companion
routes together, so multi-tenant apps cannot accidentally forget shared
metadata or token routes. Each handler creates a fresh `McpServer` instance for
each request, so HTTP mode is stateless unless you restore state yourself.

#### Lua

```lua
local lapis = require("lapis")
local McpServer = require("lapis.mcp.server").McpServer
local McpHttpRouter = require("lapis.mcp.http").McpHttpRouter

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
local router = McpHttpRouter()

router:mount("/mcp", MyMcpServer, {
  allowed_origins = {
    "https://example.com"
  }
})
router:install(app)

return app
```

#### MoonScript

```moonscript
lapis = require "lapis"

import McpServer from require "lapis.mcp.server"
import McpHttpRouter from require "lapis.mcp.http"

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

router = McpHttpRouter!
router\mount "/mcp", MyMcpServer, {
  allowed_origins: {
    "https://example.com"
  }
}

class App extends lapis.Application

router\install App
```

HTTP mode accepts `POST` requests for MCP messages and `OPTIONS` requests for
CORS preflight. Clients should send an `Accept` header that includes both
`application/json` and `text/event-stream`.

This is a JSON-only profile of the Streamable HTTP transport: the server
always responds with `application/json` and never upgrades to SSE, so
server-initiated messages (progress notifications, sampling, etc.) are not
delivered. `GET` and `DELETE` on the endpoint return `405`. This is
sufficient for tool-only servers; if your tools need to stream progress
back to the client, you'll want a fuller transport. For the same reason, the
server's capabilities are reported with `listChanged: false` and
`subscribe: false` over HTTP, since those notifications have no way to reach
the client.

Requests with an `MCP-Protocol-Version` header naming a version the server
doesn't support are rejected with `400`. The supported versions are the
server's own `protocol_version` plus the class's `@supported_protocol_versions`
(by default `2025-11-25`, `2025-06-18`, `2025-03-26`, `2024-11-05` and
`2024-10-07`), the same list used to negotiate the version in `initialize`.
Requests without the header, and `initialize` requests, are always accepted.

#### HTTP Handler Options

The third argument to `router:mount(path, ServerClass, opts)` accepts these
options:

- `allowed_origins` - Either `"*"` or an array of allowed origins. If an `Origin` header is present and not allowed, the handler returns `403`.
- `server_options` - Passed to `ServerClass(...)` each time a request creates a new server instance.
- `load_session(req, server)` - Optional callback invoked after the server instance is created, on every request except CORS preflight. Use this to restore per-session state, customize visibility, or apply authentication-derived state to the server. `server.auth` is already set when it runs (see below).
- `create_session_id(req, server)` - Optional callback invoked for `initialize` requests. If it returns a value, it is written to the `Mcp-Session-Id` response header.
- `bearer_token` - Optional static bearer token required on MCP endpoint requests; see [Authenticating with a Static Bearer Token](#authenticating-with-a-static-bearer-token).
- `oauth` - Optional table that turns on OAuth for this mount: either users of your site log in and approve each client (see [Authenticating with OAuth (User Login)](#authenticating-with-oauth-user-login)), or a static service token (see [Authenticating with OAuth (Service Tokens)](#authenticating-with-oauth-service-tokens)).

Because HTTP mode is stateless, any authentication or session persistence is up
to the surrounding Lapis application and these callbacks. For example, you can
perform your own auth checks before the route runs, then use `load_session` to
restore the server state associated with the current request.
`bearer_token` and `oauth` are mutually exclusive.

Each server instance's `server.auth` describes how the request was
authorized, so `load_session` and tool handlers can tell. It is `nil` on a
mount without `bearer_token` or `oauth`, `{static = true}` when the request
presented the static bearer token or the OAuth shim's service token, and
`{grant = grant}` when it presented a user's access token (see
[Authenticating with OAuth (User Login)](#authenticating-with-oauth-user-login)).

#### Multiple HTTP MCP Apps

Register each MCP endpoint with one router, then install it into the Lapis
application:

```moonscript
import McpHttpRouter from require "lapis.mcp.http"

router = McpHttpRouter!
router\mount "/mcp-one", TenantOneServer, {
  oauth: {
    client_id: "tenant-one"
    client_secret: "..."
  }
  -- server_options: ...
}

router\mount "/mcp-two", TenantTwoServer, {
  oauth: {
    client_id: "tenant-two"
    client_secret: "..."
  }
  -- server_options: ...
}

router\install App
```

OAuth routes are always scoped by mount path:

- `GET /.well-known/oauth-protected-resource/mcp-one`
- `GET /.well-known/oauth-authorization-server/mcp-one`
- `GET /mcp-one/oauth/authorize`
- `POST /mcp-one/oauth/token`

The router raises an error during `install` if two MCP mounts or generated
OAuth routes would collide.

To keep the MCP routes in their own sub-application, `router\application!`
returns a new `lapis.Application` subclass with the routes installed, ready
for `@include`. The including app's `before_filter`s run on the MCP and OAuth
routes, like any other included routes. Don't include it with a `path`
prefix: the OAuth metadata URLs are built from the mount path, and the
`.well-known` routes must stay at the site root. Put any prefix in the mount
path instead.

```moonscript
-- applications/mcp.moon
import McpHttpRouter from require "lapis.mcp.http"

McpHttpRouter!\mount("/mcp", "my.mcp.server", {
  -- ...
})\application!
```

```moonscript
-- app.moon
class App extends lapis.Application
  @include "applications.mcp"
```

#### HTTP serve

For the common case of serving a single MCP server class as a standalone Lapis
app, `lapis.mcp.http` provides a `serve(server_module, opts)` helper that
mirrors `lapis.serve`.

`server_module` is either a Lua module name that returns an MCP server class or
the class itself. The helper builds an anonymous Lapis application, mounts the
server through `McpHttpRouter` at `opts.path` (default `"/"`), and hands the app
off to `lapis.serve`. The remaining keys in `opts` (`allowed_origins`,
`server_options`, `load_session`, `create_session_id`, `bearer_token`, `oauth`)
are forwarded to the mount.


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

#### Authenticating with a Static Bearer Token

For clients that can send a pre-shared token directly, pass `bearer_token` in
the options to `router:mount` or `serve`. The MCP endpoint requires
`Authorization: Bearer <token>` on every non-`OPTIONS` request and returns
`401` with `WWW-Authenticate: Bearer realm="mcp"` when the header is missing or
invalid.

```moonscript
router\mount "/mcp", MyMcpServer, {
  bearer_token: "your-shared-secret"
}
```

Or, for the standalone `serve` case:

```nginx
location / {
  content_by_lua_block {
    require("lapis.mcp.http").serve("my.mcp.server", {
      bearer_token = "your-shared-secret"
    })
  }
}
```

This mode does not install OAuth discovery, authorization, or token routes. Use
`oauth` instead when a client expects an OAuth authorization flow.

#### Authenticating with OAuth (Service Tokens)

To make a remote MCP server compatible with Claude.ai's custom connectors (or
any client that expects OAuth-protected MCP endpoints), pass `oauth` in the
options to `router:mount` (or `serve`) to install a minimal OAuth shim that
gates access behind a static service token. There is no real login flow. The
shim just satisfies the OAuth protocol surface so the client can complete an
authorization round-trip and obtain a bearer token.

When a mount has `oauth`, the router registers these routes alongside the MCP
endpoint, scoped to the mount path:

- `GET /.well-known/oauth-protected-resource{mount_path}` (RFC 9728)
- `GET /.well-known/oauth-authorization-server{mount_path}` (RFC 8414)
- `GET {mount_path}/oauth/authorize`
- `POST {mount_path}/oauth/token`

The MCP endpoint requires `Authorization: Bearer <token>` and returns 401 with
a `WWW-Authenticate` header pointing at the resource metadata when missing or
invalid. Clients discover the authorization server, run the
`authorization_code` flow with PKCE (auto-approved with no UI), and exchange
the resulting code for an access token at `{mount_path}/oauth/token`. PKCE is
required and only the `S256` method is accepted, as required by OAuth 2.1 and
the MCP specification. The authorization redirect includes the `iss` parameter
([RFC 9207](https://datatracker.ietf.org/doc/html/rfc9207)) so clients can
verify which server issued the code. Once the client and `redirect_uri` are
validated (a `redirect_uri` containing a `#` fragment is rejected), authorize
errors such as a missing PKCE challenge are sent back to the client as an
`error` redirect with `state` and `iss`; earlier errors are shown directly as
a `400`. The `client_credentials` grant is also
supported and does not use PKCE. The token endpoint accepts client credentials
either as POST body parameters (`client_secret_post`) or as an
`Authorization: Basic` header (`client_secret_basic`). Auth codes are
stateless HMAC-signed payloads using `client_secret`, so no storage is
required between the `/authorize` and `/token` requests. Because codes aren't
stored, a code can be redeemed more than once within its 10 minute lifetime;
each redemption still needs the client secret and PKCE verifier, and returns
the same static token.

Direct router usage:

```moonscript
router\mount "/mcp", MyMcpServer, {
  oauth: {
    client_id: "claude-connector"
    client_secret: "your-shared-secret"
  }
}
```

Or, for the standalone `serve` case, under OpenResty:

```nginx
location / {
  content_by_lua_block {
    require("lapis.mcp.http").serve("my.mcp.server", {
      oauth = {
        client_id = "claude-connector",
        client_secret = "your-shared-secret"
        -- access_token = "...",                  -- defaults to client_secret
        -- access_token_ttl = 3600,
        -- public_base_url = "https://you.example.com", -- derived from request if omitted
        -- issuer = "https://you.example.com/mcp", -- defaults to public_base_url plus mount path
      }
    })
  }
}
```

In Claude's "Add custom connector" dialog, paste your server URL into
"Remote MCP server URL", expand "Advanced settings", and enter the same values
for "OAuth Client ID" and "OAuth Client Secret". The shim issues the
configured `access_token` to Claude, which sends it back as
`Authorization: Bearer ...` on every MCP request.

##### OAuth Options

- `client_id` (required): must match what the client sends.
- `client_secret` (required): verified at the token endpoint and used as the HMAC key for stateless auth codes.
- `access_token` (optional): the bearer token returned to the client and accepted on the MCP endpoint. Defaults to `client_secret`.
- `access_token_ttl` (optional): `expires_in` returned at the token endpoint. Defaults to `3600`.
- `allowed_redirect_uris` (optional): array of redirect URIs the authorize endpoint may redirect to. When set, any other `redirect_uri` is rejected with `400`. Loopback URIs (`http://localhost`, `http://127.0.0.1`, `http://[::1]`) match on any port, as native clients pick a port at random. When omitted, any `redirect_uri` is accepted.
- `public_base_url` (optional): public base URL used to derive metadata URLs, issuer, and resource when those values are not explicitly configured. Defaults to the request `Host` (and `X-Forwarded-Proto`/`X-Forwarded-Host`) when omitted.
- `issuer` (optional): issuer URL exposed in the metadata documents. Defaults to `public_base_url` joined with the MCP mount path.
- `resource` (optional): resource URL exposed in the protected-resource metadata. Defaults to `public_base_url` joined with the MCP mount path (e.g. `https://host/mcp` when mounted at `/mcp`), matching the default `issuer`.

Because this is a service-token shim and not real user authentication, anyone
with the configured `client_secret` (or `access_token`) can call the MCP
server. Always serve over HTTPS, treat the secret like an API key, and rotate
by updating the `oauth` table and restarting. If you need real user identity,
use [user login](#authenticating-with-oauth-user-login) instead.

#### Authenticating with OAuth (User Login)

With `grants` in the `oauth` table, the mount runs a real authorization flow
for the users of your site: someone adds your MCP URL in Claude, logs in to
your site in their browser, approves the connection, and Claude gets an access
token for their account. lapis-mcp runs the OAuth protocol and stores the
grants; your app supplies the user, the login page and the consent page, and
lapis-mcp never needs to know what a user is.

Clients identify themselves with a [Client ID Metadata
Document](https://datatracker.ietf.org/doc/draft-ietf-oauth-client-id-metadata-document/):
the `client_id` is an https URL serving the client's name and redirect URIs,
so there's no client registration. Claude (claude.ai, Desktop, mobile and
Claude Code) uses one hosted on `claude.ai`. Only clients on
`trusted_client_hosts` can connect, unless you set `allow_any_client` to let
any client connect and leave it to the user on the consent page.

The flow:

1. Claude calls the MCP endpoint, gets a `401`, and discovers the
   authorization server from the metadata routes.
2. It opens `{mount_path}/oauth/authorize` in the browser. A user who isn't
   logged in is sent to `login_url`, which must send them back afterwards.
3. lapis-mcp fetches the client's metadata document, checks the
   `redirect_uri` against it, and calls `render_consent`.
4. The consent form posts back to the authorize route. On approval the user
   is redirected to Claude with a code, which Claude exchanges at
   `{mount_path}/oauth/token` (PKCE `S256` required).
5. MCP requests carry the access token. `server.auth.grant` is the grant it
   belongs to, use it in `load_session` to find the user.

Access tokens last 90 days and there are no refresh tokens: when one expires,
Claude asks the user to connect again.

First create a grant model by extending `OauthGrantModel`, with a migration
for its table. The columns it needs are listed at the top of
`lapis/mcp/oauth/grant_model.moon`, plus whatever identifies the owner, which
`owner_values` returns:

```moonscript
import OauthGrantModel from require "lapis.mcp.oauth.grant_model"

class McpGrants extends OauthGrantModel
  @owner_values: (user) => { user_id: user.id }
```

Then mount the server:

```moonscript
router\mount "/mcp", MyMcpServer, {
  oauth: {
    grants: McpGrants
    trusted_client_hosts: {"claude.ai"}
    cache: ngx.shared.mcp_clients -- optional, caches metadata documents

    current_user: (route) -> route.current_user
    login_url: (route, return_to) -> route\url_for "login", nil, :return_to
    render_consent: (route, consent) ->
      route.consent = consent
      render: "mcp_consent"
  }

  load_session: (req, server) ->
    server.user = Users\find server.auth.grant.user_id
}
```

`render_consent` receives the request and a `consent` table, and returns a
Lapis response. The page must show who is asking and where the user will be
sent, and post `consent_token` to `action`, with `approve` set to approve and
without it to deny:

```html
<p>
  <strong><%= consent.client_host %></strong> (<%= consent.client_name %>)
  wants to access your account.
</p>
<% if not consent.client_trusted then %>
  <p>We don't recognise this app. Only allow it if you trust
  <%= consent.client_host %>.</p>
<% end %>
<% if consent.redirect_loopback then %>
  <p>You'll be sent back to an app running on your own computer.</p>
<% else %>
  <p>You'll be sent back to <%= consent.redirect_host %>.</p>
<% end %>
<form method="post" action="<%= consent.action %>">
  <input type="hidden" name="consent_token" value="<%= consent.consent_token %>">
  <button name="approve" value="1">Allow</button>
  <button>Cancel</button>
</form>
```

Name the client by `client_host`, `client_name` is whatever the client chose.
`X-Frame-Options: DENY`, `Content-Security-Policy: frame-ancestors 'none'` and
`Cache-Control: no-store` are added to the page's response unless it sets
them. The consent token is signed with your app's `secret`, expires after 10
minutes, and only works in the browser session it was shown in and for the
user it was shown to, so the form needs no CSRF token of its own. The token
includes the owner values, so `owner_values` must return plain strings,
numbers or booleans.

##### User Login Options

- `grants` (required): the grant store, usually an `OauthGrantModel` subclass. Any object that passes the contract tests in `lapis.mcp.oauth.grant_store_contract` works.
- `trusted_client_hosts` (required unless `allow_any_client` is set): hosts whose metadata documents are accepted, matched exactly. `{"claude.ai"}` for Claude.
- `allow_any_client` (optional): accept a metadata document from any public host. Hosts not in `trusted_client_hosts` get `client_trusted = false` on the consent page, which should warn about them. Needs certificate checking on outgoing requests, see below.
- `current_user(route)` (required): returns the logged in user, or `nil`. lapis-mcp only passes it to `owner_values`.
- `login_url(route, return_to)` (required): the URL of your login page, which must redirect to `return_to` after login.
- `render_consent(route, consent)` (required): renders the consent page, see above.
- `grant_created(route, grant)` (optional): called after the user approves a client, with the new grant, for example to record it in an activity log. The client hasn't exchanged its code for an access token yet.
- `cache` (optional): caches metadata documents, any object with `get(key)` and `set(key, value, ttl)` such as an `ngx.shared` dict. Without it each authorize request fetches the document.
- `access_token_ttl` (optional): seconds an access token lasts. Defaults to 90 days.
- `public_base_url`, `issuer` and `resource` work as for service tokens.

##### Running It

- Metadata documents are fetched with `lapis.http`, which under nginx goes
  through the `/proxy` location. Its TLS settings decide whether trusting a
  host means anything, so set `proxy_ssl_verify on`,
  `proxy_ssl_trusted_certificate` and `proxy_ssl_server_name on` there. With
  `allow_any_client` this also stops a hostname that resolves to a private
  address from getting anything back from your network.
- Expired grants aren't deleted automatically. Call `McpGrants\delete_expired!`
  periodically, for example from a cron job.
- Rejected clients are logged as warnings, with the reason. A client that
  can't connect shows up there.
- Run the grant store contract tests against your model in your own test
  suite:

  ```moonscript
  import grant_store_behaviour from require "lapis.mcp.oauth.grant_store_contract"

  describe "McpGrants", ->
    grant_store_behaviour (-> McpGrants), {
      owner_values: -> { user_id: factory.Users!.id }
    }
  ```

## The `lapis mcp` Subcommand

Installing this library adds a `mcp` subcommand to the `lapis` CLI. It loads an
MCP server module by name and runs it over stdin/stdout, a convenience for
projects that already use the `lapis` CLI, so you don't need to write a
separate launcher script.

```bash
lapis mcp <module>
```

The `<module>` argument is required and is the Lua/MoonScript module name of
any class that returns an `McpServer` subclass. For example, to start a
server you wrote yourself:

```bash
lapis mcp my.project.mcp_server
```

The shared CLI flags described in [Running Your Server](#running-your-server)
(`--debug`, `--tool`, `--dump-tools`, `--send-message`, `--tag`, etc.) all
work the same here. Internally `lapis mcp` dispatches through the same
argparse-driven runner that `McpServer:run_cli` uses for standalone scripts.

## Bundled Lapis MCP Server

`lapis.mcp.lapis_server` is a small `McpServer` subclass that ships with the
library and provides a handful of tools for introspecting and exercising the
current Lapis application. Run it through the `lapis mcp` subcommand:

```bash
lapis mcp lapis.mcp.lapis_server
```

It resolves the project's Lapis application on demand (via
`config.default_app_module`, falling back to the deprecated `config.app_class`,
then to `app`). Because the MCP server is
long-lived but the application source on disk is expected to change between
calls, every tool that touches the app (`list_routes`, `simulate`)
re-`require`s it from scratch. The modules pulled into `package.loaded`
during a call are tracked and purged before the next call, and
`lapis.config`'s internal cache is reset, so edits to app, model, view, and
config files take effect immediately without restarting the server.

It exposes:

- **list_routes**: lists all named routes in the application's router
- **list_models**: lists database model files found under `models/`
- **simulate**: issues a fake HTTP request through the loaded app (via `lapis.spec.request.simulate_request`) and returns the response status, headers, and body. Accepts `path` (required), `method`, `body`, `headers`, `host`, and `scheme`. Cookies set by the app via `Set-Cookie` are automatically captured into a per-session jar and replayed on subsequent calls, so an agent can log in and then make authenticated requests as the same user.
- **list_cookies**: returns the current contents of the cookie jar as a sorted array of `[name, value]` pairs.
- **clear_cookies**: empties the cookie jar.
- **schema** *(optional, only registered when [`lapis-annotate`](https://github.com/leafo/lapis-annotate) is installed)*: given a list of model class names, dumps each model's PostgreSQL schema (CREATE TABLE plus indexes/constraints) by shelling out to `pg_dump` with the project's `config.postgres` credentials.

## License

MIT
