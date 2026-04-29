local json = require("cjson.safe")
local respond_to
respond_to = require("lapis.application").respond_to
local encode_with_secret, decode_with_secret
do
  local _obj_0 = require("lapis.util.encoding")
  encode_with_secret, decode_with_secret = _obj_0.encode_with_secret, _obj_0.decode_with_secret
end
local encode_query_string
encode_query_string = require("lapis.util").encode_query_string
local build_base_url
build_base_url = function(req)
  local scheme = req.headers["x-forwarded-proto"] or (req.parsed_url and req.parsed_url.scheme) or "http"
  local host = req.headers["x-forwarded-host"] or req.headers["host"] or "localhost"
  return tostring(scheme) .. "://" .. tostring(host)
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
    local sha256 = require("resty.sha256")
    local h = sha256()
    h:update(verifier)
    return base64url_no_pad(h:final()) == challenge
  else
    return false
  end
end
local verify_bearer_token
verify_bearer_token = function(oauth, header)
  if not (header) then
    return false
  end
  local token = header:match("^[Bb]earer (.+)$")
  if not (token) then
    return false
  end
  local expected = oauth.access_token or oauth.client_secret
  return token == expected
end
local protected_resource_handler
protected_resource_handler = function(oauth)
  return function(self)
    local base = oauth.resource or build_base_url(self.req)
    local issuer = oauth.issuer or build_base_url(self.req)
    return {
      json = {
        resource = base,
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
end
local authorization_server_handler
authorization_server_handler = function(oauth)
  return function(self)
    local issuer = oauth.issuer or build_base_url(self.req)
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
          "client_secret_basic",
          "none"
        }, json.array_mt)
      },
      headers = {
        ["Cache-Control"] = "public, max-age=3600",
        ["Access-Control-Allow-Origin"] = "*"
      }
    }
  end
end
local authorize_handler
authorize_handler = function(oauth)
  return respond_to({
    GET = function(self)
      local params = self.params
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
      if not (client_id == oauth.client_id) then
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
      }, oauth.client_secret)
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
end
local token_handler
token_handler = function(oauth)
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
        access_token = oauth.access_token or oauth.client_secret,
        token_type = "Bearer",
        expires_in = oauth.access_token_ttl or 3600
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
    OPTIONS = function(self)
      return {
        status = 204,
        layout = false,
        headers = cors_headers
      }
    end,
    POST = function(self)
      local args = self.params
      local auth_header = self.req.headers["authorization"]
      local client_id = args.client_id
      local client_secret = args.client_secret
      if auth_header then
        local basic_creds = auth_header:match("^[Bb]asic (.+)$")
        if basic_creds then
          local decoded = ngx.decode_base64(basic_creds)
          if decoded then
            local cid, csec = decoded:match("^([^:]*):(.*)$")
            if cid then
              client_id = cid
            end
            if csec then
              client_secret = csec
            end
          end
        end
      end
      if not (client_id == oauth.client_id and client_secret == oauth.client_secret) then
        return error_response(401, "invalid_client")
      end
      local _exp_0 = args.grant_type
      if "authorization_code" == _exp_0 then
        local code_data, err = decode_with_secret(args.code or "", oauth.client_secret)
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
end
local register_routes
register_routes = function(app, oauth)
  assert(oauth.client_id, "oauth.client_id is required")
  assert(oauth.client_secret, "oauth.client_secret is required")
  app:match("/.well-known/oauth-protected-resource", protected_resource_handler(oauth))
  app:match("/.well-known/oauth-authorization-server", authorization_server_handler(oauth))
  app:match("/oauth/authorize", authorize_handler(oauth))
  return app:match("/oauth/token", token_handler(oauth))
end
return {
  register_routes = register_routes,
  verify_bearer_token = verify_bearer_token,
  verify_pkce = verify_pkce,
  build_base_url = build_base_url,
  protected_resource_handler = protected_resource_handler,
  authorization_server_handler = authorization_server_handler,
  authorize_handler = authorize_handler,
  token_handler = token_handler
}
