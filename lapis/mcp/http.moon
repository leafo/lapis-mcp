json = require "cjson.safe"
oauth_shim = require "lapis.mcp.oauth"

import respond_to from require "lapis.application"

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
    ["Access-Control-Allow-Headers"]: "Content-Type, Accept, Mcp-Session-Id, Authorization"
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

mcp_handler = (ServerClass, opts={}) ->
  oauth = opts.oauth
  mount_path = opts.path or "/"

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

      if oauth and @req.cmd_mth != "OPTIONS"
        unless oauth_shim.verify_bearer_token oauth, @req.headers["authorization"]
          metadata_url = oauth_shim.protected_resource_metadata_url @req, oauth, mount_path
          @write {
            json: {error: "unauthorized"}
            status: 401
            headers: merge_headers @cors_headers, {
              ["WWW-Authenticate"]: "Bearer realm=\"mcp\", resource_metadata=\"#{metadata_url}\""
            }
          }
          return

      -- Create fresh server instance for this request
      server = ServerClass opts.server_options or {}
      server\skip_initialize!
      server.transport = HttpNoopTransport!

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

      response = @mcp_server\handle_message message
      if response
        out = {
          json: response
          headers: @cors_headers
        }
        if message.method == "initialize" and opts.create_session_id
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

serve = (server_module, opts={}) ->
  ServerClass = if type(server_module) == "string"
    require server_module
  else
    server_module

  lapis = require "lapis"

  app = lapis.Application!

  mount_path = opts.path or "/"

  if opts.oauth
    oauth_shim.register_routes app, opts.oauth, mount_path

  app\match mount_path, mcp_handler ServerClass, opts
  lapis.serve app

{:mcp_handler, :HttpNoopTransport, :serve}
