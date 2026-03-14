local ToolCallInterface
ToolCallInterface = require("lapis.mcp.tool_call_interface").ToolCallInterface
local AnthropicToolCallInterface
do
  local _class_0
  local _parent_0 = ToolCallInterface
  local _base_0 = {
    convert_tool = function(self, tool)
      return {
        name = tool.name,
        description = tool.description,
        input_schema = self:normalized_schema(tool)
      }
    end,
    extract_tool_calls = function(self, message)
      if not (type(message.content) == "table") then
        return { }
      end
      local tool_calls = { }
      local _list_0 = message.content
      for _index_0 = 1, #_list_0 do
        local _continue_0 = false
        repeat
          local block = _list_0[_index_0]
          if not (block.type == "tool_use") then
            _continue_0 = true
            break
          end
          table.insert(tool_calls, {
            id = block.id,
            name = block.name,
            arguments = (function()
              if type(block.input) == "table" then
                return block.input
              else
                return { }
              end
            end)(),
            error = (function()
              if block.input ~= nil and type(block.input) ~= "table" then
                return "Expected tool_use input to be an object"
              end
            end)()
          })
          _continue_0 = true
        until true
        if not _continue_0 then
          break
        end
      end
      return tool_calls
    end,
    build_tool_result_message = function(self)
      return error("AnthropicToolCallInterface does not support individual tool result messages, use build_tool_result_messages instead")
    end,
    build_tool_result_messages = function(self, tool_results)
      if not (#tool_results > 0) then
        return { }
      end
      local content = { }
      for _index_0 = 1, #tool_results do
        local tool_result = tool_results[_index_0]
        local block = {
          type = "tool_result",
          tool_use_id = tool_result.tool_call.id,
          content = tool_result.content
        }
        if tool_result.is_error then
          block.is_error = true
        end
        table.insert(content, block)
      end
      return {
        {
          role = "user",
          content = content
        }
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
    __name = "AnthropicToolCallInterface",
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
  AnthropicToolCallInterface = _class_0
end
return {
  AnthropicToolCallInterface = AnthropicToolCallInterface
}
