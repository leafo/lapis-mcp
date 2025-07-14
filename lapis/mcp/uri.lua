local P, R, S, C, Ct, Cg, Cb, Cf, Cmt
do
  local _obj_0 = require("lpeg")
  P, R, S, C, Ct, Cg, Cb, Cf, Cmt = _obj_0.P, _obj_0.R, _obj_0.S, _obj_0.C, _obj_0.Ct, _obj_0.Cg, _obj_0.Cb, _obj_0.Cf, _obj_0.Cmt
end
local whitespace = S(" \t\n\r")
local list
list = function(p, delimiter)
  if delimiter == nil then
    delimiter = ","
  end
  return p * (whitespace ^ 0 * P(delimiter) * whitespace ^ 0 * p) ^ 0
end
local param_name_char = R("az", "AZ", "09") + S("_-")
local param = P("{") * whitespace ^ 0 * C(param_name_char ^ 1) * whitespace ^ 0 * P("}")
local query_param = P("{?") * whitespace ^ 0 * list(C(param_name_char ^ 1)) * whitespace ^ 0 * P("}")
local literal_char = P(1) - (param + query_param)
local literal = literal_char ^ 1 / function(str)
  return P(str)
end
local find_terminate
find_terminate = function(rest)
  if not rest or #rest == 0 then
    return nil
  end
  local convert = C(literal_char ^ 1) + query_param / "?"
  return convert:match(rest)
end
local capture_param = Cmt(param, function(str, pos, capture_name)
  local rest = str:sub(pos)
  local value_char = P(1) - P("/")
  do
    local exclude = find_terminate(rest)
    if exclude then
      value_char = value_char - exclude
    end
  end
  return true, Cg(value_char ^ 1, capture_name)
end)
local capture_query_param = Cmt(Ct(query_param), function(str, pos, query_names)
  local util = require("lapis.util")
  local match_pair = nil
  for _index_0 = 1, #query_names do
    local name = query_names[_index_0]
    local value_char = P(1) - S("=&")
    local match_value = value_char ^ 0
    local pair = Cg(name * P("=") * (match_value / util.unescape), name)
    if match_pair then
      match_pair = match_pair + pair
    else
      match_pair = pair
    end
  end
  local match_query = P("?") * (match_pair * (P("&") * match_pair) ^ 0) ^ -1
  return true, match_query ^ -1
end)
local part = literal + capture_query_param + capture_param
local join_patterns
join_patterns = function(left, right)
  return left * right
end
local parse_template = Cf(part * part ^ 0, join_patterns) / function(p)
  return Ct(p) * P(-1)
end
return {
  parse_template = parse_template
}
