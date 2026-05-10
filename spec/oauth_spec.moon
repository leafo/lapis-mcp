lapis = require "lapis"
json = require "cjson"

oauth_shim = require "lapis.mcp.oauth"
import encode_query_string, parse_query_string from require "lapis.util"
import simulate_request from require "lapis.spec.request"

oauth_opts = {
  client_id: "connector-client"
  client_secret: "connector-secret"
}

build_app = (path="/mcp", opts=oauth_opts) ->
  class TestApp extends lapis.Application
    layout: false

  config = oauth_shim.OauthConfig opts, path
  for route in *config\routes!
    TestApp\match route.path, route.handler

  TestApp

describe "oauth shim", ->
  it "serves protected resource metadata route", ->
    app = build_app "/mcp"

    status, body = simulate_request app, "/.well-known/oauth-protected-resource/mcp", {
      headers: {
        "Host": "example.com"
        "X-Forwarded-Proto": "https"
      }
    }

    assert.equal 200, status
    result = json.decode body
    assert.equal "https://example.com/mcp", result.resource
    assert.same {"https://example.com/mcp"}, result.authorization_servers

  it "uses configured protected resource URL", ->
    app = build_app "/mcp", {
      client_id: "connector-client"
      client_secret: "connector-secret"
      resource: "https://resource.example/mcp"
    }

    status, body = simulate_request app, "/.well-known/oauth-protected-resource/mcp", {
      headers: {
        "Host": "example.com"
        "X-Forwarded-Proto": "https"
      }
    }

    assert.equal 200, status
    result = json.decode body
    assert.equal "https://resource.example/mcp", result.resource

  it "uses public base URL for derived OAuth metadata URLs", ->
    app = build_app "/mcp", {
      client_id: "connector-client"
      client_secret: "connector-secret"
      public_base_url: "https://public.example"
    }

    status, body = simulate_request app, "/.well-known/oauth-protected-resource/mcp", {
      headers: {
        "Host": "internal.example"
        "X-Forwarded-Proto": "http"
      }
    }

    assert.equal 200, status
    result = json.decode body
    assert.equal "https://public.example/mcp", result.resource
    assert.same {"https://public.example/mcp"}, result.authorization_servers

    status, body = simulate_request app, "/.well-known/oauth-authorization-server/mcp", {
      headers: {
        "Host": "internal.example"
        "X-Forwarded-Proto": "http"
      }
    }

    assert.equal 200, status
    result = json.decode body
    assert.equal "https://public.example/mcp", result.issuer
    assert.equal "https://public.example/mcp/oauth/authorize", result.authorization_endpoint
    assert.equal "https://public.example/mcp/oauth/token", result.token_endpoint

  it "serves authorization server metadata", ->
    app = build_app "/mcp"
    status, body = simulate_request app, "/.well-known/oauth-authorization-server/mcp", {
      headers: {
        "Host": "example.com"
        "X-Forwarded-Proto": "https"
      }
    }

    assert.equal 200, status
    result = json.decode body
    assert.equal "https://example.com/mcp", result.issuer
    assert.equal "https://example.com/mcp/oauth/authorize", result.authorization_endpoint
    assert.equal "https://example.com/mcp/oauth/token", result.token_endpoint
    assert.same {"client_secret_post", "client_secret_basic"}, result.token_endpoint_auth_methods_supported

  it "serves authorization redirects", ->
    app = build_app "/mcp"
    redirect_uri = "https://client.example/callback"
    status, body, headers = simulate_request app, "/mcp/oauth/authorize?#{encode_query_string {
      response_type: "code"
      client_id: "connector-client"
      redirect_uri: redirect_uri
      state: "test-state"
    }}"

    assert.equal 302, status
    assert.is_string headers.location
    assert.equal redirect_uri, headers.location\match "^[^?]+"
    redirect_params = parse_query_string headers.location\match "%?(.*)$"
    assert.equal "test-state", redirect_params.state
    assert.is_not_nil redirect_params.code

  it "serves token endpoint preflight", ->
    app = build_app "/mcp"
    status, body, headers = simulate_request app, "/mcp/oauth/token", {
      method: "OPTIONS"
    }

    assert.equal 204, status
    assert.equal "*", headers["Access-Control-Allow-Origin"]
    assert.equal "POST, OPTIONS", headers["Access-Control-Allow-Methods"]

  it "decodes form-encoded client_secret_basic credentials", ->
    app = build_app "/", {
      client_id: "connector client"
      client_secret: "secret:value"
    }
    basic = "Y29ubmVjdG9yK2NsaWVudDpzZWNyZXQlM0F2YWx1ZQ=="

    status, body = simulate_request app, "/oauth/token", {
      method: "POST"
      headers: {
        "Content-Type": "application/x-www-form-urlencoded"
        "Authorization": "Basic #{basic}"
      }
      body: encode_query_string {
        grant_type: "client_credentials"
      }
    }

    assert.equal 200, status
    result = json.decode body
    assert.equal "secret:value", result.access_token
    assert.equal "Bearer", result.token_type
