-- Fake OAuth shim for static service token authentication.
-- Implements the minimum OAuth 2.0 endpoints required by Claude connectors
-- (and other RFC 8414 / RFC 9728 / RFC 6749 clients) without an actual login
-- step. Auth codes are stateless: HMAC-signed JSON using the configured
-- client_secret. The issued access_token is the configured access_token (or
-- the client_secret if no access_token is provided).

json = require "cjson.safe"

import respond_to from require "lapis.application"
import encode_with_secret, decode_with_secret, decode_base64 from require "lapis.util.encoding"
import encode_query_string, unescape from require "lapis.util"

build_base_url = (req) ->
  scheme = req.headers["x-forwarded-proto"] or (req.parsed_url and req.parsed_url.scheme) or "http"
  host = req.headers["x-forwarded-host"] or req.headers["host"] or "localhost"
  "#{scheme}://#{host}"

-- Path component of the protected resource (e.g. "/mcp" or ""). When
-- oauth.resource is an absolute URL we parse the path out of it; otherwise
-- we use the mount path the MCP handler is registered at.
resource_path = (oauth, mount_path) ->
  if oauth.resource
    p = oauth.resource\match "^[^:]+://[^/]*(/.*)$"
    return "" unless p
    return "" if p == "/"
    return p
  return "" unless mount_path
  return "" if mount_path == "" or mount_path == "/"
  mount_path

-- Full URL identifying the protected resource (used in metadata body).
resource_url = (req, oauth, mount_path) ->
  return oauth.resource if oauth.resource
  build_base_url(req) .. resource_path(oauth, mount_path)

-- Where the protected-resource metadata lives, per RFC 9728 §3. For a
-- resource at "/mcp" the metadata URL is "/.well-known/oauth-protected-resource/mcp".
protected_resource_metadata_url = (req, oauth, mount_path) ->
  base = build_base_url req
  path = resource_path oauth, mount_path
  "#{base}/.well-known/oauth-protected-resource#{path}"

base64url_no_pad = (s) ->
  encoded = ngx.encode_base64 s
  (encoded\gsub("+", "-")\gsub("/", "_")\gsub("=", ""))

verify_pkce = (verifier, challenge, method="plain") ->
  return false unless verifier and challenge
  switch method
    when "plain"
      verifier == challenge
    when "S256"
      digest = require "openssl.digest"
      h = digest.new "sha256"
      h\update verifier
      base64url_no_pad(h\final!) == challenge
    else
      false

verify_bearer_token = (oauth, header) ->
  return false unless header
  token = header\match "^[Bb]earer (.+)$"
  return false unless token
  expected = oauth.access_token or oauth.client_secret
  token == expected

protected_resource_handler = (oauth, mount_path) ->
  =>
    issuer = oauth.issuer or build_base_url @req
    {
      json: {
        resource: resource_url @req, oauth, mount_path
        authorization_servers: setmetatable {issuer}, json.array_mt
        bearer_methods_supported: setmetatable {"header"}, json.array_mt
      }
      headers: {
        ["Cache-Control"]: "public, max-age=3600"
        ["Access-Control-Allow-Origin"]: "*"
      }
    }

authorization_server_handler = (oauth) ->
  =>
    issuer = oauth.issuer or build_base_url @req
    {
      json: {
        issuer: issuer
        authorization_endpoint: "#{issuer}/oauth/authorize"
        token_endpoint: "#{issuer}/oauth/token"
        response_types_supported: setmetatable {"code"}, json.array_mt
        grant_types_supported: setmetatable {"authorization_code", "client_credentials"}, json.array_mt
        code_challenge_methods_supported: setmetatable {"S256", "plain"}, json.array_mt
        token_endpoint_auth_methods_supported: setmetatable {"client_secret_post", "client_secret_basic"}, json.array_mt
      }
      headers: {
        ["Cache-Control"]: "public, max-age=3600"
        ["Access-Control-Allow-Origin"]: "*"
      }
    }

authorize_handler = (oauth) ->
  respond_to {
    GET: =>
      params = @params
      response_type = params.response_type
      client_id = params.client_id
      redirect_uri = params.redirect_uri
      state = params.state
      code_challenge = params.code_challenge
      code_challenge_method = params.code_challenge_method or "plain"

      unless response_type == "code"
        return status: 400, json: {error: "unsupported_response_type"}

      unless client_id == oauth.client_id
        return status: 400, json: {error: "invalid_client"}

      unless redirect_uri
        return status: 400, json: {error: "invalid_request", error_description: "missing redirect_uri"}

      code = encode_with_secret {
        cid: client_id
        ru: redirect_uri
        cc: code_challenge
        ccm: code_challenge_method
        exp: os.time! + 600
      }, oauth.client_secret

      qs_params = {code: code}
      qs_params.state = state if state

      sep = redirect_uri\find("?", 1, true) and "&" or "?"
      {
        redirect_to: redirect_uri .. sep .. encode_query_string qs_params
      }
  }

decode_basic_part = (part) ->
  unescape part\gsub "%+", " "

token_handler = (oauth) ->
  cors_headers = {
    ["Access-Control-Allow-Origin"]: "*"
    ["Access-Control-Allow-Methods"]: "POST, OPTIONS"
    ["Access-Control-Allow-Headers"]: "Content-Type, Authorization"
  }

  merge = (base, extra) ->
    out = {k,v for k,v in pairs base}
    for k,v in pairs extra
      out[k] = v
    out

  issue_token = ->
    {
      json: {
        access_token: oauth.access_token or oauth.client_secret
        token_type: "Bearer"
        expires_in: oauth.access_token_ttl or 3600
      }
      headers: merge cors_headers, {
        ["Cache-Control"]: "no-store"
      }
    }

  error_response = (status, code, description) ->
    body = {error: code}
    body.error_description = description if description
    {
      :status
      json: body
      headers: cors_headers
    }

  respond_to {
    on_invalid_method: =>
      status: 405, layout: false, headers: cors_headers

    OPTIONS: =>
      status: 204, layout: false, headers: cors_headers

    POST: =>
      args = @params

      auth_header = @req.headers["authorization"]
      client_id = args.client_id
      client_secret = args.client_secret

      if auth_header
        basic_creds = auth_header\match "^[Bb]asic (.+)$"
        if basic_creds
          decoded = decode_base64 basic_creds
          if decoded
            cid, csec = decoded\match "^([^:]*):(.*)$"
            client_id = decode_basic_part cid if cid
            client_secret = decode_basic_part csec if csec

      unless client_id == oauth.client_id and client_secret == oauth.client_secret
        return error_response 401, "invalid_client"

      switch args.grant_type
        when "authorization_code"
          code_data, err = decode_with_secret args.code or "", oauth.client_secret
          unless code_data
            return error_response 400, "invalid_grant", err
          if code_data.exp and code_data.exp < os.time!
            return error_response 400, "invalid_grant", "code expired"
          unless code_data.cid == client_id
            return error_response 400, "invalid_grant", "client_id mismatch"
          unless code_data.ru == args.redirect_uri
            return error_response 400, "invalid_grant", "redirect_uri mismatch"
          if code_data.cc
            unless verify_pkce args.code_verifier, code_data.cc, code_data.ccm
              return error_response 400, "invalid_grant", "PKCE verification failed"
          issue_token!
        when "client_credentials"
          issue_token!
        else
          error_response 400, "unsupported_grant_type"
  }

register_routes = (app, oauth, mount_path) ->
  assert oauth.client_id, "oauth.client_id is required"
  assert oauth.client_secret, "oauth.client_secret is required"

  handler = protected_resource_handler oauth, mount_path
  app\match "/.well-known/oauth-protected-resource", handler

  -- RFC 9728 §3: when the resource has a non-empty path, clients probe
  -- "/.well-known/oauth-protected-resource{path}" instead of the root form.
  rpath = resource_path oauth, mount_path
  if rpath != ""
    app\match "/.well-known/oauth-protected-resource#{rpath}", handler

  app\match "/.well-known/oauth-authorization-server", authorization_server_handler oauth
  app\match "/oauth/authorize", authorize_handler oauth
  app\match "/oauth/token", token_handler oauth

{
  :register_routes
  :verify_bearer_token
  :verify_pkce
  :build_base_url
  :resource_path
  :resource_url
  :protected_resource_metadata_url
  :protected_resource_handler
  :authorization_server_handler
  :authorize_handler
  :token_handler
}
