local json = require("cjson.safe")
local parse_uri, is_loopback_uri
do
  local _obj_0 = require("lapis.mcp.oauth.util")
  parse_uri, is_loopback_uri = _obj_0.parse_uri, _obj_0.is_loopback_uri
end
local MAX_DOCUMENT_SIZE = 16 * 1024
local FAILURE_TTL = 60
local DEFAULT_TTL = 60 * 60
local MIN_TTL = 5 * 60
local MAX_TTL = 24 * 60 * 60
local CACHE_PREFIX = "lapis-mcp:client-metadata:"
local PRIVATE_SUFFIXES = {
  "localhost",
  "local",
  "internal",
  "home.arpa"
}
local parse_client_id
parse_client_id = function(client_id)
  if not (type(client_id) == "string") then
    return nil, "client_id must be a string"
  end
  if client_id:find("#", 1, true) then
    return nil, "client_id must not contain a fragment"
  end
  local host, path = client_id:match("^https://([^/?]+)(/[^?]*)$")
  if not (host) then
    return nil, "client_id must be an https URL with a path and no query"
  end
  if host:find("@", 1, true) then
    return nil, "client_id must not contain a username or password"
  end
  if host:find(":", 1, true) then
    return nil, "client_id must not contain a port"
  end
  if path == "/" then
    return nil, "client_id must have a path"
  end
  host = host:lower()
  if not (host:match("^[%w.-]+$") and not host:find("..", 1, true) and not host:match("^%.") and not host:match("%.$")) then
    return nil, "client_id must have a valid hostname"
  end
  if not (host:match("%.%a[%w-]*$")) then
    return nil, "client_id must use a public hostname"
  end
  for _index_0 = 1, #PRIVATE_SUFFIXES do
    local suffix = PRIVATE_SUFFIXES[_index_0]
    if host == suffix or host:sub(-#suffix - 1) == "." .. tostring(suffix) then
      return nil, "client_id must use a public hostname"
    end
  end
  if not (path:match("^[%w%-._~!$&'()*+,;=:@/%%]*$")) then
    return nil, "client_id must be a valid URL path"
  end
  if path:gsub("%%%x%x", ""):find("%", 1, true) then
    return nil, "client_id must be a valid URL path"
  end
  for segment in path:gmatch("[^/]+") do
    segment = segment:lower():gsub("%%2e", ".")
    if segment == "." or segment == ".." then
      return nil, "client_id must not contain dot segments"
    end
  end
  return host
end
local origin
origin = function(uri)
  local scheme, host, port = parse_uri(uri)
  if not (scheme) then
    return nil
  end
  if port ~= "" then
    port = ":" .. tostring(port)
  end
  return tostring(scheme) .. "://" .. tostring(host) .. tostring(port)
end
local validate_document
validate_document = function(doc, client_id, host)
  if not (type(doc) == "table") then
    return nil, "the document is not a JSON object"
  end
  if not (doc.client_id == client_id) then
    return nil, "the document's client_id doesn't match its URL"
  end
  local method = doc.token_endpoint_auth_method
  if method ~= nil and method ~= json.null then
    if not (method == "none") then
      return nil, "token_endpoint_auth_method must be none"
    end
  end
  local uris = doc.redirect_uris
  if not (type(uris) == "table" and #uris > 0) then
    return nil, "redirect_uris must be a non-empty array"
  end
  local client_origin = origin(client_id)
  for _index_0 = 1, #uris do
    local _continue_0 = false
    repeat
      local uri = uris[_index_0]
      if not (type(uri) == "string") then
        return nil, "redirect_uris must be strings"
      end
      if uri:find("#", 1, true) then
        return nil, "redirect_uris must not contain a fragment"
      end
      if is_loopback_uri(uri) then
        _continue_0 = true
        break
      end
      if not (origin(uri) == client_origin) then
        return nil, "redirect_uris must be loopback or on " .. tostring(client_origin) .. ", got " .. tostring(uri)
      end
      _continue_0 = true
    until true
    if not _continue_0 then
      break
    end
  end
  local client_name = doc.client_name
  if not (type(client_name) == "string" and client_name ~= "") then
    client_name = host
  end
  return {
    client_id = client_id,
    client_name = client_name,
    host = host,
    redirect_uris = (function()
      local _accum_0 = { }
      local _len_0 = 1
      for _index_0 = 1, #uris do
        local uri = uris[_index_0]
        _accum_0[_len_0] = uri
        _len_0 = _len_0 + 1
      end
      return _accum_0
    end)()
  }
end
local header_value
header_value = function(headers, name)
  if not (type(headers) == "table") then
    return nil
  end
  local values = { }
  for k, v in pairs(headers) do
    if type(k) == "string" and k:lower() == name then
      if type(v) == "table" then
        for _index_0 = 1, #v do
          local item = v[_index_0]
          table.insert(values, tostring(item))
        end
      else
        table.insert(values, tostring(v))
      end
    end
  end
  if not (next(values)) then
    return nil
  end
  return table.concat(values, ", ")
end
local max_age_ttl
max_age_ttl = function(headers)
  local cache_control = header_value(headers, "cache-control")
  if not (type(cache_control) == "string") then
    return DEFAULT_TTL
  end
  cache_control = cache_control:lower()
  if cache_control:find("no-store", 1, true) or cache_control:find("no-cache", 1, true) then
    return MIN_TTL
  end
  local max_age = tonumber(cache_control:match("max%-age=(%d+)"))
  if not (max_age) then
    return DEFAULT_TTL
  end
  return math.min(MAX_TTL, math.max(MIN_TTL, max_age))
end
local log_value
log_value = function(value)
  value = tostring(value)
  if #value > 200 then
    value = value:sub(1, 200) .. "..."
  end
  return (value:gsub("[%c\\]", function(c)
    return string.format("\\%03d", c:byte())
  end))
end
local log_rejection
log_rejection = function(client_id, err, description)
  if not (ngx and ngx.log) then
    return 
  end
  return ngx.log(ngx.WARN, "lapis-mcp: rejected client ", log_value(client_id), ": ", err, ": ", log_value(description))
end
local ClientMetadata
do
  local _class_0
  local _base_0 = {
    check = function(self, client_id)
      local host, description = parse_client_id(client_id)
      if not (host) then
        log_rejection(client_id, "invalid_client_id", description)
        return nil, "invalid_client_id", description
      end
      if not (self.allow_any_host or self.trusted_hosts[host]) then
        description = tostring(host) .. " is not a trusted client host"
        log_rejection(client_id, "untrusted_host", description)
        return nil, "untrusted_host", description
      end
      return host
    end,
    resolve = function(self, client_id)
      local host, err, description = self:check(client_id)
      if not (host) then
        return nil, err, description
      end
      do
        local cached = self:cache_get(client_id)
        if cached then
          do
            local client = cached.client
            if client then
              client.trusted = self.trusted_hosts[host] == true
              return client
            end
          end
          return nil, cached.error, cached.description
        end
      end
      local client, ttl
      client, err, description, ttl = self:fetch(client_id, host)
      if client then
        self:cache_set(client_id, {
          client = client
        }, ttl)
        client.trusted = self.trusted_hosts[host] == true
        return client
      end
      log_rejection(client_id, err, description)
      self:cache_set(client_id, {
        error = err,
        description = description
      }, FAILURE_TTL)
      return nil, err, description
    end,
    fetch = function(self, client_id, host)
      local ltn12 = require("ltn12")
      local http = self.http or require("lapis.http")
      local chunks = { }
      local size = 0
      local too_large = false
      local sink
      sink = function(chunk, err)
        if not (chunk) then
          return true
        end
        size = size + #chunk
        if size > MAX_DOCUMENT_SIZE then
          too_large = true
          return nil, "document too large"
        end
        table.insert(chunks, chunk)
        return true
      end
      local ok, res, status, headers = pcall(http.request, {
        url = client_id,
        method = "GET",
        headers = {
          Accept = "application/json"
        },
        sink = sink,
        redirect = false
      })
      if too_large then
        return nil, "fetch_failed", "the document is larger than " .. tostring(MAX_DOCUMENT_SIZE) .. " bytes"
      end
      if not (ok) then
        return nil, "fetch_failed", "request failed: " .. tostring(res)
      end
      if not (res) then
        return nil, "fetch_failed", "request failed: " .. tostring(status)
      end
      if not (status == 200) then
        return nil, "fetch_failed", "expected status 200, got " .. tostring(status)
      end
      local doc = json.decode(table.concat(chunks))
      local client, description = validate_document(doc, client_id, host)
      if not (client) then
        return nil, "invalid_document", description
      end
      return client, nil, nil, max_age_ttl(headers)
    end,
    cache_get = function(self, client_id)
      if not (self.cache) then
        return nil
      end
      local value = self.cache:get(CACHE_PREFIX .. client_id)
      return value and json.decode(value)
    end,
    cache_set = function(self, client_id, value, ttl)
      if not (self.cache) then
        return 
      end
      return self.cache:set(CACHE_PREFIX .. client_id, json.encode(value), ttl)
    end
  }
  _base_0.__index = _base_0
  _class_0 = setmetatable({
    __init = function(self, opts)
      if opts == nil then
        opts = { }
      end
      self.allow_any_host = opts.allow_any_host == true
      local hosts = opts.trusted_hosts or { }
      if not (self.allow_any_host) then
        assert(type(hosts) == "table" and #hosts > 0, "trusted_hosts must be a non-empty array of hostnames unless allow_any_host is set")
      end
      self.trusted_hosts = { }
      for _index_0 = 1, #hosts do
        local host = hosts[_index_0]
        assert(type(host) == "string", "trusted_hosts must be an array of hostnames")
        self.trusted_hosts[host:lower()] = true
      end
      self.cache = opts.cache
      self.http = opts.http
    end,
    __base = _base_0,
    __name = "ClientMetadata"
  }, {
    __index = _base_0,
    __call = function(cls, ...)
      local _self_0 = setmetatable({}, _base_0)
      cls.__init(_self_0, ...)
      return _self_0
    end
  })
  _base_0.__class = _class_0
  ClientMetadata = _class_0
end
return {
  ClientMetadata = ClientMetadata,
  parse_client_id = parse_client_id
}
