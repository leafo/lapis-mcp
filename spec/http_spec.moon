lapis = require "lapis"
json = require "cjson"

import McpServer from require "lapis.mcp.server"
import mcp_handler from require "lapis.mcp.http"
import simulate_request from require "lapis.spec.request"

class TestServer extends McpServer
  @server_name: "test-server"

  @add_tool {
    name: "hello"
    description: "Says hello"
    inputSchema: { type: "object", properties: {}, required: setmetatable({}, json.array_mt) }
  }, (params) => "world"

build_app = (opts) ->
  class TestApp extends lapis.Application
    layout: false
    "/mcp": mcp_handler TestServer, opts

describe "mcp_handler", ->
  describe "POST", ->
    it "handles initialize request", ->
      app = build_app!
      status, body = simulate_request app, "/mcp", {
        method: "POST"
        headers: {
          "Accept": "application/json, text/event-stream"
          "Content-Type": "application/json"
        }
        body: json.encode {
          jsonrpc: "2.0"
          id: 1
          method: "initialize"
          params: {
            protocolVersion: "2025-11-25"
            capabilities: {}
            clientInfo: { name: "test-client", version: "1.0" }
          }
        }
      }

      assert.equal 200, status
      result = json.decode body
      assert.equal "2.0", result.jsonrpc
      assert.equal 1, result.id
      assert.equal "2025-11-25", result.result.protocolVersion
      assert.equal "test-server", result.result.serverInfo.name

    it "handles tools/list request", ->
      app = build_app!
      status, body = simulate_request app, "/mcp", {
        method: "POST"
        headers: {
          "Accept": "application/json, text/event-stream"
          "Content-Type": "application/json"
        }
        body: json.encode {
          jsonrpc: "2.0"
          id: 2
          method: "tools/list"
        }
      }

      assert.equal 200, status
      result = json.decode body
      assert.equal 2, result.id
      tools = result.result.tools
      assert.equal 1, #tools
      assert.equal "hello", tools[1].name

    it "handles tools/call request", ->
      app = build_app!
      status, body = simulate_request app, "/mcp", {
        method: "POST"
        headers: {
          "Accept": "application/json, text/event-stream"
          "Content-Type": "application/json"
        }
        body: json.encode {
          jsonrpc: "2.0"
          id: 3
          method: "tools/call"
          params: {
            name: "hello"
            arguments: {}
          }
        }
      }

      assert.equal 200, status
      result = json.decode body
      assert.equal 3, result.id
      assert.is_false result.result.isError

    it "returns 202 for notification", ->
      app = build_app!
      status, body = simulate_request app, "/mcp", {
        method: "POST"
        headers: {
          "Accept": "application/json, text/event-stream"
          "Content-Type": "application/json"
        }
        body: json.encode {
          jsonrpc: "2.0"
          method: "notifications/initialized"
        }
      }

      assert.equal 202, status

    it "returns 400 for invalid JSON", ->
      app = build_app!
      status, body = simulate_request app, "/mcp", {
        method: "POST"
        headers: {
          "Accept": "application/json, text/event-stream"
          "Content-Type": "application/json"
        }
        body: "not json {"
      }

      assert.equal 400, status
      result = json.decode body
      assert.equal -32700, result.error.code

    it "returns 400 for empty body", ->
      app = build_app!
      status, body = simulate_request app, "/mcp", {
        method: "POST"
        headers: {
          "Accept": "application/json, text/event-stream"
          "Content-Type": "application/json"
        }
      }

      assert.equal 400, status

    it "returns 406 for missing Accept header", ->
      app = build_app!
      status, body = simulate_request app, "/mcp", {
        method: "POST"
        headers: {
          "Content-Type": "application/json"
        }
        body: json.encode {
          jsonrpc: "2.0"
          id: 1
          method: "initialize"
        }
      }

      assert.equal 406, status

    it "returns 406 for incomplete Accept header", ->
      app = build_app!
      status, body = simulate_request app, "/mcp", {
        method: "POST"
        headers: {
          "Accept": "application/json"
          "Content-Type": "application/json"
        }
        body: json.encode {
          jsonrpc: "2.0"
          id: 1
          method: "initialize"
        }
      }

      assert.equal 406, status

  describe "batch requests", ->
    it "handles batch of requests", ->
      app = build_app!
      status, body = simulate_request app, "/mcp", {
        method: "POST"
        headers: {
          "Accept": "application/json, text/event-stream"
          "Content-Type": "application/json"
        }
        body: json.encode {
          {jsonrpc: "2.0", id: 1, method: "tools/list"}
          {jsonrpc: "2.0", id: 2, method: "ping"}
        }
      }

      assert.equal 200, status
      result = json.decode body
      assert.equal 2, #result
      assert.equal 1, result[1].id
      assert.equal 2, result[2].id

    it "returns 202 for batch of only notifications", ->
      app = build_app!
      status = simulate_request app, "/mcp", {
        method: "POST"
        headers: {
          "Accept": "application/json, text/event-stream"
          "Content-Type": "application/json"
        }
        body: json.encode {
          {jsonrpc: "2.0", method: "notifications/initialized"}
        }
      }

      assert.equal 202, status

  describe "origin validation", ->
    it "rejects requests with Origin header when no allowed_origins configured", ->
      app = build_app!
      status, body, headers = simulate_request app, "/mcp", {
        method: "POST"
        headers: {
          "Accept": "application/json, text/event-stream"
          "Origin": "https://evil.com"
        }
        body: json.encode {jsonrpc: "2.0", id: 1, method: "ping"}
      }

      assert.equal 403, status
      assert.equal "Origin", headers["vary"]

    it "allows requests without Origin header", ->
      app = build_app!
      status = simulate_request app, "/mcp", {
        method: "POST"
        headers: {
          "Accept": "application/json, text/event-stream"
        }
        body: json.encode {jsonrpc: "2.0", id: 1, method: "ping"}
      }

      assert.equal 200, status

    it "allows all origins with wildcard", ->
      app = build_app allowed_origins: "*"
      status, body, headers = simulate_request app, "/mcp", {
        method: "POST"
        headers: {
          "Accept": "application/json, text/event-stream"
          "Origin": "https://anything.com"
        }
        body: json.encode {jsonrpc: "2.0", id: 1, method: "ping"}
      }

      assert.equal 200, status
      assert.equal "*", headers["access_control_allow_origin"]
      assert.equal "Origin", headers["vary"]
      assert.equal "Mcp-Session-Id", headers["access_control_expose_headers"]

    it "allows listed origin", ->
      app = build_app allowed_origins: {"https://good.com"}
      status, body, headers = simulate_request app, "/mcp", {
        method: "POST"
        headers: {
          "Accept": "application/json, text/event-stream"
          "Origin": "https://good.com"
        }
        body: json.encode {jsonrpc: "2.0", id: 1, method: "ping"}
      }

      assert.equal 200, status
      assert.equal "https://good.com", headers["access_control_allow_origin"]
      assert.equal "POST, OPTIONS", headers["access_control_allow_methods"]
      assert.equal "Content-Type, Accept, Mcp-Session-Id", headers["access_control_allow_headers"]

    it "rejects unlisted origin", ->
      app = build_app allowed_origins: {"https://good.com"}
      status, body, headers = simulate_request app, "/mcp", {
        method: "POST"
        headers: {
          "Accept": "application/json, text/event-stream"
          "Origin": "https://evil.com"
        }
        body: json.encode {jsonrpc: "2.0", id: 1, method: "ping"}
      }

      assert.equal 403, status
      assert.equal "Origin", headers["vary"]

    it "handles CORS preflight for allowed origin", ->
      app = build_app allowed_origins: {"https://good.com"}
      status, body, headers = simulate_request app, "/mcp", {
        method: "OPTIONS"
        headers: {
          "Origin": "https://good.com"
          "Access-Control-Request-Method": "POST"
          "Access-Control-Request-Headers": "Content-Type, Accept, Mcp-Session-Id"
        }
      }

      assert.equal 204, status
      assert.equal "https://good.com", headers["access_control_allow_origin"]
      assert.equal "POST, OPTIONS", headers["access_control_allow_methods"]
      assert.equal "Content-Type, Accept, Mcp-Session-Id", headers["access_control_allow_headers"]
      assert.equal "Mcp-Session-Id", headers["access_control_expose_headers"]

    it "rejects CORS preflight for disallowed origin", ->
      app = build_app allowed_origins: {"https://good.com"}
      status, body, headers = simulate_request app, "/mcp", {
        method: "OPTIONS"
        headers: {
          "Origin": "https://evil.com"
          "Access-Control-Request-Method": "POST"
        }
      }

      assert.equal 403, status
      assert.equal "Origin", headers["vary"]

  describe "create_session_id", ->
    it "sets Mcp-Session-Id header on initialize response", ->
      app = build_app {
        create_session_id: (req, server) -> "test-session-123"
      }

      status, body, headers = simulate_request app, "/mcp", {
        method: "POST"
        headers: {
          "Accept": "application/json, text/event-stream"
        }
        body: json.encode {
          jsonrpc: "2.0"
          id: 1
          method: "initialize"
          params: {
            protocolVersion: "2025-11-25"
            capabilities: {}
            clientInfo: { name: "test", version: "1.0" }
          }
        }
      }

      assert.equal 200, status
      assert.equal "test-session-123", headers["Mcp-Session-Id"]

    it "does not set header on non-initialize requests", ->
      app = build_app {
        create_session_id: (req, server) -> "should-not-appear"
      }

      status, body, headers = simulate_request app, "/mcp", {
        method: "POST"
        headers: {
          "Accept": "application/json, text/event-stream"
        }
        body: json.encode {jsonrpc: "2.0", id: 1, method: "ping"}
      }

      assert.equal 200, status
      assert.is_nil headers["Mcp-Session-Id"]

  describe "load_session", ->
    it "calls load_session with request and server", ->
      captured = {}
      app = build_app {
        load_session: (req, server) ->
          captured.called = true
          captured.server = server
      }

      status = simulate_request app, "/mcp", {
        method: "POST"
        headers: {
          "Accept": "application/json, text/event-stream"
        }
        body: json.encode {jsonrpc: "2.0", id: 1, method: "ping"}
      }

      assert.equal 200, status
      assert.is_true captured.called
      assert.is_not_nil captured.server

    it "allows load_session to modify server state", ->
      app = build_app {
        load_session: (req, server) ->
          server\set_tool_visibility "hello", false
      }

      status, body = simulate_request app, "/mcp", {
        method: "POST"
        headers: {
          "Accept": "application/json, text/event-stream"
        }
        body: json.encode {jsonrpc: "2.0", id: 1, method: "tools/list"}
      }

      assert.equal 200, status
      result = json.decode body
      assert.equal 0, #result.result.tools

  describe "GET", ->
    it "returns 405", ->
      app = build_app!
      status = simulate_request app, "/mcp", {
        method: "GET"
      }

      assert.equal 405, status

  describe "DELETE", ->
    it "returns 405", ->
      app = build_app!
      status = simulate_request app, "/mcp", {
        method: "DELETE"
      }

      assert.equal 405, status
