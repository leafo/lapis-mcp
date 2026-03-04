local json = require("cjson.safe")
local ToolCallInterface
do
  local _class_0
  local _base_0 = {
    get_available_tools = function(self)
      local all_tools = self.server:get_all_tools()
      local tools_array
      do
        local _accum_0 = { }
        local _len_0 = 1
        for name, tool in pairs(all_tools) do
          _accum_0[_len_0] = tool
          _len_0 = _len_0 + 1
        end
        tools_array = _accum_0
      end
      local _accum_0 = { }
      local _len_0 = 1
      for _index_0 = 1, #tools_array do
        local tool = tools_array[_index_0]
        if not tool.hidden then
          _accum_0[_len_0] = tool
          _len_0 = _len_0 + 1
        end
      end
      return _accum_0
    end,
    convert_tool = function(self, tool)
      return error("convert_tool is not implemented, use a provider subclass")
    end,
    to_tools = function(self)
      local _accum_0 = { }
      local _len_0 = 1
      local _list_0 = self:get_available_tools()
      for _index_0 = 1, #_list_0 do
        local tool = _list_0[_index_0]
        _accum_0[_len_0] = self:convert_tool(tool)
        _len_0 = _len_0 + 1
      end
      return _accum_0
    end,
    execute_tool_call = function(self, tool_name, arguments)
      if arguments == nil then
        arguments = { }
      end
      local tool = self.server:find_tool(tool_name)
      if not (tool) then
        return false, "Tool not found: " .. tostring(tool_name)
      end
      if tool.inputSchema.required then
        if type(tool.inputSchema.required) == "table" then
          local _list_0 = tool.inputSchema.required
          for _index_0 = 1, #_list_0 do
            local param_name = _list_0[_index_0]
            if not (arguments[param_name]) then
              return false, "Missing required parameter: " .. tostring(param_name)
            end
          end
        end
      end
      local ok, result, user_error = pcall(tool.handler, self.server, arguments)
      if not (ok) then
        return false, "Tool execution error: " .. tostring(result)
      end
      if user_error then
        return false, user_error
      end
      return true, result
    end,
    execute_tool_call_json = function(self, tool_name, arguments)
      if arguments == nil then
        arguments = { }
      end
      local success, result = self:execute_tool_call(tool_name, arguments)
      if not (success) then
        return false, result
      end
      if type(result) == "string" then
        return true, result
      end
      local json_result, err = json.encode(result)
      if not (json_result) then
        return false, "Failed to encode result as JSON: " .. tostring(err)
      end
      return true, json_result
    end
  }
  _base_0.__index = _base_0
  _class_0 = setmetatable({
    __init = function(self, mcp_server)
      if not (mcp_server) then
        error("ToolCallInterface requires an MCP server instance")
      end
      self.server = mcp_server
    end,
    __base = _base_0,
    __name = "ToolCallInterface"
  }, {
    __index = _base_0,
    __call = function(cls, ...)
      local _self_0 = setmetatable({}, _base_0)
      cls.__init(_self_0, ...)
      return _self_0
    end
  })
  _base_0.__class = _class_0
  ToolCallInterface = _class_0
end
return {
  ToolCallInterface = ToolCallInterface
}
