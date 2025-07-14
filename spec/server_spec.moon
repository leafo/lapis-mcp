import McpServer, StdioTransport from require "lapis.mcp.server"
json = require "cjson"

with_mock_transport = (server) ->
  server.transport = {
    messages: {}
    write_json_chunk: (obj) =>
      table.insert @messages, obj
  }

  server.transport

describe "McpServer", ->
  describe "initialization", ->
    it "should create server with proper defaults", ->
      server = McpServer({})
      assert.is_not_nil server
      assert.equal "2025-06-18", server.protocol_version
      assert.is_false server.initialized
      assert.is_false server.debug
      tools = server\get_all_tools!
      assert.is_table tools
      assert.is_table server.server_capabilities
      assert.is_table server.client_capabilities

  it "find_tool", ->
    class SimpleServer extends McpServer
      @add_tool {
        name: "subclass-tool"
        description: "Tool specific to subclass"
        inputSchema: { type: "object", properties: {}, required: {} }
        annotations: {
          title: "Subclass Tool"
        }
      }, -> "subclass result"

    server = SimpleServer!
    subclass_tool = server\find_tool("subclass-tool")
    assert.is_not_nil subclass_tool
    assert.equal "subclass-tool", subclass_tool.name
    assert.equal "Subclass Tool", subclass_tool.annotations.title
    assert.equal "Tool specific to subclass", subclass_tool.description

    assert.is_nil server\find_tool("nonexistent")

  describe "tool inheritance", ->
    it "should handle inheritance chains", ->
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

  describe "server capabilities", ->
    it "should include listChanged in initialization response", ->
      test_server = McpServer!

      init_message = {
        jsonrpc: "2.0"
        id: 1
        method: "initialize"
        params: {
          protocolVersion: "2025-06-18"
        }
      }

      response = test_server\handle_initialize(init_message)

      assert.same {
        tools: {
          listChanged: true
        }
        resources: {
          subscribe: false
          listChanged: true
        }
      }, response.result.capabilities

  describe "handle_initialize", ->
    local server
    before_each ->
      server = McpServer!

    it "should handle basic initialization", ->
      response = server\handle_initialize {
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

      assert.same {
        id: 1
        jsonrpc: "2.0"
        result: {
          protocolVersion: "2025-06-18"
          capabilities: {
            tools: {
              listChanged: true
            }
            resources: {
              subscribe: false
              listChanged: true
            }
          }
          serverInfo: {
            name: "McpServer"
            vendor: "Lapis"
            version: "1.0.0"
          }
        }
      }, response

      assert.is_true server.initialized

    it "should reject protocol version mismatch", ->
      response = server\handle_initialize {
        jsonrpc: "2.0"
        id: 1
        method: "initialize"
        params: {
          protocolVersion: "2024-01-01"
        }
      }

      assert.same {
        jsonrpc: "2.0",
        id: 1,
        error: {
          code: -32602,
          message: "Protocol version mismatch. Server supports: 2025-06-18, client requested: 2024-01-01"
        }
      }, response

      assert.is_false server.initialized

  describe "handle_message", ->
    local server

    before_each ->
      server = McpServer!

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
      response = server\handle_message {
        jsonrpc: "2.0"
        id: 99
        method: "unknown_method"
      }

      assert.same {
        jsonrpc: "2.0",
        id: 99,
        error: {
          code: -32601,
          message: "Method not found: unknown_method"
        }
      }, response

  describe "handle_tools_list", ->
    local server, mock_transport
    before_each ->
      class MyToolServer extends McpServer
        @add_tool {
          name: "test-tool"
          inputSchema: { type: "object", properties: {}, required: {} }
        }, -> "hello world"

        @add_tool {
          name: "bogus-tool"
          inputSchema: { type: "object", properties: { exampleProperty: { type: "string" } }, required: { "exampleProperty" } }
        }, -> "I am BOGUS"

      server = MyToolServer!
      mock_transport = with_mock_transport server

    it "should require initialization", ->
      response = server\handle_tools_list {
        jsonrpc: "2.0"
        id: 2
        method: "tools/list"
      }

      assert.same {
        jsonrpc: "2.0",
        id: 2,
        error: {
          code: -32002,
          message: "Server not initialized. Call initialize first."
        }
      }, response

    it "should list tools", ->
      server\skip_initialize!

      response = server\handle_tools_list {
        jsonrpc: "2.0"
        id: 2
        method: "tools/list"
      }

      assert.equal "2.0", response.jsonrpc
      assert.equal 2, response.id
      assert.is_table response.result
      assert.is_table response.result.tools
      assert.equal 2, #response.result.tools

      -- Check tool names
      tool_names = {}
      for _, tool in ipairs(response.result.tools)
        tool_names[tool.name] = true

      assert.is_true tool_names["test-tool"]
      assert.is_true tool_names["bogus-tool"]

  describe "handle_tools_call", ->
    local server
    before_each ->
      class MyToolServer extends McpServer
        @add_tool {
          name: "string-tool"
          description: "Returns a simple string"
          inputSchema: { type: "object", properties: {}, required: {} }
        }, -> "simple string"

        @add_tool {
          name: "object-tool"
          description: "Returns an object"
          inputSchema: { type: "object", properties: {}, required: {} }
        }, -> {"key": "value", "number": 42}

        @add_tool {
          name: "error-tool"
          description: "Returns nil and an error"
          inputSchema: { type: "object", properties: {}, required: {} }
        }, -> nil, "explicit error"

        @add_tool {
          name: "required-params-tool"
          description: "Requires certain parameters"
          inputSchema: { type: "object", properties: { param1: { type: "string" } }, required: { "param1" } }
        }, (params) => "Got #{params.param1}"

      server = MyToolServer!
      server\skip_initialize!

    it "should require initialization", ->
      uninit_server = McpServer!

      response = uninit_server\handle_tools_call {
        jsonrpc: "2.0"
        id: 3
        method: "tools/call"
        params: {
          name: "routes"
          arguments: {}
        }
      }

      assert.same {
        jsonrpc: "2.0",
        id: 3,
        error: {
          code: -32002,
          message: "Server not initialized. Call initialize first."
        }
      }, response

    it "should handle unknown tool", ->
      response = server\handle_tools_call {
        jsonrpc: "2.0"
        id: 3
        method: "tools/call"
        params: {
          name: "unknown_tool"
          arguments: {}
        }
      }

      assert.same {
        jsonrpc: "2.0",
        id: 3,
        result: {
          content: {
            {
              type: "text",
              text: "Unknown tool: unknown_tool"
            }
          },
          isError: true
        }
      }, response

    it "should handle returning a simple string", ->
      message = {
        jsonrpc: "2.0"
        id: 5
        method: "tools/call"
        params: {
          name: "string-tool"
          arguments: {}
        }
      }

      response = server\handle_tools_call(message)

      assert.same {
        jsonrpc: "2.0",
        id: 5,
        result: {
          content: {
            {
              type: "text",
              text: "simple string"
            }
          },
          isError: false
        }
      }, response

    it "should handle returning an object", ->
      response = server\handle_tools_call {
        jsonrpc: "2.0"
        id: 6
        method: "tools/call"
        params: {
          name: "object-tool"
          arguments: {}
        }
      }

      assert.equal "2.0", response.jsonrpc
      assert.equal 6, response.id
      assert.is_table response.result
      assert.is_table response.result.content
      assert.equal "text", response.result.content[1].type

      -- Decode the JSON text to verify structure
      decoded_result = json.decode response.result.content[1].text
      assert.same {
        key: "value"
        number: 42
      }, decoded_result

      assert.is_false response.result.isError

    it "should handle tool returning nil and an error", ->
      message = {
        jsonrpc: "2.0"
        id: 7
        method: "tools/call"
        params: {
          name: "error-tool"
          arguments: {}
        }
      }

      response = server\handle_tools_call(message)

      assert.same {
        jsonrpc: "2.0",
        id: 7,
        result: {
          content: {
            {
              type: "text",
              text: "Error executing tool: explicit error"
            }
          },
          isError: true
        }
      }, response

    it "should handle tool with missing parameter", ->
      response = server\handle_tools_call {
        jsonrpc: "2.0"
        id: 4
        method: "tools/call"
        params: {
          name: "required-params-tool"
          arguments: {}
        }
      }

      assert.same {
        jsonrpc: "2.0",
        id: 4,
        result: {
          content: {
            {
              type: "text",
              text: "Missing required parameter: param1"
            }
          },
          isError: true
        }
      }, response

    it "should handle tool with parameter", ->
      response = server\handle_tools_call {
        jsonrpc: "2.0"
        id: 4
        method: "tools/call"
        params: {
          name: "required-params-tool"
          arguments: {
            param1: "TestValue"
          }
        }
      }

      assert.same {
        jsonrpc: "2.0",
        id: 4,
        result: {
          content: {
            {
              type: "text",
              text: "Got TestValue"
            }
          },
          isError: false
        }
      }, response

  describe "hidden tools", ->
    local server
    before_each ->
      class HiddenToolServer extends McpServer
        @add_tool {
          name: "visible-tool"
          description: "A visible tool"
          inputSchema: { type: "object", properties: {}, required: {} }
          annotations: { title: "Visible Tool" }
        }, -> "visible result"

        @add_tool {
          name: "hidden-tool"
          description: "A hidden tool"
          inputSchema: { type: "object", properties: {}, required: {} }
          annotations: { title: "Hidden Tool" }
          hidden: true
        }, -> "hidden result"

      server = HiddenToolServer!
      server\skip_initialize!

    it "should create tools with hidden property", ->
      visible_tool = server\find_tool("visible-tool")
      assert.is_not_nil visible_tool
      assert.is_false visible_tool.hidden

      -- hidden tool can still be found directly by name
      hidden_tool = server\find_tool("hidden-tool")
      assert.is_not_nil hidden_tool
      assert.is_true hidden_tool.hidden

    it "should exclude hidden tools from tools list by default", ->
      response = server\handle_tools_list {
        jsonrpc: "2.0"
        id: 2
        method: "tools/list"
      }

      assert.equal 1, #response.result.tools
      assert.equal "visible-tool", response.result.tools[1].name

    it "should still allow calling hidden tools directly", ->
      -- Call hidden tool directly
      call_message = {
        jsonrpc: "2.0"
        id: 2
        method: "tools/call"
        params: {
          name: "hidden-tool"
          arguments: {}
        }
      }

      response = server\handle_tools_call(call_message)

      assert.same {
        jsonrpc: "2.0",
        id: 2,
        result: {
          content: {
            {
              type: "text",
              text: "hidden result"
            }
          },
          isError: false
        }
      }, response

  describe "tool visibility management", ->
    local server, mock_transport

    before_each ->
      class TestServer extends McpServer
        @add_tool {
          name: "tool-1"
          description: "First tool"
          inputSchema: { type: "object", properties: {}, required: {} }
          annotations: { title: "Tool 1" }
        }, -> "result 1"

        @add_tool {
          name: "tool-2"
          description: "Second tool"
          inputSchema: { type: "object", properties: {}, required: {} }
          annotations: { title: "Tool 2" }
          hidden: true
        }, -> "result 2"

        @add_tool {
          name: "tool-3"
          description: "Third tool"
          inputSchema: { type: "object", properties: {}, required: {} }
          annotations: { title: "Tool 3" }
        }, -> "result 3"

      server = TestServer!
      mock_transport = with_mock_transport server
      server\skip_initialize!

    it "should initialize with empty tool_visibility table", ->
      assert.same {}, server.tool_visibility

    it "should set single tool visibility", ->
      -- Hide a visible tool
      result = server\set_tool_visibility("tool-1", false)
      assert.is_true result
      assert.is_false server.tool_visibility["tool-1"]

      -- Show a hidden tool
      result = server\set_tool_visibility("tool-2", true)
      assert.is_true result
      assert.is_true server.tool_visibility["tool-2"]

    it "should set multiple tool visibility with table", ->
      visibility_map = {
        "tool-1": false
        "tool-2": true
        "tool-3": false
      }

      result = server\set_tool_visibility(visibility_map)
      assert.is_true result

      assert.is_false server.tool_visibility["tool-1"]
      assert.is_true server.tool_visibility["tool-2"]
      assert.is_false server.tool_visibility["tool-3"]

    it "should return false when no visibility changes", ->
      -- Set a tool to its current visibility
      server\set_tool_visibility("tool-1", true)  -- tool-1 is already visible
      result = server\set_tool_visibility("tool-1", true)
      assert.is_nil result

      server\set_tool_visibility("tool-2", false)  -- tool-2 is already hidden
      result = server\set_tool_visibility("tool-2", false)
      assert.is_nil result

    it "should use hide_tool and unhide_tool shortcuts", ->
      -- Hide a tool
      result = server\hide_tool("tool-1")
      assert.is_true result
      assert.is_false server.tool_visibility["tool-1"]

      -- Unhide a tool
      result = server\unhide_tool("tool-2")
      assert.is_true result
      assert.is_true server.tool_visibility["tool-2"]

    it "should respect visibility overrides in tools list", ->
      -- Hide tool-1 and show tool-2
      server\set_tool_visibility("tool-1", false)
      server\set_tool_visibility("tool-2", true)

      list_message = {
        jsonrpc: "2.0"
        id: 2
        method: "tools/list"
      }

      response = server\handle_tools_list(list_message)

      -- Should have tool-2 and tool-3 (tool-1 is hidden, tool-2 is shown)
      assert.equal 2, #response.result.tools

      tool_names = {}
      for tool in *response.result.tools
        tool_names[tool.name] = true

      assert.is_true tool_names["tool-2"]
      assert.is_true tool_names["tool-3"]
      assert.is_nil tool_names["tool-1"]

  describe "tools list changed notifications", ->
    local test_server, mock_transport

    before_each ->
      class TestServer extends McpServer
        @add_tool {
          name: "test-tool"
          description: "Test tool"
          inputSchema: { type: "object", properties: {}, required: {} }
          annotations: { title: "Test Tool" }
        }, -> "test result"

      test_server = TestServer!
      mock_transport = with_mock_transport test_server
      test_server\skip_initialize!

    it "should send notification when tool visibility changes", ->
      initial_count = #mock_transport.messages

      test_server\set_tool_visibility("test-tool", false)

      assert.equal initial_count + 1, #mock_transport.messages
      notification = mock_transport.messages[#mock_transport.messages]

      assert.same {
        jsonrpc: "2.0",
        method: "notifications/tools/list_changed",
      }, notification

    it "should not send notification when no visibility changes", ->
      initial_count = #mock_transport.messages

      test_server.tool_visibility["test-tool"] = true

      -- Set tool to its current visibility (should not change)
      test_server\set_tool_visibility("test-tool", true)

      assert.equal initial_count, #mock_transport.messages

    it "should not send notification before client initialization", ->
      -- Create uninitialized server
      class UninitServer extends McpServer
        @add_tool {
          name: "test-tool"
          description: "Test tool"
          inputSchema: { type: "object", properties: {}, required: {} }
          annotations: { title: "Test Tool" }
        }, -> "test result"

      uninit_server = UninitServer!
      mock_transport = with_mock_transport uninit_server

      initial_count = #mock_transport.messages

      uninit_server\set_tool_visibility("test-tool", false)

      assert.equal initial_count, #mock_transport.messages

    it "should send notification for batch visibility changes", ->
      initial_count = #mock_transport.messages

      visibility_map = {
        "test-tool": false
        "nonexistent-tool": true
      }

      test_server\set_tool_visibility(visibility_map)

      assert.equal initial_count + 1, #mock_transport.messages

  describe "resources", ->
    describe "basic resource functionality", ->
      it "should add and find resources", ->
        class TestResourceServer extends McpServer
          @add_resource {
            uri: "test://example/resource1"
            name: "Test Resource"
            description: "A test resource"
            mimeType: "text/plain"
          }, -> "Resource content"

        server = TestResourceServer!
        resource = server\find_resource("test://example/resource1")
        assert.is_not_nil resource
        assert.equal "test://example/resource1", resource.uri
        assert.equal "Test Resource", resource.name
        assert.equal "A test resource", resource.description
        assert.equal "text/plain", resource.mimeType

      it "should handle resource inheritance", ->
        class BaseResourceServer extends McpServer
          @add_resource {
            uri: "test://base/resource"
            name: "Base Resource"
            description: "Resource from base class"
            mimeType: "text/plain"
          }, -> "Base content"

        class DerivedResourceServer extends BaseResourceServer
          @add_resource {
            uri: "test://derived/resource"
            name: "Derived Resource"
            description: "Resource from derived class"
            mimeType: "text/plain"
          }, -> "Derived content"

        server = DerivedResourceServer!

        -- Should find both base and derived resources
        base_resource = server\find_resource("test://base/resource")
        assert.is_not_nil base_resource
        assert.equal "Base Resource", base_resource.name

        derived_resource = server\find_resource("test://derived/resource")
        assert.is_not_nil derived_resource
        assert.equal "Derived Resource", derived_resource.name

    describe "handle_resources_list", ->
      local server
      before_each ->
        class TestResourceServer extends McpServer
          @add_resource {
            uri: "test://example/visible"
            name: "Visible Resource"
            description: "A visible resource"
            mimeType: "text/plain"
          }, -> "Visible content"

          @add_resource {
            uri: "test://example/hidden"
            name: "Hidden Resource"
            description: "A hidden resource"
            mimeType: "application/json"
            hidden: true
          }, -> "Hidden content"

        server = TestResourceServer!

      it "should require initialization", ->
        response = server\handle_resources_list {
          jsonrpc: "2.0"
          id: 1
          method: "resources/list"
        }

        assert.same {
          jsonrpc: "2.0"
          id: 1
          error: {
            code: -32002
            message: "Server not initialized. Call initialize first."
          }
        }, response

      it "should list visible resources", ->
        server\skip_initialize!

        response = server\handle_resources_list {
          jsonrpc: "2.0"
          id: 1
          method: "resources/list"
        }

        assert.equal "2.0", response.jsonrpc
        assert.equal 1, response.id
        assert.is_table response.result
        assert.is_table response.result.resources
        assert.equal 1, #response.result.resources

        resource = response.result.resources[1]
        assert.equal "test://example/visible", resource.uri
        assert.equal "Visible Resource", resource.name
        assert.equal "A visible resource", resource.description
        assert.equal "text/plain", resource.mimeType

      it "should return empty list for resources/templates/list", ->
        server\skip_initialize!
        response = server\handle_resources_templates_list {
          jsonrpc: "2.0"
          id: 1
          method: "resources/templates/list"
        }

        assert.same {
          jsonrpc: "2.0",
          id: 1,
          result: {
            resourceTemplates: {}
          }
        }, response

    describe "handle_resources_read", ->
      local server
      before_each ->
        class TestResourceServer extends McpServer
          @add_resource {
            uri: "test://example/simple"
            name: "Simple Resource"
            description: "A simple text resource"
            mimeType: "text/plain"
          }, -> "Simple text content"

          @add_resource {
            uri: "test://example/object"
            name: "Object Resource"
            description: "A JSON object resource"
            mimeType: "application/json"
          }, -> {message: "Hello", value: 42}

          @add_resource {
            uri: "test://example/error"
            name: "Error Resource"
            description: "A resource that returns an error"
            mimeType: "text/plain"
          }, -> nil, "Resource error"

          @add_resource {
            uri: "test://example/structured"
            name: "Structured Resource"
            description: "A resource with structured response"
            mimeType: "text/plain"
          }, -> {
            contents: {
              {
                uri: "test://example/structured"
                mimeType: "text/plain"
                text: "Structured content"
              }
            }
          }

        server = TestResourceServer!

      it "should require initialization", ->
        response = server\handle_resources_read {
          jsonrpc: "2.0"
          id: 1
          method: "resources/read"
          params: {
            uri: "test://example/simple"
          }
        }

        assert.same {
          jsonrpc: "2.0"
          id: 1
          error: {
            code: -32002
            message: "Server not initialized. Call initialize first."
          }
        }, response

      it "should read simple text resource", ->
        server\skip_initialize!

        response = server\handle_resources_read {
          jsonrpc: "2.0"
          id: 1
          method: "resources/read"
          params: {
            uri: "test://example/simple"
          }
        }

        assert.equal "2.0", response.jsonrpc
        assert.equal 1, response.id
        assert.is_table response.result
        assert.is_table response.result.contents
        assert.equal 1, #response.result.contents

        content = response.result.contents[1]
        assert.equal "test://example/simple", content.uri
        assert.equal "text/plain", content.mimeType
        assert.equal "Simple text content", content.text

      it "should read object resource as JSON", ->
        server\skip_initialize!

        response = server\handle_resources_read {
          jsonrpc: "2.0"
          id: 1
          method: "resources/read"
          params: {
            uri: "test://example/object"
          }
        }

        assert.equal "2.0", response.jsonrpc
        assert.equal 1, response.id
        assert.is_table response.result
        assert.is_table response.result.contents
        assert.equal 1, #response.result.contents

        content = response.result.contents[1]
        assert.equal "test://example/object", content.uri
        assert.equal "application/json", content.mimeType

        -- Should be JSON encoded
        decoded = json.decode(content.text)
        assert.same {message: "Hello", value: 42}, decoded

      it "should handle resource not found", ->
        server\skip_initialize!

        response = server\handle_resources_read {
          jsonrpc: "2.0"
          id: 1
          method: "resources/read"
          params: {
            uri: "test://example/nonexistent"
          }
        }

        assert.same {
          jsonrpc: "2.0"
          id: 1
          error: {
            code: -32002
            message: "Resource not found: test://example/nonexistent"
          }
        }, response

      it "should handle resource error", ->
        server\skip_initialize!

        response = server\handle_resources_read {
          jsonrpc: "2.0"
          id: 1
          method: "resources/read"
          params: {
            uri: "test://example/error"
          }
        }

        assert.same {
          jsonrpc: "2.0"
          id: 1
          error: {
            code: -32603
            message: "Error reading resource: Resource error"
          }
        }, response

      it "should handle structured response", ->
        server\skip_initialize!

        response = server\handle_resources_read {
          jsonrpc: "2.0"
          id: 1
          method: "resources/read"
          params: {
            uri: "test://example/structured"
          }
        }

        assert.equal "2.0", response.jsonrpc
        assert.equal 1, response.id
        assert.is_table response.result
        assert.is_table response.result.contents
        assert.equal 1, #response.result.contents

        content = response.result.contents[1]
        assert.equal "test://example/structured", content.uri
        assert.equal "text/plain", content.mimeType
        assert.equal "Structured content", content.text

    describe "server capabilities", ->
      it "should include resources in initialization response", ->
        test_server = McpServer!

        init_message = {
          jsonrpc: "2.0"
          id: 1
          method: "initialize"
          params: {
            protocolVersion: "2025-06-18"
          }
        }

        response = test_server\handle_initialize(init_message)

        assert.same {
          tools: {
            listChanged: true
          }
          resources: {
            subscribe: false
            listChanged: true
          }
        }, response.result.capabilities

    describe "URI template resources", ->
      describe "basic URI template functionality", ->
        it "should add resources with uriTemplate", ->
          class TemplateResourceServer extends McpServer
            @add_resource {
              uriTemplate: "app://users/{userId}"
              name: "User Resource"
              description: "A user resource with ID parameter"
              mimeType: "application/json"
            }, (params) => {id: params.userId, name: "User #{params.userId}"}

          server = TemplateResourceServer!

          resource = server\find_resource("app://other/world")
          assert.is_nil resource

          -- Should find template by matching URI
          resource = server\find_resource("app://users/123")
          assert.is_not_nil resource
          assert.equal "app://users/{userId}", resource.uriTemplate
          assert.equal "User Resource", resource.name

        it "should handle multiple template parameters", ->
          class MultiParamServer extends McpServer
            @add_resource {
              uriTemplate: "app://orgs/{orgId}/users/{userId}"
              name: "Organization User"
              description: "User resource within organization"
              mimeType: "application/json"
            }, (params) => {
              org: params.orgId
              user: params.userId
              path: "orgs/#{params.orgId}/users/#{params.userId}"
            }

          server = MultiParamServer!
          resource = server\find_resource("app://orgs/acme/users/123")
          assert.is_not_nil resource
          assert.equal "app://orgs/{orgId}/users/{userId}", resource.uriTemplate

        it "should handle query parameters in templates", ->
          class QueryTemplateServer extends McpServer
            @add_resource {
              uriTemplate: "app://api/items{?sort,limit}"
              name: "Items API"
              description: "Items with optional sorting and limit"
              mimeType: "application/json"
            }, (params) => {
              items: {"item1", "item2", "item3"}
              sort: params.sort or "name"
              limit: tonumber(params.limit) or 10
            }

          server = QueryTemplateServer!

          -- Should match without query params
          resource = server\find_resource("app://api/items")
          assert.is_not_nil resource
          assert.equal "app://api/items{?sort,limit}", resource.uriTemplate

          -- Should match with query params
          resource = server\find_resource("app://api/items?sort=date&limit=5")
          assert.is_not_nil resource
          assert.equal "app://api/items{?sort,limit}", resource.uriTemplate

        it "should handle mixed path and query parameters", ->
          class MixedTemplateServer extends McpServer
            @add_resource {
              uriTemplate: "app://posts/{postId}/comments{?limit,offset}"
              name: "Post Comments"
              description: "Comments for a specific post"
              mimeType: "application/json"
            }, (params) => {
              post_id: params.postId
              limit: tonumber(params.limit) or 20
              offset: tonumber(params.offset) or 0
              comments: {"comment1", "comment2"}
            }

          server = MixedTemplateServer!
          resource = server\find_resource("app://posts/123/comments?limit=10")
          assert.is_not_nil resource
          assert.equal "app://posts/{postId}/comments{?limit,offset}", resource.uriTemplate

      describe "template resource resolution", ->
        local server
        before_each ->
          class TemplateTestServer extends McpServer
            @add_resource {
              uri: "app://static/resource"
              name: "Static Resource"
              description: "A static resource"
              mimeType: "text/plain"
            }, -> "Static content"

            @add_resource {
              uriTemplate: "app://users/{userId}"
              name: "User Resource"
              description: "Dynamic user resource"
              mimeType: "application/json"
            }, (params) => {
              id: params.userId
              name: "User #{params.userId}"
              type: "user"
            }

            @add_resource {
              uriTemplate: "app://users/{userId}/posts/{postId}"
              name: "User Post"
              description: "Specific user post"
              mimeType: "application/json"
            }, (params) => {
              user_id: params.userId
              post_id: params.postId
              title: "Post #{params.postId} by User #{params.userId}"
            }

            @add_resource {
              uriTemplate: "app://search{?q,limit}"
              name: "Search API"
              description: "Search with query parameters"
              mimeType: "application/json"
            }, (params) => {
              query: params.q or ""
              limit: tonumber(params.limit) or 10
              results: {"result1", "result2"}
            }

          server = TemplateTestServer!
          server\skip_initialize!

        it "should prioritize exact URI matches over templates", ->
          resource = server\find_resource("app://static/resource")
          assert.is_not_nil resource
          assert.equal "app://static/resource", resource.uri
          assert.is_nil resource.uriTemplate

        it "should match single parameter templates", ->
          resource = server\find_resource("app://users/123")
          assert.is_not_nil resource
          assert.equal "app://users/{userId}", resource.uriTemplate

        it "should match multiple parameter templates", ->
          resource = server\find_resource("app://users/123/posts/456")
          assert.is_not_nil resource
          assert.equal "app://users/{userId}/posts/{postId}", resource.uriTemplate

        it "should match query parameter templates", ->
          resource = server\find_resource("app://search?q=test&limit=5")
          assert.is_not_nil resource
          assert.equal "app://search{?q,limit}", resource.uriTemplate

        it "should return nil for non-matching URIs", ->
          resource = server\find_resource("app://nonexistent/resource")
          assert.is_nil resource

        it "should handle partial query parameter matches", ->
          resource = server\find_resource("app://search?q=test")
          assert.is_not_nil resource
          assert.equal "app://search{?q,limit}", resource.uriTemplate

      describe "template resource reading", ->
        local server
        before_each ->
          class ReadTemplateServer extends McpServer
            @add_resource {
              uriTemplate: "app://users/{userId}"
              name: "User Resource"
              description: "User data"
              mimeType: "application/json"
            }, (params) => {
              id: params.userId
              name: "User #{params.userId}"
              email: "user#{params.userId}@example.com"
            }

            @add_resource {
              uriTemplate: "app://files/{path}"
              name: "File Resource"
              description: "File content"
              mimeType: "text/plain"
            }, (params) => "File content for #{params.path}"

            @add_resource {
              uriTemplate: "app://api/data{?format}"
              name: "Data API"
              description: "Data with optional format"
              mimeType: "application/json"
            }, (params) =>
              data = {items: {"a", "b", "c"}}
              if params.format == "xml"
                return "<items><item>a</item><item>b</item><item>c</item></items>"
              data

            @add_resource {
              uriTemplate: "app://error/{type}"
              name: "Error Resource"
              description: "Resource that can error"
              mimeType: "text/plain"
            }, (params) =>
              if params.type == "fail"
                return nil, "Intentional error"
              "Success for #{params.type}"

          server = ReadTemplateServer!
          server\skip_initialize!

        it "should read template resource with parameters", ->
          response = server\handle_resources_read {
            jsonrpc: "2.0"
            id: 1
            method: "resources/read"
            params: {
              uri: "app://users/123"
            }
          }

          assert.equal "2.0", response.jsonrpc
          assert.equal 1, response.id
          assert.is_table response.result
          assert.is_table response.result.contents
          assert.equal 1, #response.result.contents

          content = response.result.contents[1]
          assert.equal "app://users/123", content.uri
          assert.equal "application/json", content.mimeType

          decoded = json.decode(content.text)
          assert.same {
            id: "123"
            name: "User 123"
            email: "user123@example.com"
          }, decoded

        it "should read template resource with path parameters", ->
          response = server\handle_resources_read {
            jsonrpc: "2.0"
            id: 1
            method: "resources/read"
            params: {
              uri: "app://files/document.txt"
            }
          }

          assert.equal "2.0", response.jsonrpc
          assert.equal 1, response.id
          content = response.result.contents[1]
          assert.equal "app://files/document.txt", content.uri
          assert.equal "text/plain", content.mimeType
          assert.equal "File content for document.txt", content.text

        it "should read template resource with query parameters", ->
          response = server\handle_resources_read {
            jsonrpc: "2.0"
            id: 1
            method: "resources/read"
            params: {
              uri: "app://api/data?format=json"
            }
          }

          assert.equal "2.0", response.jsonrpc
          assert.equal 1, response.id
          content = response.result.contents[1]
          assert.equal "app://api/data?format=json", content.uri

          decoded = json.decode(content.text)
          assert.same {items: {"a", "b", "c"}}, decoded

        it "should handle template resource returning string", ->
          response = server\handle_resources_read {
            jsonrpc: "2.0"
            id: 1
            method: "resources/read"
            params: {
              uri: "app://api/data?format=xml"
            }
          }

          content = response.result.contents[1]
          assert.equal "<items><item>a</item><item>b</item><item>c</item></items>", content.text

        it "should handle template resource errors", ->
          response = server\handle_resources_read {
            jsonrpc: "2.0"
            id: 1
            method: "resources/read"
            params: {
              uri: "app://error/fail"
            }
          }

          assert.same {
            jsonrpc: "2.0"
            id: 1
            error: {
              code: -32603
              message: "Error reading resource: Intentional error"
            }
          }, response

        it "should handle template resource success", ->
          response = server\handle_resources_read {
            jsonrpc: "2.0"
            id: 1
            method: "resources/read"
            params: {
              uri: "app://error/success"
            }
          }

          content = response.result.contents[1]
          assert.equal "Success for success", content.text

      describe "template resource listing", ->
        local server
        before_each ->
          class ListTemplateServer extends McpServer
            @add_resource {
              uri: "app://static/resource"
              name: "Static Resource"
              description: "A static resource"
              mimeType: "text/plain"
            }, -> "Static content"

            @add_resource {
              uriTemplate: "app://users/{userId}"
              name: "User Resource"
              description: "Dynamic user resource"
              mimeType: "application/json"
            }, (params) => {id: params.userId}

            @add_resource {
              uriTemplate: "app://posts/{postId}/comments{?limit}"
              name: "Post Comments"
              description: "Comments for a post"
              mimeType: "application/json"
              hidden: true
            }, (params) => {comments: {}}

          server = ListTemplateServer!
          server\skip_initialize!

        it "should list only non-template resources in resources/list", ->
          response = server\handle_resources_list {
            jsonrpc: "2.0"
            id: 1
            method: "resources/list"
          }
          assert.same {
            id: 1,
            jsonrpc: "2.0",
            result: {
              resources: {
                {
                  description: "A static resource",
                  mimeType: "text/plain",
                  name: "Static Resource",
                  uri: "app://static/resource"
                }
              }
            }
          }, response

        it "should return correct list for resources/templates/list", ->
          server\skip_initialize!
          response = server\handle_resources_templates_list {
            jsonrpc: "2.0"
            id: 1
            method: "resources/templates/list"
          }

          assert.same {
            id: 1,
            jsonrpc: "2.0",
            result: {
              resourceTemplates: {
                {
                  description: "Dynamic user resource",
                  mimeType: "application/json",
                  name: "User Resource",
                  uriTemplate: "app://users/{userId}"
                }
              }
            }
          }, response

      describe "template resource inheritance", ->
        it "should handle template resource inheritance", ->
          class BaseTemplateServer extends McpServer
            @add_resource {
              uriTemplate: "app://base/{id}"
              name: "Base Resource"
              description: "Base template resource"
              mimeType: "text/plain"
            }, (params) => "Base #{params.id}"

          class DerivedTemplateServer extends BaseTemplateServer
            @add_resource {
              uriTemplate: "app://derived/{id}"
              name: "Derived Resource"
              description: "Derived template resource"
              mimeType: "text/plain"
            }, (params) => "Derived #{params.id}"

            @add_resource {
              uriTemplate: "app://base/{id}"
              name: "Overridden Base"
              description: "Overridden base resource"
              mimeType: "text/plain"
            }, (params) => "Overridden #{params.id}"

          server = DerivedTemplateServer!
          server\skip_initialize!

          -- Should find overridden base resource
          response = server\handle_resources_read {
            jsonrpc: "2.0"
            id: 1
            method: "resources/read"
            params: {uri: "app://base/123"}
          }
          content = response.result.contents[1]
          assert.equal "Overridden 123", content.text

          -- Should find derived resource
          response = server\handle_resources_read {
            jsonrpc: "2.0"
            id: 2
            method: "resources/read"
            params: {uri: "app://derived/456"}
          }
          content = response.result.contents[1]
          assert.equal "Derived 456", content.text

      describe "advanced template patterns", ->
        local server
        before_each ->
          class AdvancedTemplateServer extends McpServer
            @add_resource {
              uriTemplate: "app://api/v{version}/users/{userId}"
              name: "Versioned User API"
              description: "User API with version"
              mimeType: "application/json"
            }, (params) => {
              version: params.version
              user_id: params.userId
              api_version: "v#{params.version}"
            }

            @add_resource {
              uriTemplate: "app://files/{path}/{filename}.{ext}"
              name: "File Resource"
              description: "File with path and extension"
              mimeType: "text/plain"
            }, (params) => "File: #{params.path}/#{params.filename}.#{params.ext}"

            @add_resource {
              uriTemplate: "app://search{?q,sort,limit,offset}"
              name: "Advanced Search"
              description: "Search with multiple query parameters"
              mimeType: "application/json"
            }, (params) => {
              query: params.q or ""
              sort: params.sort or "relevance"
              limit: tonumber(params.limit) or 10
              offset: tonumber(params.offset) or 0
            }

          server = AdvancedTemplateServer!
          server\skip_initialize!

        it "should handle versioned API templates", ->
          response = server\handle_resources_read {
            jsonrpc: "2.0"
            id: 1
            method: "resources/read"
            params: {uri: "app://api/v2/users/123"}
          }

          content = response.result.contents[1]
          decoded = json.decode(content.text)
          assert.same {
            version: "2"
            user_id: "123"
            api_version: "v2"
          }, decoded

        it "should handle file path templates", ->
          response = server\handle_resources_read {
            jsonrpc: "2.0"
            id: 1
            method: "resources/read"
            params: {uri: "app://files/docs/readme.txt"}
          }

          content = response.result.contents[1]
          assert.equal "File: docs/readme.txt", content.text

        it "should handle complex query parameter templates", ->
          response = server\handle_resources_read {
            jsonrpc: "2.0"
            id: 1
            method: "resources/read"
            params: {uri: "app://search?q=test&sort=date&limit=5&offset=10"}
          }

          content = response.result.contents[1]
          decoded = json.decode(content.text)
          assert.same {
            query: "test"
            sort: "date"
            limit: 5
            offset: 10
          }, decoded

        it "should handle partial query parameters", ->
          response = server\handle_resources_read {
            jsonrpc: "2.0"
            id: 1
            method: "resources/read"
            params: {uri: "app://search?q=test"}
          }

          content = response.result.contents[1]
          decoded = json.decode(content.text)
          assert.same {
            query: "test"
            sort: "relevance"
            limit: 10
            offset: 0
          }, decoded

describe "LapisMcpServer", ->
  LapisMcpServer = require "lapis.mcp.lapis_server"

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
    server = LapisMcpServer {
      app: mock_app
    }

  it "get_all_tools", ->
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

  it "find_tool", ->
    tool = server\find_tool("list_routes")
    assert.is_not_nil tool
    assert.equal "list_routes", tool.name
    assert.equal "List Routes", tool.annotations.title

  describe "routes tool", ->
    before_each ->
      server\skip_initialize!

    it "should extract routes from app via full tool call", ->
      -- Call list_routes tool through the full MCP flow
      response = server\handle_tools_call {
        jsonrpc: "2.0"
        id: 2
        method: "tools/call"
        params: {
          name: "list_routes"
          arguments: {}
        }
      }

      assert.equal "2.0", response.jsonrpc
      assert.equal 2, response.id
      assert.is_table response.result
      assert.is_false response.result.isError
      assert.is_table response.result.content
      assert.equal "text", response.result.content[1].type

      -- Parse the JSON response to check the actual routes
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

