-- OAuth 2.0 endpoints required by Claude connectors and other MCP clients:
-- RFC 9728 protected resource metadata, RFC 8414 authorization server
-- metadata, the authorize endpoint and the token endpoint.
--
-- The validation every authorization request needs (redirect_uri, PKCE S256,
-- RFC 9207 iss) happens here. How clients are identified, approved and issued
-- tokens is up to the mode. The only mode is StaticMode, see
-- lapis.mcp.oauth.static.

json = require "cjson.safe"

import respond_to from require "lapis.application"
import verify_bearer, is_s256_challenge, redirect_uri_allowed, redirect_to_client from require "lapis.mcp.oauth.util"
import StaticMode from require "lapis.mcp.oauth.static"

class OauthConfig
  new: (@opts, @mount_path="/") =>
    @mode = StaticMode @opts

    if uris = @opts.allowed_redirect_uris
      assert type(uris) == "table", "oauth.allowed_redirect_uris must be an array of strings"
      for uri in *uris
        assert type(uri) == "string", "oauth.allowed_redirect_uris must be an array of strings"

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
    @mode\verify_bearer_token header

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
      metadata = {
        issuer: issuer
        authorization_endpoint: "#{issuer}/oauth/authorize"
        token_endpoint: "#{issuer}/oauth/token"
        response_types_supported: setmetatable {"code"}, json.array_mt
        code_challenge_methods_supported: setmetatable {"S256"}, json.array_mt
        authorization_response_iss_parameter_supported: true
      }

      for k, v in pairs config.mode\server_metadata!
        metadata[k] = v

      {
        json: metadata
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
        -- RFC 7636 defaults a missing method to plain, which is not supported
        code_challenge_method = params.code_challenge_method or "plain"

        -- Errors before redirect_uri is validated must not redirect, they are
        -- shown to the user directly (RFC 6749 section 4.1.2.1)
        if err_response = config.mode\check_client client_id
          return err_response

        unless type(redirect_uri) == "string"
          return status: 400, json: {error: "invalid_request", error_description: "missing redirect_uri"}

        if redirect_uri\find "#", 1, true
          return status: 400, json: {error: "invalid_request", error_description: "redirect_uri must not contain a fragment"}

        if config.opts.allowed_redirect_uris
          unless redirect_uri_allowed redirect_uri, config.opts.allowed_redirect_uris
            return status: 400, json: {error: "invalid_request", error_description: "redirect_uri not allowed"}

        -- RFC 9207 issuer identification, lets the client detect mix-up
        -- attacks, included on both success and error responses
        iss = config\issuer_url route.req

        redirect_error = (error_code, description) ->
          redirect_to_client redirect_uri, {
            error: error_code
            error_description: description
            :state
            :iss
          }

        unless response_type == "code"
          return redirect_error "unsupported_response_type", "response_type must be code"

        unless code_challenge and code_challenge != ""
          return redirect_error "invalid_request", "PKCE code_challenge is required"

        unless code_challenge_method == "S256"
          return redirect_error "invalid_request", "code_challenge_method must be S256"

        unless is_s256_challenge code_challenge
          return redirect_error "invalid_request", "code_challenge is not a valid S256 challenge"

        config.mode\authorize route, {
          :client_id
          :redirect_uri
          :state
          :code_challenge
          :iss
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
        token, status, code, description = config.mode\token_request route
        unless token
          return error_response status, code, description

        {
          json: token
          headers: merge cors_headers, {
            ["Cache-Control"]: "no-store"
          }
        }
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
  :verify_bearer
  :redirect_uri_allowed
}
