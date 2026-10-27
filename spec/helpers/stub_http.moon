json = require "cjson"

-- a lapis.http stand-in that serves canned responses by URL and records
-- requests. A response is {status, body, headers}, or {error: msg} to raise
class StubHttp
  new: (@responses={}) =>
    @requests = {}
    -- lapis.http.request is a plain function, not a method
    @request = (req) -> @handle req

  handle: (req) =>
    table.insert @requests, req
    res = @responses[req.url]
    error res.error if res and res.error
    return nil, "connection refused" unless res

    body = res.body
    body = json.encode body if type(body) == "table"
    if req.sink
      -- delivered in chunks, like a real response
      for i=1,#body,1024
        ok, err = req.sink body\sub i, i + 1023
        return nil, err unless ok
      req.sink nil

    1, res.status or 200, res.headers or {}

{ :StubHttp }
