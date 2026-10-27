local json = require("cjson.safe")
local encode_with_secret, decode_with_secret
do
  local _obj_0 = require("lapis.util.encoding")
  encode_with_secret, decode_with_secret = _obj_0.encode_with_secret, _obj_0.decode_with_secret
end
local ClientMetadata
ClientMetadata = require("lapis.mcp.oauth.client_metadata").ClientMetadata
local secure_compare, parse_authorization, verify_pkce, redirect_to_client, sha256_hex, random_token, parse_uri, is_loopback_uri, same_resource
do
  local _obj_0 = require("lapis.mcp.oauth.util")
  secure_compare, parse_authorization, verify_pkce, redirect_to_client, sha256_hex, random_token, parse_uri, is_loopback_uri, same_resource = _obj_0.secure_compare, _obj_0.parse_authorization, _obj_0.verify_pkce, _obj_0.redirect_to_client, _obj_0.sha256_hex, _obj_0.random_token, _obj_0.parse_uri, _obj_0.is_loopback_uri, _obj_0.same_resource
end
local CODE_TTL = 60
local CONSENT_TTL = 10 * 60
local DEFAULT_ACCESS_TOKEN_TTL = 90 * 24 * 60 * 60
local SESSION_KEY = "mcp_consent_key"
local CONSENT_HEADERS = {
  ["X-Frame-Options"] = "DENY",
  ["Content-Security-Policy"] = "frame-ancestors 'none'",
  ["Cache-Control"] = "no-store"
}
local client_error
client_error = function(description)
  return {
    status = 400,
    json = {
      error = "invalid_client",
      error_description = description
    }
  }
end
local consent_error
consent_error = function(description)
  return {
    status = 400,
    json = {
      error = "invalid_request",
      error_description = description
    }
  }
end
local same_owner
same_owner = function(a, b)
  if not (type(a) == "table" and type(b) == "table") then
    return false
  end
  for k, v in pairs(a) do
    if not (b[k] == v) then
      return false
    end
  end
  for k, v in pairs(b) do
    if not (a[k] == v) then
      return false
    end
  end
  return true
end
local SiteMode
do
  local _class_0
  local _base_0 = {
    server_metadata = function(self)
      return {
        grant_types_supported = setmetatable({
          "authorization_code"
        }, json.array_mt),
        token_endpoint_auth_methods_supported = setmetatable({
          "none"
        }, json.array_mt),
        client_id_metadata_document_supported = true
      }
    end,
    check_client = function(self, route, client_id)
      local host, _, description = self.clients:check(client_id)
      if not (host) then
        return nil, client_error(description)
      end
      if not (self.opts.current_user(route)) then
        local query = route.req.parsed_url.query
        local return_to = self.config:authorize_url(route.req)
        if query and query ~= "" then
          return_to = return_to .. "?" .. tostring(query)
        end
        return nil, {
          redirect_to = self.opts.login_url(route, return_to)
        }
      end
      local client
      client, _, description = self.clients:resolve(client_id)
      if not (client) then
        return nil, client_error(description)
      end
      return client
    end,
    authorize = function(self, route, request)
      if request.requested_resource ~= nil and not same_resource(request.requested_resource, request.resource) then
        return redirect_to_client(request.redirect_uri, {
          error = "invalid_target",
          error_description = "resource must be " .. tostring(request.resource),
          state = request.state,
          iss = request.iss
        })
      end
      local key = route.session[SESSION_KEY]
      if not (key) then
        key = random_token()
        route.session[SESSION_KEY] = key
      end
      local client = request.client
      local owner = self.grants:owner_values(self.opts.current_user(route))
      local consent_token = encode_with_secret({
        key = key,
        owner = owner,
        exp = os.time() + CONSENT_TTL,
        request = {
          client_id = request.client_id,
          client_name = client.client_name,
          redirect_uri = request.redirect_uri,
          state = request.state,
          code_challenge = request.code_challenge,
          resource = request.resource,
          iss = request.iss
        }
      })
      local _, redirect_host = parse_uri(request.redirect_uri)
      local res = self.opts.render_consent(route, {
        client_id = request.client_id,
        client_name = client.client_name,
        client_host = client.host,
        client_trusted = client.trusted,
        redirect_uri = request.redirect_uri,
        redirect_host = redirect_host,
        redirect_loopback = is_loopback_uri(request.redirect_uri),
        action = self.config:authorize_url(route.req),
        consent_token = consent_token
      })
      if type(res) == "table" then
        local headers
        do
          local _tbl_0 = { }
          for k, v in pairs(res.headers or { }) do
            _tbl_0[k] = v
          end
          headers = _tbl_0
        end
        for k, v in pairs(CONSENT_HEADERS) do
          if headers[k] == nil then
            headers[k] = v
          end
        end
        res.headers = headers
      end
      return res
    end,
    consent_post = function(self, route)
      local token = route.params.consent_token
      if not (type(token) == "string") then
        return consent_error("invalid consent_token")
      end
      local data = decode_with_secret(token)
      if not (type(data) == "table" and type(data.request) == "table") then
        return consent_error("invalid consent_token")
      end
      if not (type(data.exp) == "number" and data.exp > os.time()) then
        return consent_error("consent_token expired, try connecting again")
      end
      if not (secure_compare(data.key, route.session[SESSION_KEY])) then
        return consent_error("consent_token is for another session")
      end
      local user = self.opts.current_user(route)
      if not (user) then
        return consent_error("you are no longer logged in")
      end
      local owner = self.grants:owner_values(user)
      if not (same_owner(owner, data.owner)) then
        return consent_error("you've logged in as someone else, try connecting again")
      end
      local request = data.request
      local respond
      respond = function(params)
        params.state = request.state
        params.iss = request.iss
        return redirect_to_client(request.redirect_uri, params)
      end
      if not (route.params.approve) then
        return respond({
          error = "access_denied",
          error_description = "the user denied access"
        })
      end
      local code = random_token()
      local values
      do
        local _tbl_0 = { }
        for k, v in pairs(owner) do
          _tbl_0[k] = v
        end
        values = _tbl_0
      end
      values.client_id = request.client_id
      values.client_name = request.client_name
      values.redirect_uri = request.redirect_uri
      values.code_challenge = request.code_challenge
      values.resource = request.resource
      values.code_hash = sha256_hex(code)
      local grant = self.grants:create_for_code(values, CODE_TTL)
      if not (grant) then
        error("grants\\create_for_code didn't return a grant")
      end
      if self.opts.grant_created then
        self.opts.grant_created(route, grant)
      end
      return respond({
        code = code
      })
    end,
    token_request = function(self, route)
      local args = route.params
      if not (args.grant_type == "authorization_code") then
        return nil, 400, "unsupported_grant_type"
      end
      if not (type(args.code) == "string" and args.code ~= "") then
        return nil, 400, "invalid_request", "missing code"
      end
      local access_token = random_token()
      local grant = self.grants:redeem_code(sha256_hex(args.code), {
        access_hash = sha256_hex(access_token),
        access_ttl = self.access_token_ttl
      })
      if not (grant) then
        return nil, 400, "invalid_grant", "unknown or expired code"
      end
      local reject
      reject = function(code, description)
        grant:delete()
        return nil, 400, code, description
      end
      if not (grant.resource == self.config:resource_url(route.req)) then
        return reject("invalid_grant", "code was issued for another resource")
      end
      if not (args.client_id == grant.client_id) then
        return reject("invalid_grant", "client_id mismatch")
      end
      if not (args.redirect_uri == grant.redirect_uri) then
        return reject("invalid_grant", "redirect_uri mismatch")
      end
      if not (verify_pkce(args.code_verifier, grant.code_challenge)) then
        return reject("invalid_grant", "PKCE verification failed")
      end
      if args.resource ~= nil and not same_resource(args.resource, grant.resource) then
        return reject("invalid_target", "resource mismatch")
      end
      return {
        access_token = access_token,
        token_type = "Bearer",
        expires_in = self.access_token_ttl
      }
    end,
    verify_bearer_token = function(self, header, req)
      local scheme, token = parse_authorization(header)
      if not (scheme == "bearer") then
        return false
      end
      local grant = self.grants:find_by_access(sha256_hex(token))
      if not (grant) then
        return false
      end
      if not (grant.resource == self.config:resource_url(req)) then
        return false
      end
      return {
        grant = grant
      }
    end
  }
  _base_0.__index = _base_0
  _class_0 = setmetatable({
    __init = function(self, opts, config)
      self.opts, self.config = opts, config
      assert(self.opts.grants, "oauth.grants is required")
      local _list_0 = {
        "current_user",
        "login_url",
        "render_consent"
      }
      for _index_0 = 1, #_list_0 do
        local name = _list_0[_index_0]
        assert(type(self.opts[name]) == "function", "oauth." .. tostring(name) .. " must be a function")
      end
      if self.opts.grant_created ~= nil then
        assert(type(self.opts.grant_created) == "function", "oauth.grant_created must be a function")
      end
      self.grants = self.opts.grants
      self.access_token_ttl = self.opts.access_token_ttl or DEFAULT_ACCESS_TOKEN_TTL
      self.clients = ClientMetadata({
        trusted_hosts = self.opts.trusted_client_hosts,
        allow_any_host = self.opts.allow_any_client,
        cache = self.opts.cache,
        http = self.opts.http
      })
    end,
    __base = _base_0,
    __name = "SiteMode"
  }, {
    __index = _base_0,
    __call = function(cls, ...)
      local _self_0 = setmetatable({}, _base_0)
      cls.__init(_self_0, ...)
      return _self_0
    end
  })
  _base_0.__class = _class_0
  SiteMode = _class_0
end
return {
  SiteMode = SiteMode
}
