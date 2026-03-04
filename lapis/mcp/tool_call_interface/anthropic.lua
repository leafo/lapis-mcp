local ToolCallInterface
ToolCallInterface = require("lapis.mcp.tool_call_interface").ToolCallInterface
local AnthropicToolCallInterface
do
  local _class_0
  local _parent_0 = ToolCallInterface
  local _base_0 = {
    convert_tool = function(self, tool)
      local anthropic_tool = {
        name = tool.name,
        description = tool.description,
        input_schema = {
          type = tool.inputSchema.type or "object",
          properties = tool.inputSchema.properties or { }
        }
      }
      if tool.inputSchema.required then
        if type(tool.inputSchema.required) == "table" and #tool.inputSchema.required > 0 then
          anthropic_tool.input_schema.required = tool.inputSchema.required
        end
      end
      return anthropic_tool
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
