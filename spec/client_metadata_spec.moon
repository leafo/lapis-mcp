json = require "cjson"

import ClientMetadata, parse_client_id from require "lapis.mcp.oauth.client_metadata"
import is_loopback_uri, parse_uri from require "lapis.mcp.oauth.util"

CLAUDE_CODE_ID = "https://claude.ai/oauth/claude-code-client-metadata"

-- the document served at CLAUDE_CODE_ID
CLAUDE_CODE_DOC = {
  client_id: CLAUDE_CODE_ID
  client_name: "Claude Code"
  client_uri: "https://claude.ai"
  redirect_uris: {"http://localhost/callback", "http://127.0.0.1/callback"}
  grant_types: {"authorization_code", "refresh_token"}
  response_types: {"code"}
  token_endpoint_auth_method: "none"
}

-- a lapis.http stand-in that serves canned responses by URL and records
-- requests. A response is {status, body, headers}, or {error: msg} to raise
class StubHttp
  new: (@responses={}) =>
    @requests = {}
    -- lapis.http.request is a plain function, not a method
    @request = (req) -> @handle req

  handle: (req) =>
    table.insert @requests, req
    res = @responses[req.url]
    error res.error if res and res.error
    return nil, "connection refused" unless res

    body = res.body
    body = json.encode body if type(body) == "table"
    if req.sink
      -- delivered in chunks, like a real response
      for i=1,#body,1024
        ok, err = req.sink body\sub i, i + 1023
        return nil, err unless ok
      req.sink nil

    1, res.status or 200, res.headers or {}

class StubCache
  new: =>
    @values = {}
    @ttls = {}

  get: (key) => @values[key]

  set: (key, value, ttl) =>
    @values[key] = value
    @ttls[key] = ttl

  only_ttl: =>
    for _, ttl in pairs @ttls
      return ttl

build = (responses, opts={}) ->
  http = StubHttp responses
  resolver = ClientMetadata {
    trusted_hosts: opts.trusted_hosts or {"claude.ai", "client.example"}
    cache: opts.cache
    :http
  }
  resolver, http

doc_with = (overrides) ->
  doc = {
    client_id: "https://client.example/client.json"
    client_name: "Example Client"
    redirect_uris: {"https://client.example/callback"}
  }
  for k, v in pairs overrides
    doc[k] = v
  doc

resolve_doc = (doc, opts) ->
  resolver = build {
    ["https://client.example/client.json"]: { body: doc, headers: opts and opts.headers }
  }, opts
  resolver\resolve "https://client.example/client.json"

describe "client metadata", ->
  describe "is_loopback_uri", ->
    for uri in *{
      "http://localhost/callback"
      "http://localhost:8080/callback"
      "http://127.0.0.1"
      "http://[::1]:9000/callback?x=1"
    }
      it "accepts #{uri}", ->
        assert.true is_loopback_uri uri

    for uri in *{
      "https://localhost/callback"
      "http://localhost:@evil.example/callback"
      "http://127.0.0.1:80@evil.example/callback"
      "http://localhost@evil.example/callback"
      "http://localhost.evil.example/callback"
    }
      it "rejects #{uri}", ->
        assert.false is_loopback_uri uri

    it "parses a URI with a port", ->
      assert.same {"https", "client.example", "8443", "/cb"}, {parse_uri "HTTPS://Client.Example:8443/cb"}

  describe "parse_client_id", ->
    it "accepts an https URL with a path", ->
      assert.same "claude.ai", parse_client_id CLAUDE_CODE_ID
      assert.same "client.example", parse_client_id "https://Client.Example/a/b.json"

    for bad in *{
      "http://client.example/client.json"
      "https://client.example"
      "https://client.example/"
      "https://client.example/client.json?x=1"
      "https://client.example/client.json#frag"
      "https://user@client.example/client.json"
      "https://client.example:8443/client.json"
      "https://client.example/a/../client.json"
      "https://client.example/./client.json"
      "client.example/client.json"
      "https://client.example/a b.json"
      "https://client.example/client.json\r\nX-Injected: 1"
      "https://client.example/a/%2e%2e/client.json"
      "https://client.example/a/%2E/client.json"
      "https://client.example/a%zz.json"
      "https://client.example/a.json%"
    }
      it "rejects #{bad}", ->
        assert.falsy (parse_client_id bad)

    it "rejects a non-string", ->
      assert.falsy (parse_client_id nil)

  describe "resolve", ->
    it "requires trusted_hosts", ->
      assert.has_error -> ClientMetadata {}
      assert.has_error -> ClientMetadata trusted_hosts: {}

    it "accepts Claude Code's document", ->
      resolver, http = build {
        [CLAUDE_CODE_ID]: {
          body: CLAUDE_CODE_DOC
          headers: { ["Cache-Control"]: "public, max-age=300" }
        }
      }

      assert.same {
        client_id: CLAUDE_CODE_ID
        client_name: "Claude Code"
        host: "claude.ai"
        redirect_uris: {"http://localhost/callback", "http://127.0.0.1/callback"}
      }, resolver\resolve CLAUDE_CODE_ID

      assert.same 1, #http.requests
      assert.same "GET", http.requests[1].method
      assert.false http.requests[1].redirect

    it "rejects an invalid client_id without fetching", ->
      resolver, http = build {}
      client, err = resolver\resolve "http://claude.ai/client.json"
      assert.falsy client
      assert.same "invalid_client_id", err
      assert.same 0, #http.requests

    it "rejects an untrusted host without fetching", ->
      resolver, http = build {}
      client, err, description = resolver\resolve "https://evil.example/client.json"
      assert.falsy client
      assert.same "untrusted_host", err
      assert.same "evil.example is not a trusted client host", description
      assert.same 0, #http.requests

    it "doesn't trust subdomains of a trusted host", ->
      resolver = build {}
      _, err = resolver\resolve "https://evil.claude.ai/client.json"
      assert.same "untrusted_host", err

    it "matches trusted hosts case insensitively", ->
      resolver = build {
        ["https://CLIENT.example/client.json"]: { body: doc_with client_id: "https://CLIENT.example/client.json" }
      }, trusted_hosts: {"Client.Example"}
      assert.truthy resolver\resolve "https://CLIENT.example/client.json"

    it "uses the host when there's no client_name", ->
      client = resolve_doc doc_with client_name: json.null
      assert.same "client.example", client.client_name

    it "accepts a null token_endpoint_auth_method", ->
      assert.truthy resolve_doc doc_with token_endpoint_auth_method: json.null

    it "accepts loopback and same origin redirect_uris", ->
      client = resolve_doc doc_with redirect_uris: {
        "https://client.example/callback"
        "http://localhost:8080/callback"
        "http://[::1]/callback"
      }
      assert.same 3, #client.redirect_uris

    describe "rejects a document", ->
      rejects = (doc, pattern) ->
        client, err, description = resolve_doc doc
        assert.falsy client
        assert.same "invalid_document", err
        assert.truthy description\find(pattern, 1, true), "unexpected description: #{description}"

      it "that isn't JSON", ->
        rejects "<html>not json</html>", "not a JSON object"

      it "with a different client_id", ->
        rejects doc_with(client_id: "https://client.example/other.json"), "client_id doesn't match"

      it "with a secret based auth method", ->
        rejects doc_with(token_endpoint_auth_method: "client_secret_post"), "must be none"

      it "without redirect_uris", ->
        rejects doc_with(redirect_uris: json.null), "non-empty array"
        rejects doc_with(redirect_uris: setmetatable {}, json.array_mt), "non-empty array"

      it "with a redirect_uri on another origin", ->
        rejects doc_with(redirect_uris: {"https://evil.example/callback"}), "got https://evil.example/callback"
        rejects doc_with(redirect_uris: {"http://client.example/callback"}), "must be loopback or on https://client.example"
        rejects doc_with(redirect_uris: {"https://client.example:8443/callback"}), "must be loopback"
        rejects doc_with(redirect_uris: {"http://localhost:@evil.example/callback"}), "must be loopback"

      it "with a fragment in a redirect_uri", ->
        rejects doc_with(redirect_uris: {"http://localhost/callback#x"}), "must not contain a fragment"

      it "with a non-string redirect_uri", ->
        rejects doc_with(redirect_uris: {5}), "must be strings"

    describe "fetch failures", ->
      fails = (response, pattern) ->
        resolver = build {
          ["https://client.example/client.json"]: response
        }
        client, err, description = resolver\resolve "https://client.example/client.json"
        assert.falsy client
        assert.same "fetch_failed", err
        assert.truthy description\find(pattern, 1, true), "unexpected description: #{description}"

      it "on a non-200 status", ->
        fails { status: 404, body: "not found" }, "got 404"

      it "on a redirect", ->
        fails { status: 302, body: "", headers: { Location: "https://evil.example/client.json" } }, "got 302"

      it "on a document over 16KB", ->
        fails { body: doc_with(client_name: string.rep "x", 20000) }, "larger than 16384 bytes"

      it "when the request raises", ->
        fails { error: "timeout" }, "timeout"

      it "when the request returns an error", ->
        resolver = build {}
        _, err, description = resolver\resolve "https://client.example/client.json"
        assert.same "fetch_failed", err
        assert.same "request failed: connection refused", description

    describe "cache", ->
      it "caches a valid document", ->
        cache = StubCache!
        resolver, http = build {
          [CLAUDE_CODE_ID]: { body: CLAUDE_CODE_DOC }
        }, :cache

        first = resolver\resolve CLAUDE_CODE_ID
        assert.same first, resolver\resolve CLAUDE_CODE_ID
        assert.same 1, #http.requests
        assert.same 60 * 60, cache\only_ttl!

      it "caches failures briefly", ->
        cache = StubCache!
        resolver, http = build {
          ["https://client.example/client.json"]: { status: 500, body: "" }
        }, :cache

        resolver\resolve "https://client.example/client.json"
        _, err = resolver\resolve "https://client.example/client.json"
        assert.same "fetch_failed", err
        assert.same 1, #http.requests
        assert.same 60, cache\only_ttl!

      for {cache_control, ttl} in *{
        {"public, max-age=300", 300}
        {"max-age=10", 5 * 60}
        {"max-age=999999", 24 * 60 * 60}
        {"no-store", 5 * 60}
        {"public", 60 * 60}
      }
        it "uses a ttl of #{ttl} for Cache-Control: #{cache_control}", ->
          cache = StubCache!
          resolve_doc doc_with({}), {
            :cache
            headers: { ["cache-control"]: cache_control }
          }
          assert.same ttl, cache\only_ttl!

      it "reads repeated Cache-Control headers", ->
        cache = StubCache!
        resolve_doc doc_with({}), {
          :cache
          headers: { ["Cache-Control"]: {"public, max-age=86400", "no-store"} }
        }
        assert.same 5 * 60, cache\only_ttl!

      it "doesn't cache untrusted hosts", ->
        cache = StubCache!
        resolver = build {}, :cache
        resolver\resolve "https://evil.example/client.json"
        assert.same {}, cache.values

    describe "logging", ->
      local logged

      before_each ->
        logged = {}
        _G.ngx = {
          WARN: 5
          log: (level, ...) -> table.insert logged, table.concat {...}
        }

      after_each ->
        _G.ngx = nil

      it "logs a rejected host", ->
        resolver = build {}
        resolver\resolve "https://evil.example/client.json"
        assert.same {
          "lapis-mcp: rejected client https://evil.example/client.json: untrusted_host: evil.example is not a trusted client host"
        }, logged

      it "escapes control characters and truncates", ->
        resolver = build {}
        resolver\resolve "https://evil.example/#{string.rep "a", 300}\nforged line"
        assert.same 1, #logged
        assert.falsy logged[1]\find "\n", 1, true
        assert.truthy logged[1]\find "aaaa...", 1, true

      it "escapes newlines in the client_id", ->
        resolver = build {}
        resolver\resolve "https://evil.example/x\nforged"
        assert.truthy logged[1]\find "x\\010forged", 1, true
