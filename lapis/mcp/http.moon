json = require "cjson.safe"

import respond_to from require "lapis.application"
import OauthConfig, verify_bearer from require "lapis.mcp.oauth"

-- There is no stream to deliver server initiated notifications over HTTP, so
-- don't advertise any capability that depends on them
NOTIFICATION_CAPABILITY_FLAGS = { "listChanged", "subscribe" }

without_notifications = (capabilities) ->
  out = {}
  for name, capability in pairs capabilities
    out[name] = if type(capability) == "table"
      copy = {k, v for k, v in pairs capability}
      for flag in *NOTIFICATION_CAPABILITY_FLAGS
        copy[flag] = false if copy[flag] != nil
      copy
    else
      capability

  out

class HttpNoopTransport
  read_json_chunk: =>
    error "not supported in HTTP mode"

  write_json_chunk: =>
    -- silently discard (notifications have no connection to push to)

find_allowed_origin = (origin, allowed_origins) ->
  return nil unless origin

  if allowed_origins == "*"
    return "*"

  if type(allowed_origins) == "table"
    for allowed_origin in *allowed_origins
      return origin if allowed_origin == origin

  nil

build_cors_headers = (origin, allowed_origin) ->
  return nil unless origin and allowed_origin

  {
    ["Access-Control-Allow-Origin"]: allowed_origin
    ["Access-Control-Allow-Methods"]: "POST, OPTIONS"
    ["Access-Control-Allow-Headers"]: "Content-Type, Accept, Mcp-Session-Id, MCP-Protocol-Version, Authorization"
    ["Access-Control-Expose-Headers"]: "Mcp-Session-Id, WWW-Authenticate"
    ["Vary"]: "Origin"
  }

merge_headers = (base, extra) ->
  return extra unless base
  return base unless extra

  out = {k,v for k,v in pairs base}
  for k,v in pairs extra
    out[k] = v

  out

normalize_mount_path = (path) ->
  path or= "/"
  assert type(path) == "string", "MCP mount path must be a string"
  assert path != "", "MCP mount path must not be empty"
  assert path\sub(1, 1) == "/", "MCP mount path must start with /"
  path = path\gsub "/+$", "" unless path == "/"
  path

server_class_for = (server_module) ->
  if type(server_module) == "string"
    require server_module
  else
    server_module


-- oauth_config is passed by the router so the mount's routes and its bearer
-- checks share one config, otherwise it's built from opts.oauth
mcp_handler = (ServerClass, opts={}, oauth_config) ->
  oauth = opts.oauth
  bearer_token = opts.bearer_token
  assert not (oauth and bearer_token), "MCP mount cannot set both 'oauth' and 'bearer_token'"

  mount_path = opts.path or "/"

  if oauth
    oauth_config or= OauthConfig oauth, mount_path

  respond_to {
    before: =>
      origin = @req.headers["origin"]
      if origin
        allowed_origin = find_allowed_origin origin, opts.allowed_origins
        unless allowed_origin
          @write {
            json: {error: "Origin not allowed"}
            status: 403
            headers: {
              ["Vary"]: "Origin"
            }
          }
          return
        @cors_headers = build_cors_headers origin, allowed_origin

      -- CORS preflight is unauthenticated and only needs the headers, so no
      -- server is created and load_session doesn't run
      return if @req.cmd_mth == "OPTIONS"

      -- describes how the request was authorized, set as server.auth
      auth = nil

      if oauth
        auth = oauth_config\verify_bearer_token @req.headers["authorization"], @req
        unless auth
          metadata_url = oauth_config\protected_resource_metadata_url @req
          @write {
            json: {error: "unauthorized"}
            status: 401
            headers: merge_headers @cors_headers, {
              ["WWW-Authenticate"]: "Bearer realm=\"mcp\", resource_metadata=\"#{metadata_url}\""
            }
          }
          return
      elseif bearer_token
        unless verify_bearer @req.headers["authorization"], bearer_token
          @write {
            json: {error: "unauthorized"}
            status: 401
            headers: merge_headers @cors_headers, {
              ["WWW-Authenticate"]: "Bearer realm=\"mcp\""
            }
          }
          return
        auth = {static: true}

      -- Create fresh server instance for this request
      server = ServerClass opts.server_options or {}
      server\skip_initialize!
      server.transport = HttpNoopTransport!
      server.auth = auth
      server.server_capabilities = without_notifications server.server_capabilities

      if opts.load_session
        opts.load_session @, server

      @mcp_server = server

    OPTIONS: =>
      {
        status: 204
        layout: false
        headers: @cors_headers
      }

    POST: =>
      -- Validate Accept header
      accept = @req.headers["accept"] or ""
      unless accept\find("application/json", 1, true) and accept\find("text/event-stream", 1, true)
        return {
          json: {error: "Not Acceptable: must accept application/json and text/event-stream"}
          status: 406
          headers: @cors_headers
        }

      -- Read and parse body
      ngx.req.read_body!
      body = ngx.req.get_body_data!
      unless body
        return {
          json: {
            jsonrpc: "2.0"
            error: {code: -32700, message: "Parse error: empty body"}
          }
          status: 400
          headers: @cors_headers
        }

      message = json.decode body
      unless message
        return {
          json: {
            jsonrpc: "2.0"
            error: {code: -32700, message: "Parse error: invalid JSON"}
          }
          status: 400
          headers: @cors_headers
        }

      -- the header is absent on initialize and from clients older than
      -- 2025-06-18, both of which are accepted
      protocol_version = @req.headers["mcp-protocol-version"]
      is_initialize = type(message) == "table" and message.method == "initialize"
      if protocol_version != nil and not is_initialize
        versions = @mcp_server\get_supported_protocol_versions!
        is_supported = false
        for v in *versions
          if v == protocol_version
            is_supported = true
            break

        unless is_supported
          request_id = type(message) == "table" and message.id
          return {
            json: {
              jsonrpc: "2.0"
              id: request_id or json.null
              error: {
                code: -32000
                message: "Bad Request: Unsupported protocol version: #{protocol_version} (supported versions: #{table.concat versions, ", "})"
              }
            }
            status: 400
            headers: @cors_headers
          }

      response = @mcp_server\handle_message message
      if response
        out = {
          json: response
          headers: @cors_headers
        }
        if is_initialize and opts.create_session_id
          session_id = opts.create_session_id @, @mcp_server
          if session_id
            out.headers = merge_headers out.headers, {"Mcp-Session-Id": session_id}
        return out
      else
        return status: 202, layout: false, headers: @cors_headers

    GET: =>
      status: 405, layout: false

    DELETE: =>
      status: 405, layout: false
  }

class McpHttpRouter
  new: =>
    @mounts = {}

  mount: (path, server_module, opts={}) =>
    path = normalize_mount_path path
    opts = {k, v for k, v in pairs opts}
    opts.path = path
    table.insert @mounts, {
      :path
      ServerClass: server_class_for server_module
      :opts
    }
    @

  install: (app) =>
    claimed = {}

    claim_route = (route, owner) ->
      if claimed[route]
        error "MCP HTTP route collision: #{route} claimed by #{claimed[route]} and #{owner}"
      claimed[route] = owner

    for mount in *@mounts
      owner = "MCP mount #{mount.path}"
      claim_route mount.path, owner

      local config
      if mount.opts.oauth
        config = OauthConfig mount.opts.oauth, mount.path
        routes = config\routes!
        for route in *routes
          claim_route route.path, owner
          app\match route.path, route.handler

      app\match mount.path, mcp_handler mount.ServerClass, mount.opts, config

    app

  -- returns a new lapis.Application subclass with the routes installed, for
  -- including into an existing app with @include
  application: =>
    lapis = require "lapis"
    class McpApplication extends lapis.Application
    @install McpApplication

serve = (server_module, opts={}) ->
  lapis = require "lapis"

  app = lapis.Application!
  router = McpHttpRouter!
  router\mount opts.path or "/", server_module, opts
  router\install app
  lapis.serve app

{:mcp_handler, :HttpNoopTransport, :McpHttpRouter, :serve}
