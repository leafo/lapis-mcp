local ToolCallInterface
ToolCallInterface = require("lapis.mcp.tool_call_interface").ToolCallInterface
local json = require("cjson.safe")
local OpenAIToolCallInterface
do
  local _class_0
  local _parent_0 = ToolCallInterface
  local _base_0 = {
    convert_tool = function(self, tool)
      return {
        type = "function",
        ["function"] = {
          name = tool.name,
          description = tool.description,
          parameters = self:normalized_schema(tool)
        }
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
    __name = "OpenAIToolCallInterface",
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
  OpenAIToolCallInterface = _class_0
end
return {
  OpenAIToolCallInterface = OpenAIToolCallInterface
}
