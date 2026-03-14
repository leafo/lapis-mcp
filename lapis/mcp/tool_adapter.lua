local json = require("cjson")
local ToolAdapter
do
  local _class_0
  local _base_0 = {
    subclass_responsibility = function(self, method_name)
      return error("subclass responsibility: implement " .. tostring(method_name))
    end,
    normalized_schema = function(self, tool)
      local schema = {
        type = tool.inputSchema.type or "object",
        properties = tool.inputSchema.properties or { }
      }
      if type(tool.inputSchema.required) == "table" and #tool.inputSchema.required > 0 then
        schema.required = tool.inputSchema.required
      end
      return schema
    end,
    convert_tool = function(self, tool)
      return self:subclass_responsibility("convert_tool")
    end,
    to_tools = function(self)
      local _accum_0 = { }
      local _len_0 = 1
      local _list_0 = self.server:get_enabled_tools()
      for _index_0 = 1, #_list_0 do
        local tool = _list_0[_index_0]
        _accum_0[_len_0] = self:convert_tool(tool)
        _len_0 = _len_0 + 1
      end
      return _accum_0
    end,
    extract_tool_calls = function(self, message)
      return self:subclass_responsibility("extract_tool_calls")
    end,
    build_tool_result_message = function(self, tool_result)
      return self:subclass_responsibility("build_tool_result_message")
    end,
    build_tool_result_messages = function(self, tool_results)
      local _accum_0 = { }
      local _len_0 = 1
      for _index_0 = 1, #tool_results do
        local tool_result = tool_results[_index_0]
        _accum_0[_len_0] = self:build_tool_result_message(tool_result)
        _len_0 = _len_0 + 1
      end
      return _accum_0
    end,
    serialize_result = function(self, result)
      if type(result) == "string" then
        return result
      end
      return json.encode(result)
    end,
    serialize_error = function(self, err)
      return json.encode({
        error = tostring(err)
      })
    end,
    execute_tool_call = function(self, tool_call)
      if tool_call.error then
        return {
          tool_call = tool_call,
          content = self:serialize_error(tool_call.error),
          is_error = true
        }
      end
      local result, err = self.server:execute_tool(tool_call.name, tool_call.arguments or { })
      if err then
        return {
          tool_call = tool_call,
          content = self:serialize_error(err),
          is_error = true
        }
      end
      return {
        tool_call = tool_call,
        content = self:serialize_result(result),
        is_error = false
      }
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
      return self:build_tool_result_messages(tool_results)
    end
  }
  _base_0.__index = _base_0
  _class_0 = setmetatable({
    __init = function(self, mcp_server)
      if not (mcp_server) then
        error("ToolAdapter requires an MCP server instance")
      end
      self.server = mcp_server
    end,
    __base = _base_0,
    __name = "ToolAdapter"
  }, {
    __index = _base_0,
    __call = function(cls, ...)
      local _self_0 = setmetatable({}, _base_0)
      cls.__init(_self_0, ...)
      return _self_0
    end
  })
  _base_0.__class = _class_0
  ToolAdapter = _class_0
  return _class_0
end
