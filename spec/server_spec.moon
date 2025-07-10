import LapisMcpServer, StdioTransport from require "lapis.mcp.server"

describe "McpServer", ->
  local mock_app, server

  before_each ->
    mock_app = ->
      router: {
        named_routes: {
          root: { "/", "GET" }
          users: { "/users", "GET" }
          user: { "/users/:id", "GET" }
        }
        build: ->
      }
    server = LapisMcpServer(mock_app, {})

  describe "initialization", ->
    it "should create server with proper defaults", ->
      assert.is_not_nil server
      assert.equal "2025-06-18", server.protocol_version
      assert.is_false server.initialized
      assert.is_false server.debug
      tools = server\get_all_tools!
      assert.is_table tools
      assert.is_table server.server_capabilities
      assert.is_table server.client_capabilities

    it "should have expected tools configured", ->
      tools = server\get_all_tools!

      assert.is_not_nil tools.list_routes
      assert.is_not_nil tools.list_models
      assert.is_not_nil tools.schema

      -- Check list_routes tool structure
      list_routes_tool = tools.list_routes

      assert.equal "list_routes", list_routes_tool.name
      assert.equal "List Routes", list_routes_tool.annotations.title
      assert.is_string list_routes_tool.description
      assert.is_table list_routes_tool.inputSchema

  describe "find_tool", ->
    it "should find tools in current class", ->
      tool = server\find_tool("list_routes")
      assert.is_not_nil tool
      assert.equal "list_routes", tool.name
      assert.equal "List Routes", tool.annotations.title

    it "should return nil for non-existent tools", ->
      tool = server\find_tool("nonexistent")
      assert.is_nil tool

    it "should handle inheritance chains", ->
      import McpServer from require "lapis.mcp.server"

      -- Create base class with tools
      class BaseServer extends McpServer
        @add_tool {
          name: "base-tool"
          description: "Tool from base class"
          inputSchema: { type: "object", properties: {}, required: {} }
          annotations: {
            title: "Base Tool"
          }
        }, -> "base result"

        @add_tool {
          name: "shared-tool"
          description: "Tool that will be overridden"
          inputSchema: { type: "object", properties: {}, required: {} }
          annotations: {
            title: "Shared Tool (Base)"
          }
        }, -> "base shared result"

      -- Create middle class that extends base
      class MiddleServer extends BaseServer
        @add_tool {
          name: "middle-tool"
          description: "Tool from middle class"
          inputSchema: { type: "object", properties: {}, required: {} }
          annotations: {
            title: "Middle Tool"
          }
        }, -> "middle result"

        @add_tool {
          name: "shared-tool"
          description: "Tool that overrides base"
          inputSchema: { type: "object", properties: {}, required: {} }
          annotations: {
            title: "Shared Tool (Middle)"
          }
        }, -> "middle shared result"

      -- Create final class that extends middle
      class FinalServer extends MiddleServer
        @add_tool {
          name: "final-tool"
          description: "Tool from final class"
          inputSchema: { type: "object", properties: {}, required: {} }
          annotations: {
            title: "Final Tool"
          }
        }, -> "final result"

      -- Test instance of final class
      final_server = FinalServer({})

      -- Should find tools from all levels
      base_tool = final_server\find_tool("base-tool")
      assert.is_not_nil base_tool
      assert.equal "base-tool", base_tool.name
      assert.equal "Base Tool", base_tool.annotations.title

      middle_tool = final_server\find_tool("middle-tool")
      assert.is_not_nil middle_tool
      assert.equal "middle-tool", middle_tool.name
      assert.equal "Middle Tool", middle_tool.annotations.title

      final_tool = final_server\find_tool("final-tool")
      assert.is_not_nil final_tool
      assert.equal "final-tool", final_tool.name
      assert.equal "Final Tool", final_tool.annotations.title

    it "should respect tool overriding in inheritance", ->
      import McpServer from require "lapis.mcp.server"

      -- Create base class with tools
      class BaseServer extends McpServer
        @add_tool {
          name: "shared-tool"
          description: "Original tool"
          inputSchema: { type: "object", properties: {}, required: {} }
          annotations: {
            title: "Shared Tool (Base)"
          }
        }, -> "base result"

      -- Create derived class that overrides the tool
      class DerivedServer extends BaseServer
        @add_tool {
          name: "shared-tool"
          description: "Overridden tool"
          inputSchema: { type: "object", properties: {}, required: {} }
          annotations: {
            title: "Shared Tool (Derived)"
          }
        }, -> "derived result"

      -- Test that derived class gets its own version
      derived_server = DerivedServer({})
      tool = derived_server\find_tool("shared-tool")
      assert.is_not_nil tool
      assert.equal "shared-tool", tool.name
      assert.equal "Shared Tool (Derived)", tool.annotations.title
      assert.equal "Overridden tool", tool.description

      -- Test that base class still has original
      base_server = BaseServer({})
      base_tool = base_server\find_tool("shared-tool")
      assert.is_not_nil base_tool
      assert.equal "shared-tool", base_tool.name
      assert.equal "Shared Tool (Base)", base_tool.annotations.title
      assert.equal "Original tool", base_tool.description

    it "should find first matching tool in search order", ->
      import McpServer from require "lapis.mcp.server"

      -- Create class with multiple tools with different names
      class MultiToolServer extends McpServer
        @add_tool {
          name: "first-tool"
          description: "First tool added"
          inputSchema: { type: "object", properties: {}, required: {} }
          annotations: {
            title: "First Tool"
          }
        }, -> "first result"

        @add_tool {
          name: "second-tool"
          description: "Second tool added"
          inputSchema: { type: "object", properties: {}, required: {} }
          annotations: {
            title: "Second Tool"
          }
        }, -> "second result"

        @add_tool {
          name: "third-tool"
          description: "Third tool added"
          inputSchema: { type: "object", properties: {}, required: {} }
          annotations: {
            title: "Third Tool"
          }
        }, -> "third result"

      server = MultiToolServer({})

      -- Should find each tool correctly
      first = server\find_tool("first-tool")
      assert.is_not_nil first
      assert.equal "First Tool", first.annotations.title

      second = server\find_tool("second-tool")
      assert.is_not_nil second
      assert.equal "Second Tool", second.annotations.title

      third = server\find_tool("third-tool")
      assert.is_not_nil third
      assert.equal "Third Tool", third.annotations.title

    it "should handle complex inheritance with multiple overrides", ->
      import McpServer from require "lapis.mcp.server"

      -- Create a complex inheritance chain
      class GrandParent extends McpServer
        @add_tool {
          name: "tool-a"
          description: "From grandparent"
          inputSchema: { type: "object", properties: {}, required: {} }
          annotations: {
            title: "Tool A (GrandParent)"
          }
        }, -> "grandparent-a"

        @add_tool {
          name: "tool-b"
          description: "From grandparent"
          inputSchema: { type: "object", properties: {}, required: {} }
          annotations: {
            title: "Tool B (GrandParent)"
          }
        }, -> "grandparent-b"

      class Parent extends GrandParent
        @add_tool {
          name: "tool-a"
          description: "Overridden by parent"
          inputSchema: { type: "object", properties: {}, required: {} }
          annotations: {
            title: "Tool A (Parent)"
          }
        }, -> "parent-a"

        @add_tool {
          name: "tool-c"
          description: "From parent"
          inputSchema: { type: "object", properties: {}, required: {} }
          annotations: {
            title: "Tool C (Parent)"
          }
        }, -> "parent-c"

      class Child extends Parent
        @add_tool {
          name: "tool-b"
          description: "Overridden by child"
          inputSchema: { type: "object", properties: {}, required: {} }
          annotations: {
            title: "Tool B (Child)"
          }
        }, -> "child-b"

        @add_tool {
          name: "tool-d"
          description: "From child"
          inputSchema: { type: "object", properties: {}, required: {} }
          annotations: {
            title: "Tool D (Child)"
          }
        }, -> "child-d"

      child_server = Child({})

      -- tool-a should come from parent (overrides grandparent)
      tool_a = child_server\find_tool("tool-a")
      assert.is_not_nil tool_a
      assert.equal "Tool A (Parent)", tool_a.annotations.title

      -- tool-b should come from child (overrides grandparent)
      tool_b = child_server\find_tool("tool-b")
      assert.is_not_nil tool_b
      assert.equal "Tool B (Child)", tool_b.annotations.title

      -- tool-c should come from parent
      tool_c = child_server\find_tool("tool-c")
      assert.is_not_nil tool_c
      assert.equal "Tool C (Parent)", tool_c.annotations.title

      -- tool-d should come from child
      tool_d = child_server\find_tool("tool-d")
      assert.is_not_nil tool_d
      assert.equal "Tool D (Child)", tool_d.annotations.title

  describe "handle_initialize", ->
    it "should handle basic initialization", ->
      message = {
        jsonrpc: "2.0"
        id: 1
        method: "initialize"
        params: {
          protocolVersion: "2025-06-18"
          clientInfo: {
            name: "test-client"
            version: "1.0.0"
          }
          capabilities: {}
        }
      }

      response = server\handle_initialize(message)

      assert.equal "2.0", response.jsonrpc
      assert.equal 1, response.id
      assert.is_table response.result
      assert.equal "2025-06-18", response.result.protocolVersion
      assert.is_table response.result.capabilities
      assert.is_table response.result.serverInfo
      assert.equal "lapis-mcp", response.result.serverInfo.name
      assert.is_true server.initialized

    it "should reject protocol version mismatch", ->
      message = {
        jsonrpc: "2.0"
        id: 1
        method: "initialize"
        params: {
          protocolVersion: "2024-01-01"
        }
      }

      response = server\handle_initialize(message)

      assert.equal "2.0", response.jsonrpc
      assert.equal 1, response.id
      assert.is_table response.error
      assert.equal -32602, response.error.code
      assert.matches "Protocol version mismatch", response.error.message
      assert.is_false server.initialized

  describe "handle_tools_list", ->
    it "should require initialization", ->
      message = {
        jsonrpc: "2.0"
        id: 2
        method: "tools/list"
      }

      response = server\handle_tools_list(message)

      assert.equal "2.0", response.jsonrpc
      assert.equal 2, response.id
      assert.is_table response.error
      assert.equal -32002, response.error.code
      assert.matches "Server not initialized", response.error.message

    it "should list tools after initialization", ->
      -- First initialize
      init_message = {
        jsonrpc: "2.0"
        id: 1
        method: "initialize"
        params: {
          protocolVersion: "2025-06-18"
        }
      }
      server\handle_initialize(init_message)

      -- Then list tools
      list_message = {
        jsonrpc: "2.0"
        id: 2
        method: "tools/list"
      }

      response = server\handle_tools_list(list_message)

      assert.equal "2.0", response.jsonrpc
      assert.equal 2, response.id
      assert.is_table response.result
      assert.is_table response.result.tools
      assert.equal 3, #response.result.tools

      -- Check tool names
      tool_names = {}
      for _, tool in ipairs(response.result.tools)
        tool_names[tool.name] = true

      assert.is_true tool_names["list_routes"]
      assert.is_true tool_names["list_models"]
      assert.is_true tool_names["schema"]

  describe "handle_tools_call", ->
    before_each ->
      -- Initialize server for tool calls
      init_message = {
        jsonrpc: "2.0"
        id: 1
        method: "initialize"
        params: {
          protocolVersion: "2025-06-18"
        }
      }
      server\handle_initialize(init_message)

    it "should require initialization", ->
      uninit_server = LapisMcpServer(mock_app, {})
      message = {
        jsonrpc: "2.0"
        id: 3
        method: "tools/call"
        params: {
          name: "routes"
          arguments: {}
        }
      }

      response = uninit_server\handle_tools_call(message)

      assert.equal "2.0", response.jsonrpc
      assert.equal 3, response.id
      assert.is_table response.error
      assert.equal -32002, response.error.code

    it "should handle unknown tool", ->
      message = {
        jsonrpc: "2.0"
        id: 3
        method: "tools/call"
        params: {
          name: "unknown_tool"
          arguments: {}
        }
      }

      response = server\handle_tools_call(message)

      assert.equal "2.0", response.jsonrpc
      assert.equal 3, response.id
      assert.is_table response.result
      assert.is_table response.result.content
      assert.equal "text", response.result.content[1].type
      assert.matches "Unknown tool", response.result.content[1].text
      assert.is_true response.result.isError

    it "should call list_routes tool successfully", ->
      message = {
        jsonrpc: "2.0"
        id: 3
        method: "tools/call"
        params: {
          name: "list_routes"
          arguments: {}
        }
      }

      response = server\handle_tools_call(message)

      assert.equal "2.0", response.jsonrpc
      assert.equal 3, response.id
      assert.is_table response.result
      assert.is_table response.result.content
      assert.equal "text", response.result.content[1].type
      assert.is_false response.result.isError

      -- Parse the JSON response
      json = require "cjson.safe"
      routes_data = json.decode(response.result.content[1].text)
      assert.is_table routes_data
      -- Assuming the response should contain the routes; adjust as needed
      -- to match the actual expected number of routes
      assert.is_number #routes_data

    it "should handle schema tool with missing parameter", ->
      message = {
        jsonrpc: "2.0"
        id: 4
        method: "tools/call"
        params: {
          name: "schema"
          arguments: {}
        }
      }

      response = server\handle_tools_call(message)

      assert.equal "2.0", response.jsonrpc
      assert.equal 4, response.id
      assert.is_table response.result
      assert.is_table response.result.content
      assert.equal "text", response.result.content[1].type
      assert.matches "Missing required parameter", response.result.content[1].text
      assert.is_true response.result.isError

    it "should handle schema tool with parameter", ->
      message = {
        jsonrpc: "2.0"
        id: 4
        method: "tools/call"
        params: {
          name: "schema"
          arguments: {
            model_name: "User"
          }
        }
      }

      response = server\handle_tools_call(message)

      assert.equal "2.0", response.jsonrpc
      assert.equal 4, response.id
      assert.is_table response.result
      assert.is_table response.result.content
      assert.equal "text", response.result.content[1].type
      -- This should return an error since the model loading is not implemented
      assert.is_true response.result.isError

  describe "handle_message", ->
    it "should dispatch to correct handlers", ->
      -- Test initialize
      init_message = {
        jsonrpc: "2.0"
        id: 1
        method: "initialize"
        params: {
          protocolVersion: "2025-06-18"
        }
      }

      response = server\handle_message(init_message)
      assert.is_table response.result
      assert.equal "2025-06-18", response.result.protocolVersion

      -- Test tools/list
      list_message = {
        jsonrpc: "2.0"
        id: 2
        method: "tools/list"
      }

      response = server\handle_message(list_message)
      assert.is_table response.result
      assert.is_table response.result.tools

      -- Test notifications/initialized
      notif_message = {
        jsonrpc: "2.0"
        method: "notifications/initialized"
      }

      response = server\handle_message(notif_message)
      assert.is_nil response
      assert.is_true server.client_initialized

      -- Test notifications/cancelled
      cancel_message = {
        jsonrpc: "2.0"
        method: "notifications/cancelled"
        params: {
          requestId: 1
          reason: "Test cancellation"
        }
      }

      response = server\handle_message(cancel_message)
      assert.is_nil response

      -- Test ping
      ping_message = {
        jsonrpc: "2.0"
        id: 3
        method: "ping"
      }

      response = server\handle_message(ping_message)
      assert.equal "2.0", response.jsonrpc
      assert.equal 3, response.id
      assert.is_table response.result
      assert.same {}, response.result

    it "should handle unknown methods", ->
      message = {
        jsonrpc: "2.0"
        id: 99
        method: "unknown/method"
      }

      response = server\handle_message(message)

      assert.equal "2.0", response.jsonrpc
      assert.equal 99, response.id
      assert.is_table response.error
      assert.equal -32601, response.error.code
      assert.matches "Method not found", response.error.message

  describe "routes tool", ->
    it "should extract routes from app via full tool call", ->
      -- Initialize server first
      init_message = {
        jsonrpc: "2.0"
        id: 1
        method: "initialize"
        params: {
          protocolVersion: "2025-06-18"
        }
      }
      server\handle_initialize(init_message)

      -- Call list_routes tool through the full MCP flow
      call_message = {
        jsonrpc: "2.0"
        id: 2
        method: "tools/call"
        params: {
          name: "list_routes"
          arguments: {}
        }
      }

      response = server\handle_tools_call(call_message)

      assert.equal "2.0", response.jsonrpc
      assert.equal 2, response.id
      assert.is_table response.result
      assert.is_false response.result.isError
      assert.is_table response.result.content
      assert.equal "text", response.result.content[1].type

      -- Parse the JSON response to check the actual routes
      json = require "cjson.safe"
      routes = json.decode(response.result.content[1].text)

      assert.is_table routes
      assert.equal 3, #routes

      -- Check that routes are sorted
      assert.equal "root", routes[1][1]
      assert.equal "user", routes[2][1]
      assert.equal "users", routes[3][1]

      -- Check route structure
      assert.is_table routes[1][2]
      assert.equal "/", routes[1][2][1]
      assert.equal "GET", routes[1][2][2]

  describe "transport integration", ->
    it "should handle JSON messages through transport", ->
      -- Mock transport for testing
      mock_transport = {
        messages: {}
        read_json_chunk: =>
          if #@messages > 0
            table.remove(@messages, 1)
          else
            false
        write_json_chunk: (obj) =>
          table.insert(@messages, obj)
      }

      server.transport = mock_transport

      -- Test reading/writing JSON
      test_message = {
        jsonrpc: "2.0"
        id: 1
        method: "initialize"
        params: {
          protocolVersion: "2025-06-18"
        }
      }

      mock_transport.messages = {test_message}

      message = server\read_json_chunk!
      assert.same test_message, message

      response = server\handle_message(message)
      server\write_json_chunk(response)

      assert.equal 1, #mock_transport.messages
      assert.equal "2.0", mock_transport.messages[1].jsonrpc
