local json = require("cjson.safe")
local respond_to
respond_to = require("lapis.application").respond_to
local verify_bearer, is_s256_challenge, redirect_uri_allowed, redirect_to_client
do
  local _obj_0 = require("lapis.mcp.oauth.util")
  verify_bearer, is_s256_challenge, redirect_uri_allowed, redirect_to_client = _obj_0.verify_bearer, _obj_0.is_s256_challenge, _obj_0.redirect_uri_allowed, _obj_0.redirect_to_client
end
local StaticMode
StaticMode = require("lapis.mcp.oauth.static").StaticMode
local SiteMode
SiteMode = require("lapis.mcp.oauth.site").SiteMode
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
    authorize_url = function(self, req)
      return tostring(self:issuer_url(req)) .. "/oauth/authorize"
    end,
    verify_bearer_token = function(self, header, req)
      return self.mode:verify_bearer_token(header, req)
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
        local metadata = {
          issuer = issuer,
          authorization_endpoint = config:authorize_url(route.req),
          token_endpoint = tostring(issuer) .. "/oauth/token",
          response_types_supported = setmetatable({
            "code"
          }, json.array_mt),
          code_challenge_methods_supported = setmetatable({
            "S256"
          }, json.array_mt),
          authorization_response_iss_parameter_supported = true
        }
        for k, v in pairs(config.mode:server_metadata()) do
          metadata[k] = v
        end
        return {
          json = metadata,
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
        POST = function(route)
          if config.mode.consent_post then
            return config.mode:consent_post(route)
          else
            return {
              status = 405,
              json = {
                error = "method_not_allowed"
              }
            }
          end
        end,
        GET = function(route)
          local params = route.params
          local response_type = params.response_type
          local client_id = params.client_id
          local redirect_uri = params.redirect_uri
          local state = params.state
          local code_challenge = params.code_challenge
          local code_challenge_method = params.code_challenge_method or "plain"
          local client, err_response = config.mode:check_client(route, client_id)
          if not (client) then
            return err_response
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
          if client.redirect_uris then
            if not (redirect_uri_allowed(redirect_uri, client.redirect_uris)) then
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
          return config.mode:authorize(route, {
            client = client,
            client_id = client_id,
            redirect_uri = redirect_uri,
            state = state,
            code_challenge = code_challenge,
            resource = config:resource_url(route.req),
            requested_resource = params.resource,
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
          local token, status, code, description = config.mode:token_request(route)
          if not (token) then
            return error_response(status, code, description)
          end
          return {
            json = token,
            headers = merge(cors_headers, {
              ["Cache-Control"] = "no-store"
            })
          }
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
      if self.opts.grants then
        assert(not self.opts.client_secret, "oauth can't set both grants and client_secret")
        assert(not self.opts.allowed_redirect_uris, "oauth.allowed_redirect_uris doesn't apply with grants, redirect URIs come from each client's metadata document")
        self.mode = SiteMode(self.opts, self)
      else
        self.mode = StaticMode(self.opts)
      end
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
