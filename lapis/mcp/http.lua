local json = require("cjson.safe")
local respond_to
respond_to = require("lapis.application").respond_to
local HttpNoopTransport
do
  local _class_0
  local _base_0 = {
    read_json_chunk = function(self)
      return error("not supported in HTTP mode")
    end,
    write_json_chunk = function(self) end
  }
  _base_0.__index = _base_0
  _class_0 = setmetatable({
    __init = function() end,
    __base = _base_0,
    __name = "HttpNoopTransport"
  }, {
    __index = _base_0,
    __call = function(cls, ...)
      local _self_0 = setmetatable({}, _base_0)
      cls.__init(_self_0, ...)
      return _self_0
    end
  })
  _base_0.__class = _class_0
  HttpNoopTransport = _class_0
end
local find_allowed_origin
find_allowed_origin = function(origin, allowed_origins)
  if not (origin) then
    return nil
  end
  if allowed_origins == "*" then
    return "*"
  end
  if type(allowed_origins) == "table" then
    for _index_0 = 1, #allowed_origins do
      local allowed_origin = allowed_origins[_index_0]
      if allowed_origin == origin then
        return origin
      end
    end
  end
  return nil
end
local build_cors_headers
build_cors_headers = function(origin, allowed_origin)
  if not (origin and allowed_origin) then
    return nil
  end
  return {
    ["Access-Control-Allow-Origin"] = allowed_origin,
    ["Access-Control-Allow-Methods"] = "POST, OPTIONS",
    ["Access-Control-Allow-Headers"] = "Content-Type, Accept, Mcp-Session-Id, Authorization",
    ["Access-Control-Expose-Headers"] = "Mcp-Session-Id, WWW-Authenticate",
    ["Vary"] = "Origin"
  }
end
local merge_headers
merge_headers = function(base, extra)
  if not (base) then
    return extra
  end
  if not (extra) then
    return base
  end
  local out
  do
    local _tbl_0 = { }
    for k, v in pairs(base) do
      _tbl_0[k] = v
    end
    out = _tbl_0
  end
  for k, v in pairs(extra) do
    out[k] = v
  end
  return out
end
local normalize_mount_path
normalize_mount_path = function(path)
  path = path or "/"
  assert(type(path) == "string", "MCP mount path must be a string")
  assert(path ~= "", "MCP mount path must not be empty")
  assert(path:sub(1, 1) == "/", "MCP mount path must start with /")
  if not (path == "/") then
    path = path:gsub("/+$", "")
  end
  return path
end
local server_class_for
server_class_for = function(server_module)
  if type(server_module) == "string" then
    return require(server_module)
  else
    return server_module
  end
end
local verify_static_bearer
verify_static_bearer = function(header, expected)
  if not (header and expected) then
    return false
  end
  local scheme, token = header:match("^(%S+)%s+(.+)$")
  if not (scheme and scheme:lower() == "bearer") then
    return false
  end
  if not (token) then
    return false
  end
  return token == expected
end
local mcp_handler
mcp_handler = function(ServerClass, opts)
  if opts == nil then
    opts = { }
  end
  local oauth = opts.oauth
  local bearer_token = opts.bearer_token
  assert(not (oauth and bearer_token), "MCP mount cannot set both 'oauth' and 'bearer_token'")
  local mount_path = opts.path or "/"
  local oauth_config
  if oauth then
    local oauth_shim = require("lapis.mcp.oauth")
    oauth_config = oauth_shim.OauthConfig(oauth, mount_path)
  end
  return respond_to({
    before = function(self)
      local origin = self.req.headers["origin"]
      if origin then
        local allowed_origin = find_allowed_origin(origin, opts.allowed_origins)
        if not (allowed_origin) then
          self:write({
            json = {
              error = "Origin not allowed"
            },
            status = 403,
            headers = {
              ["Vary"] = "Origin"
            }
          })
          return 
        end
        self.cors_headers = build_cors_headers(origin, allowed_origin)
      end
      if self.req.cmd_mth ~= "OPTIONS" then
        if oauth then
          if not (oauth_config:verify_bearer_token(self.req.headers["authorization"])) then
            local metadata_url = oauth_config:protected_resource_metadata_url(self.req)
            self:write({
              json = {
                error = "unauthorized"
              },
              status = 401,
              headers = merge_headers(self.cors_headers, {
                ["WWW-Authenticate"] = "Bearer realm=\"mcp\", resource_metadata=\"" .. tostring(metadata_url) .. "\""
              })
            })
            return 
          end
        elseif bearer_token then
          if not (verify_static_bearer(self.req.headers["authorization"], bearer_token)) then
            self:write({
              json = {
                error = "unauthorized"
              },
              status = 401,
              headers = merge_headers(self.cors_headers, {
                ["WWW-Authenticate"] = "Bearer realm=\"mcp\""
              })
            })
            return 
          end
        end
      end
      local server = ServerClass(opts.server_options or { })
      server:skip_initialize()
      server.transport = HttpNoopTransport()
      if opts.load_session then
        opts.load_session(self, server)
      end
      self.mcp_server = server
    end,
    OPTIONS = function(self)
      return {
        status = 204,
        layout = false,
        headers = self.cors_headers
      }
    end,
    POST = function(self)
      local accept = self.req.headers["accept"] or ""
      if not (accept:find("application/json", 1, true) and accept:find("text/event-stream", 1, true)) then
        return {
          json = {
            error = "Not Acceptable: must accept application/json and text/event-stream"
          },
          status = 406,
          headers = self.cors_headers
        }
      end
      ngx.req.read_body()
      local body = ngx.req.get_body_data()
      if not (body) then
        return {
          json = {
            jsonrpc = "2.0",
            error = {
              code = -32700,
              message = "Parse error: empty body"
            }
          },
          status = 400,
          headers = self.cors_headers
        }
      end
      local message = json.decode(body)
      if not (message) then
        return {
          json = {
            jsonrpc = "2.0",
            error = {
              code = -32700,
              message = "Parse error: invalid JSON"
            }
          },
          status = 400,
          headers = self.cors_headers
        }
      end
      local response = self.mcp_server:handle_message(message)
      if response then
        local out = {
          json = response,
          headers = self.cors_headers
        }
        if message.method == "initialize" and opts.create_session_id then
          local session_id = opts.create_session_id(self, self.mcp_server)
          if session_id then
            out.headers = merge_headers(out.headers, {
              ["Mcp-Session-Id"] = session_id
            })
          end
        end
        return out
      else
        return {
          status = 202,
          layout = false,
          headers = self.cors_headers
        }
      end
    end,
    GET = function(self)
      return {
        status = 405,
        layout = false
      }
    end,
    DELETE = function(self)
      return {
        status = 405,
        layout = false
      }
    end
  })
end
local McpHttpRouter
do
  local _class_0
  local _base_0 = {
    mount = function(self, path, server_module, opts)
      if opts == nil then
        opts = { }
      end
      path = normalize_mount_path(path)
      do
        local _tbl_0 = { }
        for k, v in pairs(opts) do
          _tbl_0[k] = v
        end
        opts = _tbl_0
      end
      opts.path = path
      table.insert(self.mounts, {
        path = path,
        ServerClass = server_class_for(server_module),
        opts = opts
      })
      return self
    end,
    install = function(self, app)
      local oauth_shim = require("lapis.mcp.oauth")
      local claimed = { }
      local claim_route
      claim_route = function(route, owner)
        if claimed[route] then
          error("MCP HTTP route collision: " .. tostring(route) .. " claimed by " .. tostring(claimed[route]) .. " and " .. tostring(owner))
        end
        claimed[route] = owner
      end
      local _list_0 = self.mounts
      for _index_0 = 1, #_list_0 do
        local mount = _list_0[_index_0]
        local owner = "MCP mount " .. tostring(mount.path)
        claim_route(mount.path, owner)
        if mount.opts.oauth then
          local config = oauth_shim.OauthConfig(mount.opts.oauth, mount.path)
          local routes = config:routes()
          for _index_1 = 1, #routes do
            local route = routes[_index_1]
            claim_route(route.path, owner)
            app:match(route.path, route.handler)
          end
        end
        app:match(mount.path, mcp_handler(mount.ServerClass, mount.opts))
      end
      return app
    end
  }
  _base_0.__index = _base_0
  _class_0 = setmetatable({
    __init = function(self)
      self.mounts = { }
    end,
    __base = _base_0,
    __name = "McpHttpRouter"
  }, {
    __index = _base_0,
    __call = function(cls, ...)
      local _self_0 = setmetatable({}, _base_0)
      cls.__init(_self_0, ...)
      return _self_0
    end
  })
  _base_0.__class = _class_0
  McpHttpRouter = _class_0
end
local serve
serve = function(server_module, opts)
  if opts == nil then
    opts = { }
  end
  local lapis = require("lapis")
  local app = lapis.Application()
  local router = McpHttpRouter()
  router:mount(opts.path or "/", server_module, opts)
  router:install(app)
  return lapis.serve(app)
end
return {
  mcp_handler = mcp_handler,
  HttpNoopTransport = HttpNoopTransport,
  McpHttpRouter = McpHttpRouter,
  serve = serve
}
