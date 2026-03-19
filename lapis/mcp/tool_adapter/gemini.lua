local ToolAdapter = require("lapis.mcp.tool_adapter")
local json = require("cjson.safe")
local GEMINI_TYPE_NAMES = {
  string = "STRING",
  number = "NUMBER",
  integer = "INTEGER",
  boolean = "BOOLEAN",
  array = "ARRAY",
  object = "OBJECT",
  ["null"] = "NULL"
}
local GeminiToolAdapter
do
  local _class_0
  local _parent_0 = ToolAdapter
  local _base_0 = {
    normalize_schema_type = function(self, schema_type)
      if not (schema_type) then
        return nil
      end
      return GEMINI_TYPE_NAMES[schema_type] or schema_type
    end,
    normalize_schema_node = function(self, schema)
      if not (type(schema) == "table") then
        return nil
      end
      local normalized = { }
      for key, value in pairs(schema) do
        local _exp_0 = key
        if "type" == _exp_0 then
          normalized.type = self:normalize_schema_type(value)
        elseif "properties" == _exp_0 then
          if type(value) == "table" then
            local properties = { }
            for property_name, property_schema in pairs(value) do
              properties[property_name] = self:normalize_schema_node(property_schema)
            end
            normalized.properties = properties
          end
        elseif "items" == _exp_0 then
          if type(value) == "table" then
            normalized.items = self:normalize_schema_node(value)
          end
        elseif "anyOf" == _exp_0 then
          if type(value) == "table" then
            do
              local _accum_0 = { }
              local _len_0 = 1
              for _index_0 = 1, #value do
                local option_schema = value[_index_0]
                _accum_0[_len_0] = self:normalize_schema_node(option_schema)
                _len_0 = _len_0 + 1
              end
              normalized.anyOf = _accum_0
            end
          end
        elseif "required" == _exp_0 then
          if type(value) == "table" and #value > 0 then
            normalized.required = value
          end
        elseif "description" == _exp_0 or "enum" == _exp_0 or "format" == _exp_0 or "nullable" == _exp_0 or "title" == _exp_0 or "minimum" == _exp_0 or "maximum" == _exp_0 or "minItems" == _exp_0 or "maxItems" == _exp_0 or "minProperties" == _exp_0 or "maxProperties" == _exp_0 or "minLength" == _exp_0 or "maxLength" == _exp_0 or "pattern" == _exp_0 or "example" == _exp_0 or "propertyOrdering" == _exp_0 or "default" == _exp_0 then
          normalized[key] = value
        end
      end
      return normalized
    end,
    normalized_schema = function(self, tool)
      local input_schema = tool.inputSchema or tool
      local schema = self:normalize_schema_node(input_schema)
      if not (schema.type) then
        schema.type = self:normalize_schema_type("object")
      end
      if (input_schema.type == nil or input_schema.type == "object" or input_schema.properties) and not schema.properties then
        schema.properties = { }
      end
      return schema
    end,
    convert_tool = function(self, tool)
      return {
        name = tool.name,
        description = tool.description,
        parameters = self:normalized_schema(tool)
      }
    end,
    to_tools = function(self)
      local declarations
      do
        local _accum_0 = { }
        local _len_0 = 1
        local _list_0 = self.server:get_enabled_tools()
        for _index_0 = 1, #_list_0 do
          local tool = _list_0[_index_0]
          _accum_0[_len_0] = self:convert_tool(tool)
          _len_0 = _len_0 + 1
        end
        declarations = _accum_0
      end
      if #declarations == 0 then
        return setmetatable({ }, json.array_mt)
      end
      return setmetatable({
        {
          functionDeclarations = declarations
        }
      }, json.array_mt)
    end,
    extract_tool_calls = function(self, message)
      local candidates
      if type(message.candidates) == "table" then
        candidates = message.candidates
      else
        candidates = { }
      end
      local tool_calls = { }
      for _index_0 = 1, #candidates do
        local candidate = candidates[_index_0]
        local parts
        if type(candidate.content) == "table" and type(candidate.content.parts) == "table" then
          parts = candidate.content.parts
        else
          parts = { }
        end
        for _index_1 = 1, #parts do
          local _continue_0 = false
          repeat
            local part = parts[_index_1]
            if not (type(part.functionCall) == "table") then
              _continue_0 = true
              break
            end
            local function_call = part.functionCall
            local args
            if type(function_call.args) == "table" then
              args = function_call.args
            else
              args = { }
            end
            table.insert(tool_calls, {
              name = function_call.name,
              arguments = args,
              error = (function()
                if function_call.args ~= nil and type(function_call.args) ~= "table" then
                  return "Expected functionCall args to be an object"
                end
              end)()
            })
            _continue_0 = true
          until true
          if not _continue_0 then
            break
          end
        end
      end
      return tool_calls
    end,
    build_tool_result_message = function(self)
      return error("GeminiToolAdapter does not support individual tool result messages, use build_tool_result_messages instead")
    end,
    build_tool_result_messages = function(self)
      return error("GeminiToolAdapter requires process_tool_calls to build Gemini responses")
    end,
    process_tool_calls = function(self, message)
      local tool_calls = self:extract_tool_calls(message)
      if not (tool_calls) then
        return { }
      end
      local tool_results
      do
        local _accum_0 = { }
        local _len_0 = 1
        for _index_0 = 1, #tool_calls do
          local tool_call = tool_calls[_index_0]
          _accum_0[_len_0] = self:execute_tool_call(tool_call)
          _len_0 = _len_0 + 1
        end
        tool_results = _accum_0
      end
      if not (#tool_results > 0) then
        return { }
      end
      local model_contents = { }
      local candidates
      if type(message.candidates) == "table" then
        candidates = message.candidates
      else
        candidates = { }
      end
      for _index_0 = 1, #candidates do
        local _continue_0 = false
        repeat
          local candidate = candidates[_index_0]
          if not (type(candidate.content) == "table" and type(candidate.content.parts) == "table") then
            _continue_0 = true
            break
          end
          table.insert(model_contents, candidate.content)
          _continue_0 = true
        until true
        if not _continue_0 then
          break
        end
      end
      local response_parts = { }
      for _index_0 = 1, #tool_results do
        local tool_result = tool_results[_index_0]
        local payload = json.decode(tool_result.content) or tool_result.content
        local error_payload
        if type(payload) == "table" and payload.error ~= nil then
          error_payload = payload.error
        else
          error_payload = payload
        end
        local response
        if tool_result.is_error then
          response = {
            error = error_payload
          }
        else
          response = {
            result = payload
          }
        end
        table.insert(response_parts, {
          functionResponse = {
            name = tool_result.tool_call.name,
            response = response
          }
        })
      end
      local messages
      do
        local _accum_0 = { }
        local _len_0 = 1
        for _index_0 = 1, #model_contents do
          local content = model_contents[_index_0]
          _accum_0[_len_0] = content
          _len_0 = _len_0 + 1
        end
        messages = _accum_0
      end
      table.insert(messages, {
        role = "user",
        parts = response_parts
      })
      return messages
    end
  }
  _base_0.__index = _base_0
  setmetatable(_base_0, _parent_0.__base)
  _class_0 = setmetatable({
    __init = function(self, ...)
      return _class_0.__parent.__init(self, ...)
    end,
    __base = _base_0,
    __name = "GeminiToolAdapter",
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
  GeminiToolAdapter = _class_0
  return _class_0
end
