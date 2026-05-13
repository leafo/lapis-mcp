-- Fake OAuth shim for static service token authentication.
-- Implements the minimum OAuth 2.0 endpoints required by Claude connectors
-- (and other RFC 8414 / RFC 9728 / RFC 6749 clients) without an actual login
-- step. Auth codes are stateless: HMAC-signed JSON using the configured
-- client_secret. The issued access_token is the configured access_token (or
-- the client_secret if no access_token is provided).

json = require "cjson.safe"

import respond_to from require "lapis.application"
import encode_base64, encode_with_secret, decode_with_secret, decode_base64 from require "lapis.util.encoding"
import encode_query_string, unescape from require "lapis.util"

base64url_no_pad = (s) ->
  encoded = encode_base64 s
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

decode_basic_part = (part) ->
  unescape part\gsub "%+", " "

class OauthConfig
  new: (@opts, @mount_path="/") =>
    assert @opts.client_id, "oauth.client_id is required"
    assert @opts.client_secret, "oauth.client_secret is required"

  public_base_url: (req) =>
    scheme = req.headers["x-forwarded-proto"] or (req.parsed_url and req.parsed_url.scheme) or "http"
    host = req.headers["x-forwarded-host"] or req.headers["host"] or "localhost"
    base = @opts.public_base_url or "#{scheme}://#{host}"
    base = base\gsub "/+$", "" if @opts.public_base_url
    base

  mount_path_segment: =>
    return "" unless @mount_path
    return "" if @mount_path == "" or @mount_path == "/"
    @mount_path

  resource_url: (req) =>
    @opts.resource or @public_base_url(req) .. @mount_path_segment!

  protected_resource_metadata_url: (req) =>
    "#{@public_base_url(req)}/.well-known/oauth-protected-resource#{@mount_path_segment!}"

  issuer_url: (req) =>
    return @opts.issuer if @opts.issuer
    base = @public_base_url req
    segment = @mount_path_segment!
    return base if segment == ""
    "#{base}#{segment}"

  verify_bearer_token: (header) =>
    return false unless header
    token = header\match "^[Bb]earer (.+)$"
    return false unless token
    token == (@opts.access_token or @opts.client_secret)

  protected_resource_handler: =>
    config = @
    (route) ->
      issuer = config\issuer_url route.req
      {
        json: {
          resource: config\resource_url route.req
          authorization_servers: setmetatable {issuer}, json.array_mt
          bearer_methods_supported: setmetatable {"header"}, json.array_mt
        }
        headers: {
          ["Cache-Control"]: "public, max-age=3600"
          ["Access-Control-Allow-Origin"]: "*"
        }
      }

  authorization_server_handler: =>
    config = @
    (route) ->
      issuer = config\issuer_url route.req
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

  authorize_handler: =>
    config = @
    respond_to {
      GET: (route) ->
        params = route.params
        response_type = params.response_type
        client_id = params.client_id
        redirect_uri = params.redirect_uri
        state = params.state
        code_challenge = params.code_challenge
        code_challenge_method = params.code_challenge_method or "plain"

        unless response_type == "code"
          return status: 400, json: {error: "unsupported_response_type"}

        unless client_id == config.opts.client_id
          return status: 400, json: {error: "invalid_client"}

        unless redirect_uri
          return status: 400, json: {error: "invalid_request", error_description: "missing redirect_uri"}

        code = encode_with_secret {
          cid: client_id
          ru: redirect_uri
          cc: code_challenge
          ccm: code_challenge_method
          exp: os.time! + 600
        }, config.opts.client_secret

        qs_params = {code: code}
        qs_params.state = state if state

        sep = redirect_uri\find("?", 1, true) and "&" or "?"
        {
          redirect_to: redirect_uri .. sep .. encode_query_string qs_params
        }
    }

  token_handler: =>
    config = @
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
          access_token: config.opts.access_token or config.opts.client_secret
          token_type: "Bearer"
          expires_in: config.opts.access_token_ttl or 3600
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
      on_invalid_method: (route) ->
        status: 405, layout: false, headers: cors_headers

      OPTIONS: (route) ->
        status: 204, layout: false, headers: cors_headers

      POST: (route) ->
        args = route.params

        auth_header = route.req.headers["authorization"]
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

        unless client_id == config.opts.client_id and client_secret == config.opts.client_secret
          return error_response 401, "invalid_client"

        switch args.grant_type
          when "authorization_code"
            code_data, err = decode_with_secret args.code or "", config.opts.client_secret
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

  routes: =>
    segment = @mount_path_segment!
    authorize_path = if @mount_path == "/" then "/oauth/authorize" else "#{@mount_path}/oauth/authorize"
    token_path = if @mount_path == "/" then "/oauth/token" else "#{@mount_path}/oauth/token"
    {
      {
        path: "/.well-known/oauth-protected-resource#{segment}"
        handler: @protected_resource_handler!
      }
      {
        path: "/.well-known/oauth-authorization-server#{segment}"
        handler: @authorization_server_handler!
      }
      {
        path: authorize_path
        handler: @authorize_handler!
      }
      {
        path: token_path
        handler: @token_handler!
      }
    }

{
  :OauthConfig
}
