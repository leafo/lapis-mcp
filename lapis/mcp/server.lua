local json = require("cjson")
local insert
insert = table.insert
local McpServer
do
  local _class_0
  local _base_0 = {
    setup_tools = function(self)
      self.tools = {
        routes = {
          description = "Lists all named routes in the Lapis application",
          parameters = { },
          handler = function(self, params)
            return self:list_routes()
          end
        },
        models = {
          description = "Lists all database models defined in the application",
          parameters = { },
          handler = function(self, params)
            return self:list_models()
          end
        },
        schema = {
          description = "Shows the schema for a specific database model",
          parameters = {
            model_name = {
              type = "string",
              description = "Name of the model to inspect",
              required = true
            }
          },
          handler = function(self, params)
            local schema, err = self:get_model_schema(params.model_name)
            if not schema then
              return {
                error = err
              }
            end
            return schema
          end
        }
      }
    end,
    read_json_chunk = function(self)
      local size_line = io.read("*line")
      if not (size_line) then
        return nil
      end
      local size = tonumber(size_line)
      if not (size) then
        return nil
      end
      local chunk = io.read(size)
      if not (chunk) then
        return nil
      end
      local delimiter = io.read(1)
      if not (delimiter == "\n") then
        return nil
      end
      return json.decode(chunk)
    end,
    write_json_chunk = function(self, obj)
      local data = json.encode(obj)
      io.write(#data .. "\n")
      io.write(data .. "\n")
      return io.flush()
    end,
    list_routes = function(self)
      local routes = { }
      if self.app and self.app.router and self.app.router.named_routes then
        for name, route in pairs(self.app.router.named_routes) do
          insert(routes, {
            name = name,
            path = route[1],
            method = route[2] or "GET"
          })
        end
      end
      return routes
    end,
    list_models = function(self)
      local models = { }
      local ok, db = pcall(require, "models")
      if ok and type(db) == "table" then
        for name, model in pairs(db) do
          if type(model) == "table" and model.__base then
            insert(models, name)
          end
        end
      end
      return models
    end,
    get_model_schema = function(self, model_name)
      local ok, db = pcall(require, "models")
      if not ok or type(db) ~= "table" or not db[model_name] then
        return nil, "Model not found: " .. tostring(model_name)
      end
      local model = db[model_name]
      local schema = { }
      if model.columns then
        for name, type in pairs(model.columns) do
          schema[name] = {
            type = type
          }
        end
      end
      if model.relations then
        schema._relations = model.relations
      end
      return schema
    end,
    handle_message = function(self, message)
      if message.type == "tool_call" then
        local tool_name = message.tool_call.name
        local params = message.tool_call.parameters
        if not (self.tools[tool_name]) then
          return {
            type = "tool_result",
            id = message.id,
            tool_result = {
              error = "Unknown tool: " .. tostring(tool_name)
            }
          }
        end
        local tool = self.tools[tool_name]
        for param_name, param_def in pairs(tool.parameters) do
          if param_def.required and not params[param_name] then
            return {
              type = "tool_result",
              id = message.id,
              tool_result = {
                error = "Missing required parameter: " .. tostring(param_name)
              }
            }
          end
        end
        local result = nil
        local ok, result_or_error = pcall(tool.handler, params)
        if not ok then
          return {
            type = "tool_result",
            id = message.id,
            tool_result = {
              error = "Error executing tool: " .. tostring(result_or_error)
            }
          }
        end
        return {
          type = "tool_result",
          id = message.id,
          tool_result = result_or_error
        }
      elseif message.type == "list_tools" then
        return self:get_tools_list()
      else
        return {
          type = "error",
          error = "Unsupported message type: " .. tostring(message.type)
        }
      end
    end,
    get_tools_list = function(self)
      local tools_list = { }
      for name, tool in pairs(self.tools) do
        insert(tools_list, {
          name = name,
          description = tool.description,
          parameters = tool.parameters
        })
      end
      return {
        type = "tools_list",
        tools = tools_list
      }
    end,
    get_server_info = function(self)
      return {
        type = "server_info",
        server = {
          name = "lapis-mcp",
          version = "0.1.0",
          vendor = "Lapis"
        }
      }
    end,
    run = function(self)
      self:write_json_chunk(self:get_server_info())
      while true do
        local message = self:read_json_chunk()
        if not (message) then
          break
        end
        local response = self:handle_message(message)
        self:write_json_chunk(response)
      end
    end
  }
  _base_0.__index = _base_0
  _class_0 = setmetatable({
    __init = function(self, app)
      self.app = app
      return self:setup_tools()
    end,
    __base = _base_0,
    __name = "McpServer"
  }, {
    __index = _base_0,
    __call = function(cls, ...)
      local _self_0 = setmetatable({}, _base_0)
      cls.__init(_self_0, ...)
      return _self_0
    end
  })
  _base_0.__class = _class_0
  McpServer = _class_0
end
local find_lapis_application
find_lapis_application = function(config)
  local app_module = "app"
  if config and config.app_module then
    app_module = config.app_module
  end
  local ok, app = pcall(require, app_module)
  if ok then
    return app
  end
  local lapis
  ok, lapis = pcall(require, "lapis")
  if ok then
    return lapis.Application()
  end
  return error("Could not find a Lapis application")
end
return {
  McpServer = McpServer,
  find_lapis_application = find_lapis_application
}
