-- Static mode for static service token authentication. One pre-registered
-- confidential client is approved without a login step and always issued the
-- configured access_token (or the client_secret if no access_token is
-- provided). Auth codes are stateless: HMAC-signed JSON using the configured
-- client_secret.
--
-- Because codes are not stored, a code can be redeemed more than once until
-- it expires. Every redemption still requires the client secret and the PKCE
-- verifier, and always yields the same static token.

json = require "cjson.safe"

import encode_with_secret, decode_with_secret, decode_base64 from require "lapis.util.encoding"
import unescape from require "lapis.util"
import secure_compare, parse_authorization, verify_bearer, verify_pkce, redirect_to_client from require "lapis.mcp.oauth.util"

decode_basic_part = (part) ->
  unescape part\gsub "%+", " "

class StaticMode
  new: (@opts) =>
    assert @opts.client_id, "oauth.client_id is required"
    assert @opts.client_secret, "oauth.client_secret is required"

  access_token: =>
    @opts.access_token or @opts.client_secret

  -- fields merged into the authorization server metadata
  server_metadata: =>
    {
      grant_types_supported: setmetatable {"authorization_code", "client_credentials"}, json.array_mt
      token_endpoint_auth_methods_supported: setmetatable {"client_secret_post", "client_secret_basic"}, json.array_mt
    }

  -- returns the client, or nil and an error response when it's unknown. It
  -- runs before the redirect_uri is validated, so the error is shown to the
  -- user directly. A nil redirect_uris allows any redirect_uri
  check_client: (route, client_id) =>
    unless client_id == @opts.client_id
      return nil, { status: 400, json: {error: "invalid_client"} }

    { redirect_uris: @opts.allowed_redirect_uris }

  -- called with a fully validated authorization request, approves it
  -- immediately since there is no user to log in
  authorize: (route, request) =>
    code = encode_with_secret {
      cid: request.client_id
      ru: request.redirect_uri
      cc: request.code_challenge
      exp: os.time! + 600
    }, @opts.client_secret

    redirect_to_client request.redirect_uri, {
      :code
      state: request.state
      iss: request.iss
    }

  -- returns the token response body, or nil, status, error code, description
  token_request: (route) =>
    args = route.params

    client_id = args.client_id
    client_secret = args.client_secret

    scheme, basic_creds = parse_authorization route.req.headers["authorization"]
    if scheme == "basic"
      decoded = decode_base64 basic_creds
      if decoded
        cid, csec = decoded\match "^([^:]*):(.*)$"
        client_id = decode_basic_part cid if cid
        client_secret = decode_basic_part csec if csec

    unless client_id == @opts.client_id and secure_compare client_secret, @opts.client_secret
      return nil, 401, "invalid_client"

    switch args.grant_type
      when "authorization_code"
        code_data, err = decode_with_secret args.code or "", @opts.client_secret
        unless code_data
          return nil, 400, "invalid_grant", err
        if code_data.exp and code_data.exp < os.time!
          return nil, 400, "invalid_grant", "code expired"
        unless code_data.cid == client_id
          return nil, 400, "invalid_grant", "client_id mismatch"
        unless code_data.ru == args.redirect_uri
          return nil, 400, "invalid_grant", "redirect_uri mismatch"
        unless verify_pkce args.code_verifier, code_data.cc
          return nil, 400, "invalid_grant", "PKCE verification failed"
        @issue_token!
      when "client_credentials"
        @issue_token!
      else
        nil, 400, "unsupported_grant_type"

  issue_token: =>
    {
      access_token: @access_token!
      token_type: "Bearer"
      expires_in: @opts.access_token_ttl or 3600
    }

  -- returns the auth table set as server.auth, or false
  verify_bearer_token: (header) =>
    verify_bearer(header, @access_token!) and {static: true}

{ :StaticMode }
