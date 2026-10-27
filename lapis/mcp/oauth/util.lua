local encode_base64
encode_base64 = require("lapis.util.encoding").encode_base64
local encode_query_string
encode_query_string = require("lapis.util").encode_query_string
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
return {
  secure_compare = secure_compare,
  parse_authorization = parse_authorization,
  verify_bearer = verify_bearer,
  verify_pkce = verify_pkce,
  is_s256_challenge = is_s256_challenge,
  redirect_uri_allowed = redirect_uri_allowed,
  redirect_to_client = redirect_to_client
}
