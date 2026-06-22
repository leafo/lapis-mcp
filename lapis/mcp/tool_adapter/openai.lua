local ToolAdapter = require("lapis.mcp.tool_adapter")
local json = require("cjson.safe")
local array
array = function(items)
  return setmetatable(items, json.array_mt)
end
local has_value
has_value = function(items, value)
  if not (type(items) == "table") then
    return false
  end
  for _index_0 = 1, #items do
    local item = items[_index_0]
    if item == value then
      return true
    end
  end
  return false
end
local copy_schema
copy_schema = function(schema)
  if not (type(schema) == "table") then
    return schema
  end
  local out = { }
  for key, value in pairs(schema) do
    out[key] = copy_schema(value)
  end
  if getmetatable(schema) == json.array_mt then
    setmetatable(out, json.array_mt)
  end
  return out
end
local make_nullable
make_nullable = function(schema)
  if not (type(schema) == "table") then
    return schema
  end
  if type(schema.type) == "string" then
    schema.type = array({
      schema.type,
      "null"
    })
  elseif type(schema.type) == "table" then
    if not (has_value(schema.type, "null")) then
      table.insert(schema.type, "null")
    end
  end
  if type(schema.enum) == "table" then
    if not (has_value(schema.enum, json.null)) then
      table.insert(schema.enum, json.null)
    end
  end
  return schema
end
local strict_schema_node
strict_schema_node = function(schema, nullable)
  if nullable == nil then
    nullable = false
  end
  if not (type(schema) == "table") then
    return schema
  end
  schema = copy_schema(schema)
  schema.default = nil
  local is_object = schema.type == "object"
  if type(schema.type) == "table" then
    is_object = has_value(schema.type, "object")
  end
  if is_object or schema.properties then
    if not (type(schema.properties) == "table") then
      schema.properties = { }
    end
    local original_required = { }
    if type(schema.required) == "table" then
      local _list_0 = schema.required
      for _index_0 = 1, #_list_0 do
        local key = _list_0[_index_0]
        original_required[key] = true
      end
    end
    local required = { }
    for key, property in pairs(schema.properties) do
      table.insert(required, key)
      local normalized_property = strict_schema_node(property)
      if original_required[key] then
        schema.properties[key] = normalized_property
      else
        schema.properties[key] = make_nullable(normalized_property)
      end
    end
    table.sort(required)
    schema.required = array(required)
    if not (schema.additionalProperties ~= nil) then
      schema.additionalProperties = false
    end
  end
  if schema.items then
    schema.items = strict_schema_node(schema.items)
  end
  if nullable then
    make_nullable(schema)
  end
  return schema
end
local OpenAIToolAdapter
do
  local _class_0
  local _parent_0 = ToolAdapter
  local _base_0 = {
    normalized_schema = function(self, tool)
      local schema = _class_0.__parent.__base.normalized_schema(self, tool)
      if self.options.strict then
        return strict_schema_node(schema)
      else
        return schema
      end
    end,
    convert_tool = function(self, tool)
      local function_def = {
        name = tool.name,
        description = tool.description,
        parameters = self:normalized_schema(tool)
      }
      if self.options.strict then
        function_def.strict = true
      end
      return {
        type = "function",
        ["function"] = function_def
      }
    end,
    extract_tool_calls = function(self, message)
      if not (message.tool_calls) then
        return { }
      end
      local tool_calls = { }
      local _list_0 = message.tool_calls
      for _index_0 = 1, #_list_0 do
        local tool_call = _list_0[_index_0]
        local func = tool_call["function"]
        local args = { }
        local decode_error = nil
        if func.arguments and func.arguments ~= "" then
          args, decode_error = json.decode(func.arguments)
          if not (args) then
            args = { }
          end
        end
        table.insert(tool_calls, {
          id = tool_call.id,
          name = func.name,
          arguments = args,
          error = (function()
            if decode_error then
              return "Failed to decode tool arguments as JSON: " .. tostring(decode_error)
            end
          end)()
        })
      end
      return tool_calls
    end,
    build_tool_result_message = function(self, tool_result)
      return {
        role = "tool",
        tool_call_id = tool_result.tool_call.id,
        content = tool_result.content
      }
    end
  }
  _base_0.__index = _base_0
  setmetatable(_base_0, _parent_0.__base)
  _class_0 = setmetatable({
    __init = function(self, ...)
      return _class_0.__parent.__init(self, ...)
    end,
    __base = _base_0,
    __name = "OpenAIToolAdapter",
    __parent = _parent_0
  }, {
    __index = function(cls, name)
      local val = rawget(_base_0, name)
      if val == nil then
        local parent = rawget(cls, "__parent")
        if parent then
          return parent[name]
        end
      else
        return val
      end
    end,
    __call = function(cls, ...)
      local _self_0 = setmetatable({}, _base_0)
      cls.__init(_self_0, ...)
      return _self_0
    end
  })
  _base_0.__class = _class_0
  if _parent_0.__inherited then
    _parent_0.__inherited(_parent_0, _class_0)
  end
  OpenAIToolAdapter = _class_0
  return _class_0
end
