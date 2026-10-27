local json = require("cjson.safe")
local encode_with_secret, decode_with_secret, decode_base64
do
  local _obj_0 = require("lapis.util.encoding")
  encode_with_secret, decode_with_secret, decode_base64 = _obj_0.encode_with_secret, _obj_0.decode_with_secret, _obj_0.decode_base64
end
local unescape
unescape = require("lapis.util").unescape
local secure_compare, parse_authorization, verify_bearer, verify_pkce, redirect_to_client
do
  local _obj_0 = require("lapis.mcp.oauth.util")
  secure_compare, parse_authorization, verify_bearer, verify_pkce, redirect_to_client = _obj_0.secure_compare, _obj_0.parse_authorization, _obj_0.verify_bearer, _obj_0.verify_pkce, _obj_0.redirect_to_client
end
local decode_basic_part
decode_basic_part = function(part)
  return unescape(part:gsub("%+", " "))
end
local StaticMode
do
  local _class_0
  local _base_0 = {
    access_token = function(self)
      return self.opts.access_token or self.opts.client_secret
    end,
    server_metadata = function(self)
      return {
        grant_types_supported = setmetatable({
          "authorization_code",
          "client_credentials"
        }, json.array_mt),
        token_endpoint_auth_methods_supported = setmetatable({
          "client_secret_post",
          "client_secret_basic"
        }, json.array_mt)
      }
    end,
    check_client = function(self, client_id)
      if not (client_id == self.opts.client_id) then
        return {
          status = 400,
          json = {
            error = "invalid_client"
          }
        }
      end
    end,
    authorize = function(self, route, request)
      local code = encode_with_secret({
        cid = request.client_id,
        ru = request.redirect_uri,
        cc = request.code_challenge,
        exp = os.time() + 600
      }, self.opts.client_secret)
      return redirect_to_client(request.redirect_uri, {
        code = code,
        state = request.state,
        iss = request.iss
      })
    end,
    token_request = function(self, route)
      local args = route.params
      local client_id = args.client_id
      local client_secret = args.client_secret
      local scheme, basic_creds = parse_authorization(route.req.headers["authorization"])
      if scheme == "basic" then
        local decoded = decode_base64(basic_creds)
        if decoded then
          local cid, csec = decoded:match("^([^:]*):(.*)$")
          if cid then
            client_id = decode_basic_part(cid)
          end
          if csec then
            client_secret = decode_basic_part(csec)
          end
        end
      end
      if not (client_id == self.opts.client_id and secure_compare(client_secret, self.opts.client_secret)) then
        return nil, 401, "invalid_client"
      end
      local _exp_0 = args.grant_type
      if "authorization_code" == _exp_0 then
        local code_data, err = decode_with_secret(args.code or "", self.opts.client_secret)
        if not (code_data) then
          return nil, 400, "invalid_grant", err
        end
        if code_data.exp and code_data.exp < os.time() then
          return nil, 400, "invalid_grant", "code expired"
        end
        if not (code_data.cid == client_id) then
          return nil, 400, "invalid_grant", "client_id mismatch"
        end
        if not (code_data.ru == args.redirect_uri) then
          return nil, 400, "invalid_grant", "redirect_uri mismatch"
        end
        if not (verify_pkce(args.code_verifier, code_data.cc)) then
          return nil, 400, "invalid_grant", "PKCE verification failed"
        end
        return self:issue_token()
      elseif "client_credentials" == _exp_0 then
        return self:issue_token()
      else
        return nil, 400, "unsupported_grant_type"
      end
    end,
    issue_token = function(self)
      return {
        access_token = self:access_token(),
        token_type = "Bearer",
        expires_in = self.opts.access_token_ttl or 3600
      }
    end,
    verify_bearer_token = function(self, header)
      return verify_bearer(header, self:access_token())
    end
  }
  _base_0.__index = _base_0
  _class_0 = setmetatable({
    __init = function(self, opts)
      self.opts = opts
      assert(self.opts.client_id, "oauth.client_id is required")
      return assert(self.opts.client_secret, "oauth.client_secret is required")
    end,
    __base = _base_0,
    __name = "StaticMode"
  }, {
    __index = _base_0,
    __call = function(cls, ...)
      local _self_0 = setmetatable({}, _base_0)
      cls.__init(_self_0, ...)
      return _self_0
    end
  })
  _base_0.__class = _class_0
  StaticMode = _class_0
end
return {
  StaticMode = StaticMode
}
