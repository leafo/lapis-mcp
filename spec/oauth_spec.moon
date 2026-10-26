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

VERIFIER = "test-code-verifier-0123456789-abcdefghijklmnopqrstuvwxyz"

s256_challenge = (verifier) ->
  import encode_base64 from require "lapis.util.encoding"
  digest = require "openssl.digest"
  h = digest.new "sha256"
  h\update verifier
  (encode_base64(h\final!)\gsub("+", "-")\gsub("/", "_")\gsub("=", ""))

-- params set to false are left out of the request
authorize = (app, params={}) ->
  args = {
    response_type: "code"
    client_id: "connector-client"
    redirect_uri: "https://client.example/callback"
    code_challenge: s256_challenge VERIFIER
    code_challenge_method: "S256"
  }
  for k, v in pairs params
    args[k] = v or nil

  simulate_request app, "/mcp/oauth/authorize?#{encode_query_string args}", {
    headers: {
      "Host": "example.com"
      "X-Forwarded-Proto": "https"
    }
  }

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
    status, body, headers = authorize app, {
      redirect_uri: redirect_uri
      state: "test-state"
    }

    assert.equal 302, status
    assert.is_string headers.location
    assert.equal redirect_uri, headers.location\match "^[^?]+"
    redirect_params = parse_query_string headers.location\match "%?(.*)$"
    assert.equal "test-state", redirect_params.state
    assert.is_not_nil redirect_params.code
    assert.equal "https://example.com/mcp", redirect_params.iss

  it "advertises only S256 PKCE and the iss parameter", ->
    app = build_app "/mcp"
    status, body = simulate_request app, "/.well-known/oauth-authorization-server/mcp"

    assert.equal 200, status
    result = json.decode body
    assert.same {"S256"}, result.code_challenge_methods_supported
    assert.is_true result.authorization_response_iss_parameter_supported

  describe "authorize errors", ->
    -- returns the params of an error redirect back to the client
    redirected_error = (status, headers) ->
      assert.equal 302, status
      assert.equal "https://client.example/callback", headers.location\match "^[^?]+"
      params = parse_query_string headers.location\match "%?(.*)$"
      assert.is_nil params.code
      params

    it "redirects with an error when the PKCE code_challenge is missing", ->
      app = build_app "/mcp"
      status, body, headers = authorize app, {
        code_challenge: false
        code_challenge_method: false
        state: "test-state"
      }

      params = redirected_error status, headers
      assert.equal "invalid_request", params.error
      assert.equal "PKCE code_challenge is required", params.error_description
      assert.equal "test-state", params.state
      assert.equal "https://example.com/mcp", params.iss

    it "redirects with an error for plain and missing code_challenge_method", ->
      app = build_app "/mcp"
      for method in *{"plain", false}
        status, body, headers = authorize app, { code_challenge_method: method }

        params = redirected_error status, headers
        assert.equal "code_challenge_method must be S256", params.error_description

    it "redirects with an error for a malformed S256 challenge", ->
      app = build_app "/mcp"
      for challenge in *{"abc", VERIFIER, "#{("a")\rep 42}!"}
        status, body, headers = authorize app, { code_challenge: challenge }

        params = redirected_error status, headers
        assert.equal "code_challenge is not a valid S256 challenge", params.error_description

    it "redirects with an error for an unsupported response_type", ->
      app = build_app "/mcp"
      status, body, headers = authorize app, { response_type: "token" }

      params = redirected_error status, headers
      assert.equal "unsupported_response_type", params.error

    it "does not redirect when the client_id is unknown", ->
      app = build_app "/mcp"
      status, body = authorize app, { client_id: "other-client" }

      assert.equal 400, status
      assert.equal "invalid_client", json.decode(body).error

    it "does not redirect to a redirect_uri with a fragment", ->
      app = build_app "/mcp"
      status, body = authorize app, { redirect_uri: "https://client.example/callback#frag" }

      assert.equal 400, status
      assert.equal "redirect_uri must not contain a fragment", json.decode(body).error_description

  describe "authorization_code exchange", ->
    get_code = (app) ->
      status, body, headers = authorize app
      assert.equal 302, status
      parse_query_string(headers.location\match "%?(.*)$").code

    exchange = (app, params) ->
      args = {
        grant_type: "authorization_code"
        client_id: "connector-client"
        client_secret: "connector-secret"
        redirect_uri: "https://client.example/callback"
        code_verifier: VERIFIER
      }
      for k, v in pairs params
        args[k] = v

      simulate_request app, "/mcp/oauth/token", {
        method: "POST"
        headers: { "Content-Type": "application/x-www-form-urlencoded" }
        body: encode_query_string args
      }

    it "issues a token for the correct code_verifier", ->
      app = build_app "/mcp"
      status, body = exchange app, { code: get_code app }

      assert.equal 200, status
      assert.equal "connector-secret", json.decode(body).access_token

    it "rejects the wrong code_verifier", ->
      app = build_app "/mcp"
      status, body = exchange app, { code: get_code(app), code_verifier: "wrong-verifier" }

      assert.equal 400, status
      assert.equal "PKCE verification failed", json.decode(body).error_description

    it "rejects the wrong client_secret", ->
      app = build_app "/mcp"
      status, body = exchange app, { code: get_code(app), client_secret: "nope" }

      assert.equal 401, status
      assert.equal "invalid_client", json.decode(body).error

  describe "allowed_redirect_uris", ->
    restricted_app = ->
      build_app "/mcp", {
        client_id: "connector-client"
        client_secret: "connector-secret"
        allowed_redirect_uris: {
          "https://client.example/callback"
          "http://localhost/callback"
          "http://127.0.0.1/callback"
          "http://[::1]/callback"
        }
      }

    it "requires allowed_redirect_uris to be an array of strings", ->
      for bad in *{"https://client.example/callback", {"https://client.example/callback", 5}}
        assert.has_error (->
          oauth_shim.OauthConfig {
            client_id: "connector-client"
            client_secret: "connector-secret"
            allowed_redirect_uris: bad
          }
        ), "oauth.allowed_redirect_uris must be an array of strings"

    it "allows listed redirect URIs", ->
      status = authorize restricted_app!, { redirect_uri: "https://client.example/callback" }
      assert.equal 302, status

    it "allows any port on loopback redirect URIs", ->
      for uri in *{"http://localhost:51234/callback", "http://127.0.0.1:8080/callback", "http://[::1]:8080/callback", "http://[::1]/callback"}
        status, body, headers = authorize restricted_app!, { redirect_uri: uri }
        assert.equal 302, status
        assert.equal uri, headers.location\match "^[^?]+"

    it "rejects unlisted redirect URIs", ->
      for uri in *{
        "https://evil.example/callback"
        "https://client.example:8443/callback"
        "http://localhost:51234/other"
        "https://localhost:51234/callback"
        "http://[::1]:8080/other"
        "http://[::2]:8080/callback"
      }
        status, body = authorize restricted_app!, { redirect_uri: uri }
        assert.equal 400, status
        assert.equal "redirect_uri not allowed", json.decode(body).error_description

  describe "verify_bearer", ->
    import verify_bearer from oauth_shim

    it "accepts any case of the Bearer scheme", ->
      for header in *{"Bearer tok", "bearer tok", "BEARER tok"}
        assert.is_true verify_bearer header, "tok"

    it "rejects wrong tokens and schemes", ->
      assert.is_false verify_bearer "Bearer toke", "tok"
      assert.is_false verify_bearer "Bearer to", "tok"
      assert.is_false verify_bearer "Basic tok", "tok"
      assert.is_false verify_bearer nil, "tok"
      assert.is_false verify_bearer "Bearer tok", nil

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

  it "accepts any case of the Basic scheme", ->
    app = build_app "/"
    import encode_base64 from require "lapis.util.encoding"
    basic = encode_base64 "connector-client:connector-secret"

    for scheme in *{"Basic", "basic", "BASIC"}
      status, body = simulate_request app, "/oauth/token", {
        method: "POST"
        headers: {
          "Content-Type": "application/x-www-form-urlencoded"
          "Authorization": "#{scheme} #{basic}"
        }
        body: encode_query_string {
          grant_type: "client_credentials"
        }
      }

      assert.equal 200, status
      assert.equal "connector-secret", json.decode(body).access_token
