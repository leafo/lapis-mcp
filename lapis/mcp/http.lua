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
    ["Access-Control-Allow-Headers"] = "Content-Type, Accept, Mcp-Session-Id",
    ["Access-Control-Expose-Headers"] = "Mcp-Session-Id",
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
local mcp_handler
mcp_handler = function(ServerClass, opts)
  if opts == nil then
    opts = { }
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
      local is_batch = type(message) == "table" and message[1] ~= nil
      if is_batch then
        local responses = { }
        for _index_0 = 1, #message do
          local msg = message[_index_0]
          local response = self.mcp_server:handle_message(msg)
          if response then
            table.insert(responses, response)
          end
        end
        if #responses == 0 then
          return {
            status = 202,
            layout = false,
            headers = self.cors_headers
          }
        else
          return {
            json = responses,
            headers = self.cors_headers
          }
        end
      else
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
return {
  mcp_handler = mcp_handler,
  HttpNoopTransport = HttpNoopTransport
}
