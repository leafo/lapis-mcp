-- Site mode: users of your site log in and approve each MCP client. Clients
-- identify themselves with a Client ID Metadata Document (see
-- lapis.mcp.oauth.client_metadata), and grants are kept in a grant store (see
-- lapis.mcp.oauth.grant_store_contract).
--
--   oauth: {
--     grants: McpGrants
--     trusted_client_hosts: {"claude.ai"}
--     allow_any_client: true -- optional, see below
--     current_user: (route) -> route.current_user
--     login_url: (route, return_to) -> route\url_for "login", nil, :return_to
--     render_consent: (route, consent) ->
--       route.consent = consent
--       render: "mcp_consent"
--   }
--
-- login_url must send the user back to return_to after they log in.
-- render_consent shows what's asking for access and a form that posts
-- consent.consent_token to consent.action, with approve set to approve and
-- without it to deny. The consent fields are client_id, client_name,
-- client_host, client_trusted, redirect_uri, redirect_host and
-- redirect_loopback. Name the client by client_host, client_name is chosen
-- by the client. Headers that stop the page being framed or cached are added
-- to its response.
--
-- Only clients on trusted_client_hosts can connect unless allow_any_client
-- is set. With it, any website can send your users to a consent page naming
-- itself, so warn on the page when client_trusted is false.
--
-- The owner values are put in the consent token, so they must be plain
-- strings, numbers or booleans.
--
-- grant_created(route, grant), optional, is called after the user approves
-- a client, for example to record it in an activity log. The client hasn't
-- exchanged its code for an access token yet at that point.
--
-- There are no refresh tokens: access tokens last access_token_ttl seconds
-- (90 days by default) and then the user connects again.

json = require "cjson.safe"

import encode_with_secret, decode_with_secret from require "lapis.util.encoding"
import ClientMetadata from require "lapis.mcp.oauth.client_metadata"
import secure_compare, parse_authorization, verify_pkce, redirect_to_client,
  sha256_hex, random_token, parse_uri, is_loopback_uri, same_resource from require "lapis.mcp.oauth.util"

CODE_TTL = 60
CONSENT_TTL = 10 * 60
DEFAULT_ACCESS_TOKEN_TTL = 90 * 24 * 60 * 60

-- a random value kept in the session and put in each consent token, so a
-- consent token only works in the browser it was shown in. Without it an
-- attacker could have a victim submit the attacker's consent form, connecting
-- the attacker's client to the victim's account
SESSION_KEY = "mcp_consent_key"

-- added to the consent page's response unless it sets them, so it can't be
-- framed by a page that tricks the user into clicking approve
CONSENT_HEADERS = {
  "X-Frame-Options": "DENY"
  "Content-Security-Policy": "frame-ancestors 'none'"
  "Cache-Control": "no-store"
}

client_error = (description) ->
  { status: 400, json: {error: "invalid_client", error_description: description} }

consent_error = (description) ->
  { status: 400, json: {error: "invalid_request", error_description: description} }

-- owner values after a round trip through the consent token's JSON
same_owner = (a, b) ->
  return false unless type(a) == "table" and type(b) == "table"
  for k, v in pairs a
    return false unless b[k] == v
  for k, v in pairs b
    return false unless a[k] == v
  true

class SiteMode
  new: (@opts, @config) =>
    assert @opts.grants, "oauth.grants is required"
    for name in *{"current_user", "login_url", "render_consent"}
      assert type(@opts[name]) == "function", "oauth.#{name} must be a function"

    if @opts.grant_created != nil
      assert type(@opts.grant_created) == "function", "oauth.grant_created must be a function"

    @grants = @opts.grants
    @access_token_ttl = @opts.access_token_ttl or DEFAULT_ACCESS_TOKEN_TTL
    @clients = ClientMetadata {
      trusted_hosts: @opts.trusted_client_hosts
      allow_any_host: @opts.allow_any_client
      cache: @opts.cache
      http: @opts.http
    }

  server_metadata: =>
    {
      grant_types_supported: setmetatable {"authorization_code"}, json.array_mt
      token_endpoint_auth_methods_supported: setmetatable {"none"}, json.array_mt
      client_id_metadata_document_supported: true
    }

  -- the user logs in before the client's document is fetched, so only
  -- logged in users can make the server fetch anything
  check_client: (route, client_id) =>
    host, _, description = @clients\check client_id
    return nil, client_error description unless host

    unless @opts.current_user route
      query = route.req.parsed_url.query
      return_to = @config\authorize_url route.req
      return_to ..= "?#{query}" if query and query != ""
      return nil, redirect_to: @opts.login_url route, return_to

    client, _, description = @clients\resolve client_id
    return nil, client_error description unless client
    client

  authorize: (route, request) =>
    -- RFC 8707, a token is only for this mount
    if request.requested_resource != nil and not same_resource request.requested_resource, request.resource
      return redirect_to_client request.redirect_uri, {
        error: "invalid_target"
        error_description: "resource must be #{request.resource}"
        state: request.state
        iss: request.iss
      }

    key = route.session[SESSION_KEY]
    unless key
      key = random_token!
      route.session[SESSION_KEY] = key

    client = request.client

    -- the user who sees the page is the one who approves it, even if someone
    -- else logs in to the same browser session before it's submitted
    owner = @grants\owner_values @opts.current_user route

    consent_token = encode_with_secret {
      :key
      :owner
      exp: os.time! + CONSENT_TTL
      request: {
        client_id: request.client_id
        client_name: client.client_name
        redirect_uri: request.redirect_uri
        state: request.state
        code_challenge: request.code_challenge
        resource: request.resource
        iss: request.iss
      }
    }

    _, redirect_host = parse_uri request.redirect_uri

    res = @opts.render_consent route, {
      client_id: request.client_id
      client_name: client.client_name
      client_host: client.host
      client_trusted: client.trusted
      redirect_uri: request.redirect_uri
      :redirect_host
      redirect_loopback: is_loopback_uri request.redirect_uri
      action: @config\authorize_url route.req
      :consent_token
    }

    if type(res) == "table"
      headers = {k, v for k, v in pairs res.headers or {}}
      for k, v in pairs CONSENT_HEADERS
        headers[k] = v if headers[k] == nil
      res.headers = headers

    res

  consent_post: (route) =>
    token = route.params.consent_token
    return consent_error "invalid consent_token" unless type(token) == "string"

    data = decode_with_secret token
    return consent_error "invalid consent_token" unless type(data) == "table" and type(data.request) == "table"
    return consent_error "consent_token expired, try connecting again" unless type(data.exp) == "number" and data.exp > os.time!

    unless secure_compare data.key, route.session[SESSION_KEY]
      return consent_error "consent_token is for another session"

    user = @opts.current_user route
    return consent_error "you are no longer logged in" unless user

    owner = @grants\owner_values user
    unless same_owner owner, data.owner
      return consent_error "you've logged in as someone else, try connecting again"

    request = data.request

    respond = (params) ->
      params.state = request.state
      params.iss = request.iss
      redirect_to_client request.redirect_uri, params

    unless route.params.approve
      return respond error: "access_denied", error_description: "the user denied access"

    code = random_token!

    values = {k, v for k, v in pairs owner}
    values.client_id = request.client_id
    values.client_name = request.client_name
    values.redirect_uri = request.redirect_uri
    values.code_challenge = request.code_challenge
    values.resource = request.resource
    values.code_hash = sha256_hex code

    grant = @grants\create_for_code values, CODE_TTL
    error "grants\\create_for_code didn't return a grant" unless grant

    @opts.grant_created route, grant if @opts.grant_created

    respond :code

  -- returns the token response body, or nil, status, error code, description
  token_request: (route) =>
    args = route.params

    unless args.grant_type == "authorization_code"
      return nil, 400, "unsupported_grant_type"

    unless type(args.code) == "string" and args.code != ""
      return nil, 400, "invalid_request", "missing code"

    access_token = random_token!
    grant = @grants\redeem_code sha256_hex(args.code), {
      access_hash: sha256_hex access_token
      access_ttl: @access_token_ttl
    }

    return nil, 400, "invalid_grant", "unknown or expired code" unless grant

    -- the code is spent either way, so a failed check revokes the grant
    reject = (code, description) ->
      grant\delete!
      nil, 400, code, description

    -- mounts can share a grant store, a code is only for the mount that
    -- approved it, which also decides the token's lifetime
    return reject "invalid_grant", "code was issued for another resource" unless grant.resource == @config\resource_url route.req
    return reject "invalid_grant", "client_id mismatch" unless args.client_id == grant.client_id
    return reject "invalid_grant", "redirect_uri mismatch" unless args.redirect_uri == grant.redirect_uri
    return reject "invalid_grant", "PKCE verification failed" unless verify_pkce args.code_verifier, grant.code_challenge

    if args.resource != nil and not same_resource args.resource, grant.resource
      return reject "invalid_target", "resource mismatch"

    {
      :access_token
      token_type: "Bearer"
      expires_in: @access_token_ttl
    }

  -- returns {:grant}, set as server.auth, or false
  verify_bearer_token: (header, req) =>
    scheme, token = parse_authorization header
    return false unless scheme == "bearer"

    grant = @grants\find_by_access sha256_hex token
    return false unless grant
    return false unless grant.resource == @config\resource_url req

    { :grant }

{ :SiteMode }
