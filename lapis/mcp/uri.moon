-- URI template parsing utilities for MCP resources
-- Supports RFC 6570-style URI templates like app://games/{id}

-- Create LPEG patterns
import P, R, S, C, Ct, Cg, Cb, Cf, Cmt from require "lpeg"

param_name = R("az", "AZ", "09") + S("_-")
param = P"{" * C(param_name^1) * P"}"

literal_char = P(1) - param
literal = literal_char^1 / (str) ->
  P(str)

capture_param = Cmt param, (str, pos, capture_name) ->
  -- print "pos", pos
  -- print "got capture name", capture_name
  rest = str\sub pos

  value_char = P(1)

  -- don't terminate early for remaining
  if #rest > 0
    if exclude = C(literal_char^1)\match rest
      value_char = value_char - exclude

  true, Cg value_char^1, capture_name

part = literal + capture_param

join_patterns = (left, right) -> left * right

-- an lpeg pattern that parsed a template string to return a new lpeg pattern
-- that can be used to test if an arbitrary string matches the template,
-- returning any extracted parameters
parse_template = Cf(part * part^0, join_patterns) / Ct

-- pattern = assert parse_template\match "hello://world/{id}/zone/{age}"
-- 
-- print pattern\match("hello://world/123") --> nil
-- print pattern\match("hello://world/123/zone/99") --> {id = "123", age = "99"}

{:parse_template}

