local P, R, S, C, Ct, Cg, Cb, Cf, Cmt
do
  local _obj_0 = require("lpeg")
  P, R, S, C, Ct, Cg, Cb, Cf, Cmt = _obj_0.P, _obj_0.R, _obj_0.S, _obj_0.C, _obj_0.Ct, _obj_0.Cg, _obj_0.Cb, _obj_0.Cf, _obj_0.Cmt
end
local param_name = R("az", "AZ", "09") + S("_-")
local param = P("{") * C(param_name ^ 1) * P("}")
local literal_char = P(1) - param
local literal = literal_char ^ 1 / function(str)
  return P(str)
end
local capture_param = Cmt(param, function(str, pos, capture_name)
  local rest = str:sub(pos)
  local value_char = P(1)
  if #rest > 0 then
    do
      local exclude = C(literal_char ^ 1):match(rest)
      if exclude then
        value_char = value_char - exclude
      end
    end
  end
  return true, Cg(value_char ^ 1, capture_name)
end)
local part = literal + capture_param
local join_patterns
join_patterns = function(left, right)
  return left * right
end
local parse_template = Cf(part * part ^ 0, join_patterns) / Ct
return {
  parse_template = parse_template
}
