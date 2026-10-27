-- Client ID Metadata Documents (CIMD): the client_id is an https URL, and the
-- document served there lists the client's name and redirect URIs.
-- https://datatracker.ietf.org/doc/draft-ietf-oauth-client-id-metadata-document/
--
-- Only clients on trusted_hosts are accepted. Anyone can publish a metadata
-- document, so without that list any website could ask users to connect.
--
--   resolver = ClientMetadata {
--     trusted_hosts: {"claude.ai"}
--     cache: ngx.shared.mcp_clients -- optional, anything with get and set
--   }
--
--   client, err, description = resolver\resolve client_id
--
-- client is {:client_id, :client_name, :host, :redirect_uris}. err is one of
-- "invalid_client_id", "untrusted_host", "fetch_failed" or
-- "invalid_document", with a description for logging or an error page.
--
-- check runs only the checks that don't need a fetch, so a caller can do
-- something in between, like asking the user to log in:
--
--   host, err, description = resolver\check client_id
--
-- Documents are fetched with lapis.http, which doesn't follow redirects.
-- Under nginx that's a subrequest to the /proxy location, so its settings
-- decide how the fetch behaves:
--
--   * Trusting a host only means something if its certificate is checked,
--     and nginx doesn't by default. Set proxy_ssl_verify on,
--     proxy_ssl_trusted_certificate and proxy_ssl_server_name on.
--   * Timeouts come from proxy_connect_timeout and proxy_read_timeout.
--   * The response is buffered whole before lapis-mcp sees it, so the 16KB
--     limit stops an oversized document being used but not being read.

json = require "cjson.safe"
import parse_uri, is_loopback_uri from require "lapis.mcp.oauth.util"

MAX_DOCUMENT_SIZE = 16 * 1024

-- how long a fetched document is cached: its Cache-Control max-age clamped
-- to this range, or DEFAULT_TTL without one. Failures are cached for
-- FAILURE_TTL so a broken client can't make every authorize request fetch
FAILURE_TTL = 60
DEFAULT_TTL = 60 * 60
MIN_TTL = 5 * 60
MAX_TTL = 24 * 60 * 60

CACHE_PREFIX = "lapis-mcp:client-metadata:"

-- returns the host of a valid client_id URL, or nil and the reason
parse_client_id = (client_id) ->
  return nil, "client_id must be a string" unless type(client_id) == "string"
  return nil, "client_id must not contain a fragment" if client_id\find "#", 1, true

  host, path = client_id\match "^https://([^/?]+)(/[^?]*)$"
  unless host
    return nil, "client_id must be an https URL with a path and no query"

  return nil, "client_id must not contain a username or password" if host\find "@", 1, true
  return nil, "client_id must not contain a port" if host\find ":", 1, true
  return nil, "client_id must have a path" if path == "/"

  -- RFC 3986 path characters only, which rules out whitespace and control
  -- characters reaching the request line
  unless path\match "^[%w%-._~!$&'()*+,;=:@/%%]*$"
    return nil, "client_id must be a valid URL path"

  -- every % starts a percent-encoded byte
  if path\gsub("%%%x%x", "")\find "%", 1, true
    return nil, "client_id must be a valid URL path"

  for segment in path\gmatch "[^/]+"
    segment = segment\lower!\gsub "%%2e", "."
    if segment == "." or segment == ".."
      return nil, "client_id must not contain dot segments"

  host\lower!

origin = (uri) ->
  scheme, host, port = parse_uri uri
  return nil unless scheme
  port = ":#{port}" if port != ""
  "#{scheme}://#{host}#{port}"

validate_document = (doc, client_id, host) ->
  return nil, "the document is not a JSON object" unless type(doc) == "table"
  return nil, "the document's client_id doesn't match its URL" unless doc.client_id == client_id

  method = doc.token_endpoint_auth_method
  if method != nil and method != json.null
    return nil, "token_endpoint_auth_method must be none" unless method == "none"

  uris = doc.redirect_uris
  unless type(uris) == "table" and #uris > 0
    return nil, "redirect_uris must be a non-empty array"

  -- a document on a trusted host can only send codes back to that host or to
  -- the user's own machine
  client_origin = origin client_id
  for uri in *uris
    return nil, "redirect_uris must be strings" unless type(uri) == "string"
    return nil, "redirect_uris must not contain a fragment" if uri\find "#", 1, true
    continue if is_loopback_uri uri
    unless origin(uri) == client_origin
      return nil, "redirect_uris must be loopback or on #{client_origin}, got #{uri}"

  client_name = doc.client_name
  client_name = host unless type(client_name) == "string" and client_name != ""

  {
    :client_id
    :client_name
    :host
    redirect_uris: [uri for uri in *uris]
  }

-- joins repeated headers, which can arrive as several keys differing in case
-- or as an array value
header_value = (headers, name) ->
  return nil unless type(headers) == "table"
  values = {}
  for k, v in pairs headers
    if type(k) == "string" and k\lower! == name
      if type(v) == "table"
        for item in *v
          table.insert values, tostring item
      else
        table.insert values, tostring v

  return nil unless next values
  table.concat values, ", "

max_age_ttl = (headers) ->
  cache_control = header_value headers, "cache-control"
  return DEFAULT_TTL unless type(cache_control) == "string"

  cache_control = cache_control\lower!
  return MIN_TTL if cache_control\find("no-store", 1, true) or cache_control\find("no-cache", 1, true)

  max_age = tonumber cache_control\match "max%-age=(%d+)"
  return DEFAULT_TTL unless max_age
  math.min MAX_TTL, math.max MIN_TTL, max_age

-- client_id comes from the request and descriptions can quote the document,
-- so control characters are escaped and long values truncated to keep them
-- from forging or flooding log lines
log_value = (value) ->
  value = tostring value
  value = value\sub(1, 200) .. "..." if #value > 200
  (value\gsub "[%c\\]", (c) -> string.format "\\%03d", c\byte!)

log_rejection = (client_id, err, description) ->
  return unless ngx and ngx.log
  ngx.log ngx.WARN, "lapis-mcp: rejected client ", log_value(client_id), ": ", err, ": ", log_value(description)

class ClientMetadata
  new: (opts={}) =>
    hosts = opts.trusted_hosts
    assert type(hosts) == "table" and #hosts > 0, "trusted_hosts must be a non-empty array of hostnames"

    @trusted_hosts = {}
    for host in *hosts
      assert type(host) == "string", "trusted_hosts must be a non-empty array of hostnames"
      @trusted_hosts[host\lower!] = true

    @cache = opts.cache
    @http = opts.http

  check: (client_id) =>
    host, description = parse_client_id client_id
    unless host
      log_rejection client_id, "invalid_client_id", description
      return nil, "invalid_client_id", description

    unless @trusted_hosts[host]
      description = "#{host} is not a trusted client host"
      log_rejection client_id, "untrusted_host", description
      return nil, "untrusted_host", description

    host

  resolve: (client_id) =>
    host, err, description = @check client_id
    return nil, err, description unless host

    if cached = @cache_get client_id
      return cached.client if cached.client
      return nil, cached.error, cached.description

    client, err, description, ttl = @fetch client_id, host
    if client
      @cache_set client_id, {:client}, ttl
      return client

    log_rejection client_id, err, description
    @cache_set client_id, {error: err, :description}, FAILURE_TTL
    nil, err, description

  -- returns the client and its cache ttl, or nil, err, description
  fetch: (client_id, host) =>
    ltn12 = require "ltn12"
    http = @http or require "lapis.http"

    chunks = {}
    size = 0
    too_large = false

    sink = (chunk, err) ->
      return true unless chunk
      size += #chunk
      if size > MAX_DOCUMENT_SIZE
        too_large = true
        return nil, "document too large"
      table.insert chunks, chunk
      true

    -- failures are either raised or returned as nil, err depending on the
    -- backend
    ok, res, status, headers = pcall http.request, {
      url: client_id
      method: "GET"
      headers: { Accept: "application/json" }
      :sink
      redirect: false
    }

    if too_large
      return nil, "fetch_failed", "the document is larger than #{MAX_DOCUMENT_SIZE} bytes"

    return nil, "fetch_failed", "request failed: #{res}" unless ok
    return nil, "fetch_failed", "request failed: #{status}" unless res

    unless status == 200
      return nil, "fetch_failed", "expected status 200, got #{status}"

    doc = json.decode table.concat chunks
    client, description = validate_document doc, client_id, host
    return nil, "invalid_document", description unless client

    client, nil, nil, max_age_ttl headers

  cache_get: (client_id) =>
    return nil unless @cache
    value = @cache\get CACHE_PREFIX .. client_id
    value and json.decode value

  cache_set: (client_id, value, ttl) =>
    return unless @cache
    @cache\set CACHE_PREFIX .. client_id, json.encode(value), ttl

{ :ClientMetadata, :parse_client_id }
