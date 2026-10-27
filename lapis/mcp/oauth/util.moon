-- Helpers shared by the OAuth endpoints and every OAuth mode

import encode_base64 from require "lapis.util.encoding"
import encode_query_string from require "lapis.util"

base64url_no_pad = (s) ->
  encoded = encode_base64 s
  (encoded\gsub("+", "-")\gsub("/", "_")\gsub("=", ""))

-- doesn't exit early on the first mismatched byte, so timing doesn't reveal
-- how much of a secret matched (the length is not hidden)
secure_compare = (a, b) ->
  return false unless type(a) == "string" and type(b) == "string"
  return false unless #a == #b

  diff = 0
  for i=1,#a
    diff += 1 unless a\byte(i) == b\byte(i)

  diff == 0

-- splits an Authorization header into a lowercased scheme and its value, the
-- scheme is case insensitive (RFC 7235)
parse_authorization = (header) ->
  return nil unless type(header) == "string"
  scheme, value = header\match "^(%S+)%s+(.+)$"
  return nil unless scheme
  scheme\lower!, value

-- matches an Authorization header against an expected bearer token
verify_bearer = (header, expected) ->
  return false unless expected
  scheme, token = parse_authorization header
  return false unless scheme == "bearer"
  secure_compare token, expected

-- only S256 is supported, as required by OAuth 2.1 and the MCP spec
verify_pkce = (verifier, challenge) ->
  return false unless type(verifier) == "string" and type(challenge) == "string"
  digest = require "openssl.digest"
  h = digest.new "sha256"
  h\update verifier
  secure_compare base64url_no_pad(h\final!), challenge

-- an S256 challenge is a base64url encoded SHA-256 digest without padding
is_s256_challenge = (challenge) ->
  type(challenge) == "string" and #challenge == 43 and challenge\match("^[%w%-_]+$") != nil

-- loopback redirect URIs may use any port (RFC 8252 section 7.3)
LOOPBACK_HOSTS = {
  "localhost": true
  "127.0.0.1": true
  "[::1]": true
}

parse_redirect_uri = (uri) ->
  -- IPv6 literal hosts are bracketed, and contain colons
  scheme, host, port, rest = uri\match "^(%a[%w+.-]*)://(%[[^%]]+%]):?(%d*)(.*)$"
  unless scheme
    scheme, host, port, rest = uri\match "^(%a[%w+.-]*)://([^/:?#%[]+):?(%d*)(.*)$"

  return nil unless scheme
  scheme\lower!, host\lower!, port, rest

redirect_uri_allowed = (uri, allowed_uris) ->
  return false unless type(uri) == "string"

  for allowed in *allowed_uris
    return true if uri == allowed

  -- only http loopback URIs get the any port rule
  scheme, host, _, rest = parse_redirect_uri uri
  return false unless scheme == "http" and LOOPBACK_HOSTS[host]

  for allowed in *allowed_uris
    a_scheme, a_host, _, a_rest = parse_redirect_uri allowed
    return true if scheme == a_scheme and host == a_host and rest == a_rest

  false

-- appends response params to the client's redirect_uri
redirect_to_client = (redirect_uri, params) ->
  sep = redirect_uri\find("?", 1, true) and "&" or "?"
  {
    redirect_to: redirect_uri .. sep .. encode_query_string params
  }

{
  :secure_compare
  :parse_authorization
  :verify_bearer
  :verify_pkce
  :is_s256_challenge
  :redirect_uri_allowed
  :redirect_to_client
}
