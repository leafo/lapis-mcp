-- This generates a basic URI parser from a URI template string to extract parameters
-- from an incoming URL generate by the expansion string
--
-- NOTE: URI templates are a pattern for expansion, not for parsing, but we
-- implement a basic parser to make it easier to extract parameters from the
-- incoming URL when the resource request is incoming. Only a subset of the
-- spec is implemented
--
-- example: app://games/{id}{?fields}

-- Create LPEG patterns
import P, R, S, C, Ct, Cg, Cb, Cf, Cmt from require "lpeg"

whitespace = S" \t\n\r"

list = (p, delimiter=",") ->
  p * (whitespace^0 *P(delimiter) * whitespace^0 * p)^0

param_name_char = R("az", "AZ", "09") + S("_-")
param = P"{" * whitespace^0 * C(param_name_char^1) * whitespace^0 * P"}"

query_param = P"{?" * whitespace^0 * list(C(param_name_char^1)) * whitespace^0 * P"}"

literal_char = P(1) - (param + query_param)
literal = literal_char^1 / (str) ->
  P(str)

-- create a terminating pattern for what's in the rest of the pattern string to prevent values from over-capturing
-- NOTE: for every param type, we need to include the prefix from the exclude type
find_terminate = (rest) ->
  if not rest or #rest == 0
    return nil

  convert = C(literal_char^1) + query_param / "?"
  convert\match rest

capture_param = Cmt param, (str, pos, capture_name) ->
  -- print "pos", pos
  -- print "got capture name", capture_name
  rest = str\sub pos

  value_char = P(1)

  if exclude = find_terminate rest
    value_char = value_char - exclude

  true, Cg value_char^1, capture_name

-- {?one,two,three}
capture_query_param = Cmt Ct(query_param), (str, pos, query_names) ->
  util = require "lapis.util"

  match_pair = nil

  for name in *query_names
    value_char = P(1) - S"=&"
    match_value = value_char^0
    pair = Cg name * P("=") * (match_value / util.unescape), name

    match_pair = if match_pair
      match_pair + pair
    else
      pair

  match_query = P("?") * (match_pair * (P("&") * match_pair)^0)^-1
  true, match_query^-1 -- optional

part = literal + capture_query_param + capture_param

join_patterns = (left, right) -> left * right

-- an lpeg pattern that parsed a template string to return a new lpeg pattern
-- that can be used to test if an arbitrary string matches the template,
-- returning any extracted parameters
parse_template = Cf(part * part^0, join_patterns) / (p) -> Ct(p) * P(-1)

-- pattern = assert parse_template\match "hello://world/{id}/zone/{age}"
--
-- print pattern\match("hello://world/123") --> nil
-- print pattern\match("hello://world/123/zone/99") --> {id = "123", age = "99"}


{:parse_template}

