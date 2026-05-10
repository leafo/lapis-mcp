lapis = require "lapis"
json = require "cjson"

import McpServer from require "lapis.mcp.server"
import mcp_handler, McpHttpRouter from require "lapis.mcp.http"
import simulate_request from require "lapis.spec.request"

class TestServer extends McpServer
  @server_name: "test-server"

  @add_tool {
    name: "hello"
    description: "Says hello"
    inputSchema: { type: "object", properties: {}, required: setmetatable({}, json.array_mt) }
  }, (params) => "world"

class OtherTestServer extends McpServer
  @server_name: "other-test-server"

build_app = (opts) ->
  class TestApp extends lapis.Application
    layout: false
    "/mcp": mcp_handler TestServer, opts

build_router_app = (mounts) ->
  class TestApp extends lapis.Application
    layout: false

  router = McpHttpRouter!
  for mount in *mounts
    router\mount mount.path, mount.server or TestServer, mount.opts or {}
  router\install TestApp

  TestApp

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
      assert.equal "Mcp-Session-Id, WWW-Authenticate", headers["access_control_expose_headers"]

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
      assert.equal "Content-Type, Accept, Mcp-Session-Id, Authorization", headers["access_control_allow_headers"]

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
      assert.equal "Content-Type, Accept, Mcp-Session-Id, Authorization", headers["access_control_allow_headers"]
      assert.equal "Mcp-Session-Id, WWW-Authenticate", headers["access_control_expose_headers"]

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

  describe "oauth", ->
    it "uses public base URL in bearer challenge metadata URL", ->
      app = build_app {
        oauth: {
          client_id: "connector-client"
          client_secret: "connector-secret"
          public_base_url: "https://public.example"
        }
        path: "/mcp"
      }

      status, body, headers = simulate_request app, "/mcp", {
        method: "POST"
        headers: {
          "Accept": "application/json, text/event-stream"
          "Host": "internal.example"
          "X-Forwarded-Proto": "http"
        }
        body: json.encode {jsonrpc: "2.0", id: 1, method: "ping"}
      }

      assert.equal 401, status
      assert.equal 'Bearer realm="mcp", resource_metadata="https://public.example/.well-known/oauth-protected-resource/mcp"', headers["WWW-Authenticate"]

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

describe "McpHttpRouter", ->
  https_headers = {
    "Host": "example.com"
    "X-Forwarded-Proto": "https"
  }

  it "installs oauth routes under the MCP mount path", ->
    app = build_router_app {
      {
        path: "/mcp"
        opts: {
          oauth: {
            client_id: "one"
            client_secret: "secret-one"
          }
        }
      }
    }

    status, body = simulate_request app, "/.well-known/oauth-authorization-server/mcp", headers: https_headers
    assert.equal 200, status
    result = json.decode body
    assert.equal "https://example.com/mcp/oauth/authorize", result.authorization_endpoint
    assert.equal "https://example.com/mcp/oauth/token", result.token_endpoint

    status, body = simulate_request app, "/.well-known/oauth-protected-resource/mcp", headers: https_headers
    assert.equal 200, status
    result = json.decode body
    assert.equal "https://example.com/mcp", result.resource

  it "installs distinct oauth routes for multiple oauth mounts", ->
    app = build_router_app {
      {
        path: "/mcp-one"
        server: TestServer
        opts: {
          oauth: {
            client_id: "one"
            client_secret: "secret-one"
          }
        }
      }
      {
        path: "/mcp-two"
        server: OtherTestServer
        opts: {
          oauth: {
            client_id: "two"
            client_secret: "secret-two"
          }
        }
      }
    }

    status, body = simulate_request app, "/.well-known/oauth-authorization-server/mcp-one", headers: https_headers
    assert.equal 200, status
    result = json.decode body
    assert.equal "https://example.com/mcp-one", result.issuer
    assert.equal "https://example.com/mcp-one/oauth/authorize", result.authorization_endpoint
    assert.equal "https://example.com/mcp-one/oauth/token", result.token_endpoint

    status, body = simulate_request app, "/.well-known/oauth-protected-resource/mcp-two", headers: https_headers
    assert.equal 200, status
    result = json.decode body
    assert.equal "https://example.com/mcp-two", result.resource
    assert.same {"https://example.com/mcp-two"}, result.authorization_servers

    status, body = simulate_request app, "/mcp-two/oauth/token", {
      method: "POST"
      headers: {
        "Content-Type": "application/x-www-form-urlencoded"
      }
      body: "grant_type=client_credentials&client_id=two&client_secret=secret-two"
    }
    assert.equal 200, status
    result = json.decode body
    assert.equal "secret-two", result.access_token

  it "scopes oauth routes when only one mount has oauth", ->
    app = build_router_app {
      {
        path: "/public"
        server: TestServer
      }
      {
        path: "/mcp"
        server: OtherTestServer
        opts: {
          oauth: {
            client_id: "one"
            client_secret: "secret-one"
          }
        }
      }
    }

    status, body = simulate_request app, "/.well-known/oauth-authorization-server/mcp", headers: https_headers
    assert.equal 200, status
    result = json.decode body
    assert.equal "https://example.com/mcp/oauth/token", result.token_endpoint

  it "raises on route collisions", ->
    assert.has_error ->
      build_router_app {
        { path: "/mcp" }
        { path: "/mcp" }
      }

    assert.has_error ->
      build_router_app {
        {
          path: "/mcp"
          opts: {
            oauth: {
              client_id: "one"
              client_secret: "secret-one"
            }
          }
        }
        {
          path: "/mcp/oauth/token"
        }
      }

  it "routes MCP POST requests through router-installed handlers", ->
    app = build_router_app {
      { path: "/mcp-one", server: TestServer }
      { path: "/mcp-two", server: OtherTestServer }
    }

    status, body = simulate_request app, "/mcp-one", {
      method: "POST"
      headers: {
        "Accept": "application/json, text/event-stream"
        "Content-Type": "application/json"
      }
      body: json.encode {
        jsonrpc: "2.0"
        id: 1
        method: "tools/call"
        params: { name: "hello", arguments: {} }
      }
    }

    assert.equal 200, status
    result = json.decode body
    assert.equal "world", result.result.content[1].text

  it "normalizes trailing slashes on mount paths", ->
    app = build_router_app {
      { path: "/mcp/", server: TestServer }
    }

    status, body = simulate_request app, "/mcp", {
      method: "POST"
      headers: {
        "Accept": "application/json, text/event-stream"
        "Content-Type": "application/json"
      }
      body: json.encode {
        jsonrpc: "2.0"
        id: 1
        method: "tools/list"
      }
    }

    assert.equal 200, status
    result = json.decode body
    assert.equal "hello", result.result.tools[1].name
