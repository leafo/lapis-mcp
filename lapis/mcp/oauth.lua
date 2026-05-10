local json = require("cjson.safe")
local respond_to
respond_to = require("lapis.application").respond_to
local encode_with_secret, decode_with_secret, decode_base64
do
  local _obj_0 = require("lapis.util.encoding")
  encode_with_secret, decode_with_secret, decode_base64 = _obj_0.encode_with_secret, _obj_0.decode_with_secret, _obj_0.decode_base64
end
local encode_query_string, unescape
do
  local _obj_0 = require("lapis.util")
  encode_query_string, unescape = _obj_0.encode_query_string, _obj_0.unescape
end
local base64url_no_pad
base64url_no_pad = function(s)
  local encoded = ngx.encode_base64(s)
  return (encoded:gsub("+", "-"):gsub("/", "_"):gsub("=", ""))
end
local verify_pkce
verify_pkce = function(verifier, challenge, method)
  if method == nil then
    method = "plain"
  end
  if not (verifier and challenge) then
    return false
  end
  local _exp_0 = method
  if "plain" == _exp_0 then
    return verifier == challenge
  elseif "S256" == _exp_0 then
    local digest = require("openssl.digest")
    local h = digest.new("sha256")
    h:update(verifier)
    return base64url_no_pad(h:final()) == challenge
  else
    return false
  end
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
      if not (header) then
        return false
      end
      local token = header:match("^[Bb]earer (.+)$")
      if not (token) then
        return false
      end
      return token == (self.opts.access_token or self.opts.client_secret)
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
              "S256",
              "plain"
            }, json.array_mt),
            token_endpoint_auth_methods_supported = setmetatable({
              "client_secret_post",
              "client_secret_basic"
            }, json.array_mt)
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
          if not (response_type == "code") then
            return {
              status = 400,
              json = {
                error = "unsupported_response_type"
              }
            }
          end
          if not (client_id == config.opts.client_id) then
            return {
              status = 400,
              json = {
                error = "invalid_client"
              }
            }
          end
          if not (redirect_uri) then
            return {
              status = 400,
              json = {
                error = "invalid_request",
                error_description = "missing redirect_uri"
              }
            }
          end
          local code = encode_with_secret({
            cid = client_id,
            ru = redirect_uri,
            cc = code_challenge,
            ccm = code_challenge_method,
            exp = os.time() + 600
          }, config.opts.client_secret)
          local qs_params = {
            code = code
          }
          if state then
            qs_params.state = state
          end
          local sep = redirect_uri:find("?", 1, true) and "&" or "?"
          return {
            redirect_to = redirect_uri .. sep .. encode_query_string(qs_params)
          }
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
          if auth_header then
            local basic_creds = auth_header:match("^[Bb]asic (.+)$")
            if basic_creds then
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
          end
          if not (client_id == config.opts.client_id and client_secret == config.opts.client_secret) then
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
            if code_data.cc then
              if not (verify_pkce(args.code_verifier, code_data.cc, code_data.ccm)) then
                return error_response(400, "invalid_grant", "PKCE verification failed")
              end
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
      return assert(self.opts.client_secret, "oauth.client_secret is required")
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
  OauthConfig = OauthConfig
}
