lapis = require "lapis"
json = require "cjson"

import McpServer from require "lapis.mcp.server"
import McpHttpRouter from require "lapis.mcp.http"
import OauthConfig from require "lapis.mcp.oauth"
import simulate_request from require "lapis.spec.request"
import encode_query_string, parse_query_string from require "lapis.util"
import encode_with_secret from require "lapis.util.encoding"
import MemoryGrants from require "spec.helpers.memory_grants"
import StubHttp from require "spec.helpers.stub_http"

CLIENT_ID = "https://claude.ai/oauth/claude-code-client-metadata"
REDIRECT_URI = "http://localhost:4567/callback"
RESOURCE = "https://example.com/mcp"
VERIFIER = "test-code-verifier-0123456789-abcdefghijklmnopqrstuvwxyz"

CLAUDE_CODE_DOC = {
  client_id: CLIENT_ID
  client_name: "Claude Code"
  redirect_uris: {"http://localhost/callback", "http://127.0.0.1/callback"}
  token_endpoint_auth_method: "none"
}

s256_challenge = (verifier) ->
  import encode_base64 from require "lapis.util.encoding"
  digest = require "openssl.digest"
  h = digest.new "sha256"
  h\update verifier
  (encode_base64(h\final!)\gsub("+", "-")\gsub("/", "_")\gsub("=", ""))

class TestServer extends McpServer
  @server_name: "test-server"

oauth_opts = (grants, http) ->
  {
    :grants
    :http
    trusted_client_hosts: {"claude.ai"}
    -- the test user's id is sent in a header
    current_user: (route) ->
      id = route.req.headers["x-test-user"]
      id and { id: tonumber id }
    login_url: (route, return_to) -> "/login?#{encode_query_string :return_to}"
    render_consent: (route, consent) -> json: consent
  }

build_app = (opts={}) ->
  grants = MemoryGrants!
  http = StubHttp { [CLIENT_ID]: { body: CLAUDE_CODE_DOC } }
  captured = {}

  oauth = oauth_opts grants, http
  for k, v in pairs opts.oauth or {}
    oauth[k] = v

  class TestApp extends lapis.Application
    layout: false

  router = McpHttpRouter!
  router\mount "/mcp", TestServer, {
    :oauth
    load_session: (req, server) -> captured.auth = server.auth
  }
  router\install TestApp

  TestApp, grants, http, captured

request = (app, url, opts={}) ->
  headers = {
    "Host": opts.host or "example.com"
    "X-Forwarded-Proto": "https"
  }
  headers["X-Test-User"] = tostring opts.user if opts.user
  for k, v in pairs opts.headers or {}
    headers[k] = v

  simulate_request app, url, {
    method: opts.method
    post: opts.post
    body: opts.body
    prev: opts.prev
    :headers
  }

-- params set to false are left out
authorize = (app, params={}, opts={user: 1}) ->
  args = {
    response_type: "code"
    client_id: CLIENT_ID
    redirect_uri: REDIRECT_URI
    state: "xyz"
    code_challenge: s256_challenge VERIFIER
    code_challenge_method: "S256"
  }
  for k, v in pairs params
    args[k] = v or nil

  request app, "#{opts.path or "/mcp"}/oauth/authorize?#{encode_query_string args}", opts

-- shows the consent page, returns the consent and the response headers
show_consent = (app, params, opts) ->
  status, body, headers = authorize app, params, opts
  assert.same 200, status
  json.decode(body), headers

submit_consent = (app, consent_token, opts={}) ->
  post = { consent_token: consent_token }
  post.approve = "1" if opts.approve != false
  request app, "#{opts.path or "/mcp"}/oauth/authorize", {
    method: "POST"
    :post
    prev: opts.prev
    user: opts.user == nil and 1 or opts.user or nil
  }

redirect_params = (headers) ->
  parse_query_string headers.location\match "%?(.*)$"

-- runs the authorize and consent steps, returns the code
get_code = (app) ->
  consent, headers = show_consent app
  status, _, res_headers = submit_consent app, consent.consent_token, prev: headers
  assert.same 302, status
  redirect_params(res_headers).code

exchange = (app, code, overrides={}, path="/mcp") ->
  post = {
    grant_type: "authorization_code"
    :code
    client_id: CLIENT_ID
    redirect_uri: REDIRECT_URI
    code_verifier: VERIFIER
  }
  for k, v in pairs overrides
    post[k] = v or nil

  status, body = request app, "#{path}/oauth/token", method: "POST", :post
  status, json.decode body

ping = (app, token, opts={}) ->
  headers = {
    "Accept": "application/json, text/event-stream"
    "Content-Type": "application/json"
  }
  headers["Authorization"] = "Bearer #{token}" if token
  request app, "/mcp", {
    method: "POST"
    :headers
    host: opts.host
    body: json.encode {jsonrpc: "2.0", id: 1, method: "ping"}
  }

count_rows = (grants) ->
  n = 0
  n += 1 for _ in pairs grants.rows
  n

describe "oauth site mode", ->
  describe "config", ->
    it "requires the callbacks", ->
      opts = oauth_opts MemoryGrants!, StubHttp!
      opts.render_consent = nil
      assert.has_error (-> OauthConfig opts), "oauth.render_consent must be a function"

    it "requires trusted_client_hosts", ->
      opts = oauth_opts MemoryGrants!, StubHttp!
      opts.trusted_client_hosts = nil
      assert.has_error -> OauthConfig opts

    it "can't be combined with a client_secret", ->
      opts = oauth_opts MemoryGrants!, StubHttp!
      opts.client_secret = "secret"
      assert.has_error (-> OauthConfig opts), "oauth can't set both grants and client_secret"

  it "advertises client ID metadata documents", ->
    app = build_app!
    status, body = request app, "/.well-known/oauth-authorization-server/mcp"
    assert.same 200, status
    metadata = json.decode body
    assert.same "https://example.com/mcp/oauth/authorize", metadata.authorization_endpoint
    assert.same true, metadata.client_id_metadata_document_supported
    assert.same {"none"}, metadata.token_endpoint_auth_methods_supported
    assert.same {"authorization_code"}, metadata.grant_types_supported

  describe "authorize", ->
    it "sends a logged out user to log in without fetching the client", ->
      app, _, http = build_app!
      status, _, headers = authorize app, {}, {}
      assert.same 302, status

      return_to = parse_query_string(headers.location\match "%?(.*)$").return_to
      assert.truthy return_to\match "^https://example%.com/mcp/oauth/authorize%?"
      assert.same CLIENT_ID, parse_query_string(return_to\match "%?(.*)$").client_id
      assert.same 0, #http.requests

    it "rejects an untrusted client before login", ->
      app, _, http = build_app!
      status, body = authorize app, { client_id: "https://evil.example/client.json" }, {}
      assert.same 400, status
      assert.same "invalid_client", json.decode(body).error
      assert.same 0, #http.requests

    it "shows the consent page", ->
      app = build_app!
      consent = show_consent app
      assert.same CLIENT_ID, consent.client_id
      assert.same "Claude Code", consent.client_name
      assert.same "claude.ai", consent.client_host
      assert.same REDIRECT_URI, consent.redirect_uri
      assert.same "localhost", consent.redirect_host
      assert.same true, consent.redirect_loopback
      assert.same "https://example.com/mcp/oauth/authorize", consent.action
      assert.is_string consent.consent_token

    it "rejects a redirect_uri the client doesn't list, without redirecting", ->
      app = build_app!
      status, body = authorize app, { redirect_uri: "https://evil.example/callback" }
      assert.same 400, status
      assert.same "redirect_uri not allowed", json.decode(body).error_description

    it "rejects a client whose document can't be fetched", ->
      app, _, http = build_app!
      http.responses[CLIENT_ID] = { status: 404, body: "" }
      status, body = authorize app
      assert.same 400, status
      assert.same "invalid_client", json.decode(body).error

    it "redirects with invalid_target for another resource", ->
      app = build_app!
      status, _, headers = authorize app, { resource: "https://other.example/mcp" }
      assert.same 302, status
      assert.same "invalid_target", redirect_params(headers).error

    it "accepts this mount as the resource", ->
      app = build_app!
      assert.truthy show_consent app, resource: RESOURCE

    it "ignores a trailing slash and case in the resource", ->
      app = build_app!
      assert.truthy show_consent app, resource: "https://EXAMPLE.com/mcp/"

    it "adds headers that stop the consent page being framed or cached", ->
      app = build_app!
      _, headers = show_consent app
      assert.same "DENY", headers.x_frame_options
      assert.same "frame-ancestors 'none'", headers.content_security_policy
      assert.same "no-store", headers.cache_control

    it "keeps the consent page's own headers", ->
      app = build_app oauth: {
        render_consent: (route, consent) ->
          json: consent, headers: { "X-Frame-Options": "SAMEORIGIN" }
      }
      _, headers = show_consent app
      assert.same "SAMEORIGIN", headers.x_frame_options
      assert.same "no-store", headers.cache_control

  describe "consent", ->
    it "redirects with a code when approved", ->
      app, grants = build_app!
      consent, headers = show_consent app
      status, _, res_headers = submit_consent app, consent.consent_token, prev: headers

      assert.same 302, status
      assert.same REDIRECT_URI, res_headers.location\match "^[^?]+"
      params = redirect_params res_headers
      assert.is_string params.code
      assert.same "xyz", params.state
      assert.same "https://example.com/mcp", params.iss

      _, grant = next grants.rows
      assert.same 1, grant.user_id
      assert.same "Claude Code", grant.client_name
      assert.same RESOURCE, grant.resource

    it "redirects with access_denied when denied", ->
      app, grants = build_app!
      consent, headers = show_consent app
      status, _, res_headers = submit_consent app, consent.consent_token, prev: headers, approve: false

      assert.same 302, status
      params = redirect_params res_headers
      assert.same "access_denied", params.error
      assert.same "xyz", params.state
      assert.same 0, count_rows grants

    it "rejects a consent token from another session", ->
      app, grants = build_app!
      consent = show_consent app
      status, body = submit_consent app, consent.consent_token
      assert.same 400, status
      assert.same "consent_token is for another session", json.decode(body).error_description
      assert.same 0, count_rows grants

    it "rejects a consent token for another user", ->
      app, grants = build_app!
      consent, headers = show_consent app
      status, body = submit_consent app, consent.consent_token, prev: headers, user: 2
      assert.same 400, status
      assert.same "you've logged in as someone else, try connecting again", json.decode(body).error_description
      assert.same 0, count_rows grants

    it "rejects a consent_token that isn't a string", ->
      app = build_app!
      _, headers = show_consent app
      status, body = request app, "/mcp/oauth/authorize", {
        method: "POST"
        body: "consent_token[x]=1&approve=1"
        headers: { "Content-Type": "application/x-www-form-urlencoded" }
        prev: headers
        user: 1
      }
      assert.same 400, status
      assert.same "invalid consent_token", json.decode(body).error_description

    it "errors when the grant store doesn't return a grant", ->
      app, grants = build_app!
      grants.create_for_code = -> nil
      consent, headers = show_consent app
      ok, err = pcall -> submit_consent app, consent.consent_token, prev: headers
      assert.false ok
      assert.truthy err\find "create_for_code didn't return a grant", 1, true

    it "rejects a forged consent token", ->
      app = build_app!
      _, headers = show_consent app
      status, body = submit_consent app, "not-a-token", prev: headers
      assert.same 400, status
      assert.same "invalid consent_token", json.decode(body).error_description

    it "rejects an expired consent token", ->
      app = build_app!
      _, headers = show_consent app
      token = encode_with_secret { key: "k", exp: os.time! - 1, request: {} }
      status, body = submit_consent app, token, prev: headers
      assert.same 400, status
      assert.same "consent_token expired, try connecting again", json.decode(body).error_description

    it "rejects a logged out user", ->
      app = build_app!
      consent, headers = show_consent app
      status, body = submit_consent app, consent.consent_token, prev: headers, user: false
      assert.same 400, status
      assert.same "you are no longer logged in", json.decode(body).error_description

  describe "token", ->
    it "exchanges a code for an access token", ->
      app = build_app!
      status, body = exchange app, get_code app
      assert.same 200, status
      assert.is_string body.access_token
      assert.same "Bearer", body.token_type
      assert.same 90 * 24 * 60 * 60, body.expires_in
      assert.is_nil body.refresh_token

    it "redeems a code only once", ->
      app = build_app!
      code = get_code app
      assert.same 200, (exchange app, code)
      status, body = exchange app, code
      assert.same 400, status
      assert.same "invalid_grant", body.error

    for {name, overrides, err} in *{
      {"PKCE verifier", { code_verifier: "wrong-verifier-0123456789-abcdefghijklmnopqrstuvwxyz" }, "invalid_grant"}
      {"client_id", { client_id: "https://claude.ai/other" }, "invalid_grant"}
      {"redirect_uri", { redirect_uri: "http://localhost:9999/callback" }, "invalid_grant"}
      {"resource", { resource: "https://other.example/mcp" }, "invalid_target"}
    }
      it "rejects the wrong #{name} and revokes the grant", ->
        app, grants = build_app!
        status, body = exchange app, get_code(app), overrides
        assert.same 400, status
        assert.same err, body.error
        assert.same 0, count_rows grants

    it "accepts the resource with a trailing slash", ->
      app = build_app!
      status = exchange app, get_code(app), resource: "#{RESOURCE}/"
      assert.same 200, status

    it "rejects a code issued for another mount", ->
      grants = MemoryGrants!
      http = StubHttp { [CLIENT_ID]: { body: CLAUDE_CODE_DOC } }

      class TwoMounts extends lapis.Application
        layout: false

      router = McpHttpRouter!
      router\mount "/one", TestServer, oauth: oauth_opts grants, http
      router\mount "/two", TestServer, oauth: oauth_opts grants, http
      router\install TwoMounts

      consent, headers = show_consent TwoMounts, nil, { user: 1, path: "/one" }
      _, _, res_headers = submit_consent TwoMounts, consent.consent_token, prev: headers, path: "/one"
      code = redirect_params(res_headers).code

      status, body = exchange TwoMounts, code, nil, "/two"
      assert.same 400, status
      assert.same "invalid_grant", body.error
      assert.same 0, count_rows grants

    it "rejects other grant types", ->
      app = build_app!
      status, body = exchange app, nil, grant_type: "refresh_token"
      assert.same 400, status
      assert.same "unsupported_grant_type", body.error

    it "rejects a missing code", ->
      app = build_app!
      status, body = exchange app, nil
      assert.same 400, status
      assert.same "invalid_request", body.error

  describe "bearer tokens", ->
    it "sets server.auth to the grant", ->
      app, _, _, captured = build_app!
      _, token = exchange app, get_code app

      assert.same 200, (ping app, token.access_token)
      assert.same 1, captured.auth.grant.user_id
      assert.same CLIENT_ID, captured.auth.grant.client_id

    it "rejects an unknown token", ->
      app, _, _, captured = build_app!
      status = ping app, "unknown-token"
      assert.same 401, status
      assert.is_nil captured.auth

    it "rejects a token for another resource", ->
      app = build_app!
      _, token = exchange app, get_code app
      status = ping app, token.access_token, host: "other.example"
      assert.same 401, status

    it "stops working when the grant is deleted", ->
      app, grants = build_app!
      _, token = exchange app, get_code app
      _, grant = next grants.rows
      grant\delete!
      assert.same 401, (ping app, token.access_token)
