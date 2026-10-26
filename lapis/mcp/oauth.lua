local json = require("cjson.safe")
local respond_to
respond_to = require("lapis.application").respond_to
local encode_base64, encode_with_secret, decode_with_secret, decode_base64
do
  local _obj_0 = require("lapis.util.encoding")
  encode_base64, encode_with_secret, decode_with_secret, decode_base64 = _obj_0.encode_base64, _obj_0.encode_with_secret, _obj_0.decode_with_secret, _obj_0.decode_base64
end
local encode_query_string, unescape
do
  local _obj_0 = require("lapis.util")
  encode_query_string, unescape = _obj_0.encode_query_string, _obj_0.unescape
end
local base64url_no_pad
base64url_no_pad = function(s)
  local encoded = encode_base64(s)
  return (encoded:gsub("+", "-"):gsub("/", "_"):gsub("=", ""))
end
local secure_compare
secure_compare = function(a, b)
  if not (type(a) == "string" and type(b) == "string") then
    return false
  end
  if not (#a == #b) then
    return false
  end
  local diff = 0
  for i = 1, #a do
    if not (a:byte(i) == b:byte(i)) then
      diff = diff + 1
    end
  end
  return diff == 0
end
local parse_authorization
parse_authorization = function(header)
  if not (type(header) == "string") then
    return nil
  end
  local scheme, value = header:match("^(%S+)%s+(.+)$")
  if not (scheme) then
    return nil
  end
  return scheme:lower(), value
end
local verify_bearer
verify_bearer = function(header, expected)
  if not (expected) then
    return false
  end
  local scheme, token = parse_authorization(header)
  if not (scheme == "bearer") then
    return false
  end
  return secure_compare(token, expected)
end
local verify_pkce
verify_pkce = function(verifier, challenge)
  if not (type(verifier) == "string" and type(challenge) == "string") then
    return false
  end
  local digest = require("openssl.digest")
  local h = digest.new("sha256")
  h:update(verifier)
  return secure_compare(base64url_no_pad(h:final()), challenge)
end
local is_s256_challenge
is_s256_challenge = function(challenge)
  return type(challenge) == "string" and #challenge == 43 and challenge:match("^[%w%-_]+$") ~= nil
end
local LOOPBACK_HOSTS = {
  ["localhost"] = true,
  ["127.0.0.1"] = true,
  ["[::1]"] = true
}
local parse_redirect_uri
parse_redirect_uri = function(uri)
  local scheme, host, port, rest = uri:match("^(%a[%w+.-]*)://(%[[^%]]+%]):?(%d*)(.*)$")
  if not (scheme) then
    scheme, host, port, rest = uri:match("^(%a[%w+.-]*)://([^/:?#%[]+):?(%d*)(.*)$")
  end
  if not (scheme) then
    return nil
  end
  return scheme:lower(), host:lower(), port, rest
end
local redirect_uri_allowed
redirect_uri_allowed = function(uri, allowed_uris)
  if not (type(uri) == "string") then
    return false
  end
  for _index_0 = 1, #allowed_uris do
    local allowed = allowed_uris[_index_0]
    if uri == allowed then
      return true
    end
  end
  local scheme, host, _, rest = parse_redirect_uri(uri)
  if not (scheme == "http" and LOOPBACK_HOSTS[host]) then
    return false
  end
  for _index_0 = 1, #allowed_uris do
    local allowed = allowed_uris[_index_0]
    local a_scheme, a_host, a_rest
    a_scheme, a_host, _, a_rest = parse_redirect_uri(allowed)
    if scheme == a_scheme and host == a_host and rest == a_rest then
      return true
    end
  end
  return false
end
local redirect_to_client
redirect_to_client = function(redirect_uri, params)
  local sep = redirect_uri:find("?", 1, true) and "&" or "?"
  return {
    redirect_to = redirect_uri .. sep .. encode_query_string(params)
  }
end
local decode_basic_part
decode_basic_part = function(part)
  return unescape(part:gsub("%+", " "))
end
local OauthConfig
do
  local _class_0
  local _base_0 = {
    public_base_url = function(self, req)
      local scheme = req.headers["x-forwarded-proto"] or (req.parsed_url and req.parsed_url.scheme) or "http"
      local host = req.headers["x-forwarded-host"] or req.headers["host"] or "localhost"
      local base = self.opts.public_base_url or tostring(scheme) .. "://" .. tostring(host)
      if self.opts.public_base_url then
        base = base:gsub("/+$", "")
      end
      return base
    end,
    mount_path_segment = function(self)
      if not (self.mount_path) then
        return ""
      end
      if self.mount_path == "" or self.mount_path == "/" then
        return ""
      end
      return self.mount_path
    end,
    resource_url = function(self, req)
      return self.opts.resource or self:public_base_url(req) .. self:mount_path_segment()
    end,
    protected_resource_metadata_url = function(self, req)
      return tostring(self:public_base_url(req)) .. "/.well-known/oauth-protected-resource" .. tostring(self:mount_path_segment())
    end,
    issuer_url = function(self, req)
      if self.opts.issuer then
        return self.opts.issuer
      end
      local base = self:public_base_url(req)
      local segment = self:mount_path_segment()
      if segment == "" then
        return base
      end
      return tostring(base) .. tostring(segment)
    end,
    verify_bearer_token = function(self, header)
      return verify_bearer(header, self.opts.access_token or self.opts.client_secret)
    end,
    protected_resource_handler = function(self)
      local config = self
      return function(route)
        local issuer = config:issuer_url(route.req)
        return {
          json = {
            resource = config:resource_url(route.req),
            authorization_servers = setmetatable({
              issuer
            }, json.array_mt),
            bearer_methods_supported = setmetatable({
              "header"
            }, json.array_mt)
          },
          headers = {
            ["Cache-Control"] = "public, max-age=3600",
            ["Access-Control-Allow-Origin"] = "*"
          }
        }
      end
    end,
    authorization_server_handler = function(self)
      local config = self
      return function(route)
        local issuer = config:issuer_url(route.req)
        return {
          json = {
            issuer = issuer,
            authorization_endpoint = tostring(issuer) .. "/oauth/authorize",
            token_endpoint = tostring(issuer) .. "/oauth/token",
            response_types_supported = setmetatable({
              "code"
            }, json.array_mt),
            grant_types_supported = setmetatable({
              "authorization_code",
              "client_credentials"
            }, json.array_mt),
            code_challenge_methods_supported = setmetatable({
              "S256"
            }, json.array_mt),
            token_endpoint_auth_methods_supported = setmetatable({
              "client_secret_post",
              "client_secret_basic"
            }, json.array_mt),
            authorization_response_iss_parameter_supported = true
          },
          headers = {
            ["Cache-Control"] = "public, max-age=3600",
            ["Access-Control-Allow-Origin"] = "*"
          }
        }
      end
    end,
    authorize_handler = function(self)
      local config = self
      return respond_to({
        GET = function(route)
          local params = route.params
          local response_type = params.response_type
          local client_id = params.client_id
          local redirect_uri = params.redirect_uri
          local state = params.state
          local code_challenge = params.code_challenge
          local code_challenge_method = params.code_challenge_method or "plain"
          if not (client_id == config.opts.client_id) then
            return {
              status = 400,
              json = {
                error = "invalid_client"
              }
            }
          end
          if not (type(redirect_uri) == "string") then
            return {
              status = 400,
              json = {
                error = "invalid_request",
                error_description = "missing redirect_uri"
              }
            }
          end
          if redirect_uri:find("#", 1, true) then
            return {
              status = 400,
              json = {
                error = "invalid_request",
                error_description = "redirect_uri must not contain a fragment"
              }
            }
          end
          if config.opts.allowed_redirect_uris then
            if not (redirect_uri_allowed(redirect_uri, config.opts.allowed_redirect_uris)) then
              return {
                status = 400,
                json = {
                  error = "invalid_request",
                  error_description = "redirect_uri not allowed"
                }
              }
            end
          end
          local iss = config:issuer_url(route.req)
          local redirect_error
          redirect_error = function(error_code, description)
            return redirect_to_client(redirect_uri, {
              error = error_code,
              error_description = description,
              state = state,
              iss = iss
            })
          end
          if not (response_type == "code") then
            return redirect_error("unsupported_response_type", "response_type must be code")
          end
          if not (code_challenge and code_challenge ~= "") then
            return redirect_error("invalid_request", "PKCE code_challenge is required")
          end
          if not (code_challenge_method == "S256") then
            return redirect_error("invalid_request", "code_challenge_method must be S256")
          end
          if not (is_s256_challenge(code_challenge)) then
            return redirect_error("invalid_request", "code_challenge is not a valid S256 challenge")
          end
          local code = encode_with_secret({
            cid = client_id,
            ru = redirect_uri,
            cc = code_challenge,
            exp = os.time() + 600
          }, config.opts.client_secret)
          return redirect_to_client(redirect_uri, {
            code = code,
            state = state,
            iss = iss
          })
        end
      })
    end,
    token_handler = function(self)
      local config = self
      local cors_headers = {
        ["Access-Control-Allow-Origin"] = "*",
        ["Access-Control-Allow-Methods"] = "POST, OPTIONS",
        ["Access-Control-Allow-Headers"] = "Content-Type, Authorization"
      }
      local merge
      merge = function(base, extra)
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
      local issue_token
      issue_token = function()
        return {
          json = {
            access_token = config.opts.access_token or config.opts.client_secret,
            token_type = "Bearer",
            expires_in = config.opts.access_token_ttl or 3600
          },
          headers = merge(cors_headers, {
            ["Cache-Control"] = "no-store"
          })
        }
      end
      local error_response
      error_response = function(status, code, description)
        local body = {
          error = code
        }
        if description then
          body.error_description = description
        end
        return {
          status = status,
          json = body,
          headers = cors_headers
        }
      end
      return respond_to({
        on_invalid_method = function(route)
          return {
            status = 405,
            layout = false,
            headers = cors_headers
          }
        end,
        OPTIONS = function(route)
          return {
            status = 204,
            layout = false,
            headers = cors_headers
          }
        end,
        POST = function(route)
          local args = route.params
          local auth_header = route.req.headers["authorization"]
          local client_id = args.client_id
          local client_secret = args.client_secret
          local scheme, basic_creds = parse_authorization(auth_header)
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
          if not (client_id == config.opts.client_id and secure_compare(client_secret, config.opts.client_secret)) then
            return error_response(401, "invalid_client")
          end
          local _exp_0 = args.grant_type
          if "authorization_code" == _exp_0 then
            local code_data, err = decode_with_secret(args.code or "", config.opts.client_secret)
            if not (code_data) then
              return error_response(400, "invalid_grant", err)
            end
            if code_data.exp and code_data.exp < os.time() then
              return error_response(400, "invalid_grant", "code expired")
            end
            if not (code_data.cid == client_id) then
              return error_response(400, "invalid_grant", "client_id mismatch")
            end
            if not (code_data.ru == args.redirect_uri) then
              return error_response(400, "invalid_grant", "redirect_uri mismatch")
            end
            if not (verify_pkce(args.code_verifier, code_data.cc)) then
              return error_response(400, "invalid_grant", "PKCE verification failed")
            end
            return issue_token()
          elseif "client_credentials" == _exp_0 then
            return issue_token()
          else
            return error_response(400, "unsupported_grant_type")
          end
        end
      })
    end,
    routes = function(self)
      local segment = self:mount_path_segment()
      local authorize_path
      if self.mount_path == "/" then
        authorize_path = "/oauth/authorize"
      else
        authorize_path = tostring(self.mount_path) .. "/oauth/authorize"
      end
      local token_path
      if self.mount_path == "/" then
        token_path = "/oauth/token"
      else
        token_path = tostring(self.mount_path) .. "/oauth/token"
      end
      return {
        {
          path = "/.well-known/oauth-protected-resource" .. tostring(segment),
          handler = self:protected_resource_handler()
        },
        {
          path = "/.well-known/oauth-authorization-server" .. tostring(segment),
          handler = self:authorization_server_handler()
        },
        {
          path = authorize_path,
          handler = self:authorize_handler()
        },
        {
          path = token_path,
          handler = self:token_handler()
        }
      }
    end
  }
  _base_0.__index = _base_0
  _class_0 = setmetatable({
    __init = function(self, opts, mount_path)
      if mount_path == nil then
        mount_path = "/"
      end
      self.opts, self.mount_path = opts, mount_path
      assert(self.opts.client_id, "oauth.client_id is required")
      assert(self.opts.client_secret, "oauth.client_secret is required")
      do
        local uris = self.opts.allowed_redirect_uris
        if uris then
          assert(type(uris) == "table", "oauth.allowed_redirect_uris must be an array of strings")
          for _index_0 = 1, #uris do
            local uri = uris[_index_0]
            assert(type(uri) == "string", "oauth.allowed_redirect_uris must be an array of strings")
          end
        end
      end
    end,
    __base = _base_0,
    __name = "OauthConfig"
  }, {
    __index = _base_0,
    __call = function(cls, ...)
      local _self_0 = setmetatable({}, _base_0)
      cls.__init(_self_0, ...)
      return _self_0
    end
  })
  _base_0.__class = _class_0
  OauthConfig = _class_0
end
return {
  OauthConfig = OauthConfig,
  verify_bearer = verify_bearer,
  redirect_uri_allowed = redirect_uri_allowed
}
