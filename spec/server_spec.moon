import McpServer, StdioTransport from require "lapis.mcp.server"

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
    server = McpServer(mock_app)

  describe "initialization", ->
    it "should create server with proper defaults", ->
      assert.is_not_nil server
      assert.equal "2025-06-18", server.protocol_version
      assert.is_false server.initialized
      assert.is_false server.debug
      assert.is_table server.tools
      assert.is_table server.server_capabilities
      assert.is_table server.client_capabilities

    it "should have expected tools configured", ->
      assert.is_not_nil server.tools.routes
      assert.is_not_nil server.tools.models
      assert.is_not_nil server.tools.schema
      
      -- Check routes tool structure
      routes_tool = server.tools.routes
      assert.equal "routes", routes_tool.name
      assert.equal "List Routes", routes_tool.title
      assert.is_string routes_tool.description
      assert.is_table routes_tool.inputSchema
      assert.is_function routes_tool.handler

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

      assert.is_true tool_names["routes"]
      assert.is_true tool_names["models"]
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
      uninit_server = McpServer(mock_app)
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

    it "should call routes tool successfully", ->
      message = {
        jsonrpc: "2.0"
        id: 3
        method: "tools/call"
        params: {
          name: "routes"
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
      assert.equal 3, #routes_data

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

      -- Call routes tool through the full MCP flow
      call_message = {
        jsonrpc: "2.0"
        id: 2
        method: "tools/call"
        params: {
          name: "routes"
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