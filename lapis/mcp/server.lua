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
          name = "routes",
          title = "List Routes",
          description = "Lists all named routes in the Lapis application",
          inputSchema = {
            type = "object",
            properties = { },
            required = { }
          },
          handler = function(self, params)
            return self:list_routes()
          end
        },
        models = {
          name = "models",
          title = "List Models",
          description = "Lists all database models defined in the application",
          inputSchema = {
            type = "object",
            properties = { },
            required = { }
          },
          handler = function(self, params)
            return self:list_models()
          end
        },
        schema = {
          name = "schema",
          title = "Get Model Schema",
          description = "Shows the schema for a specific database model",
          inputSchema = {
            type = "object",
            properties = {
              model_name = {
                type = "string",
                description = "Name of the model to inspect"
              }
            },
            required = {
              "model_name"
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
      assert(self.app, "Missing app class")
      local router = self.app().router
      router:build()
      local tuples
      do
        local _accum_0 = { }
        local _len_0 = 1
        for k, v in pairs(router.named_routes) do
          _accum_0[_len_0] = {
            k,
            v
          }
          _len_0 = _len_0 + 1
        end
        tuples = _accum_0
      end
      table.sort(tuples, function(a, b)
        return a[1] < b[1]
      end)
      return tuples
    end,
    list_models = function(self)
      local models = { }
      error("not implemented yet")
      return models
    end,
    get_model_schema = function(self, model_name)
      local ok, db = pcall(require, "models")
      if not ok or type(db) ~= "table" or not db[model_name] then
        return nil, "Model not found: " .. tostring(model_name)
      end
      local model = db[model_name]
      error("TODO")
      return { }
    end,
    handle_message = function(self, message)
      if message.method == "initialize" then
        return self:handle_initialize(message)
      elseif message.method == "tools/call" then
        if not (self.initialized) then
          return {
            jsonrpc = "2.0",
            id = message.id,
            error = {
              code = -32002,
              message = "Server not initialized. Call initialize first."
            }
          }
        end
        local tool_name = message.params.name
        local params = message.params.arguments or { }
        if not (self.tools[tool_name]) then
          return {
            jsonrpc = "2.0",
            id = message.id,
            result = {
              content = {
                {
                  type = "text",
                  text = "Unknown tool: " .. tostring(tool_name)
                }
              },
              isError = true
            }
          }
        end
        local tool = self.tools[tool_name]
        local _list_0 = tool.inputSchema.required
        for _index_0 = 1, #_list_0 do
          local param_name = _list_0[_index_0]
          if not params[param_name] then
            return {
              jsonrpc = "2.0",
              id = message.id,
              result = {
                content = {
                  {
                    type = "text",
                    text = "Missing required parameter: " .. tostring(param_name)
                  }
                },
                isError = true
              }
            }
          end
        end
        local ok, result_or_error = pcall(tool.handler, self, params)
        if not ok then
          return {
            jsonrpc = "2.0",
            id = message.id,
            result = {
              content = {
                {
                  type = "text",
                  text = "Error executing tool: " .. tostring(result_or_error)
                }
              },
              isError = true
            }
          }
        end
        if result_or_error.error then
          return {
            jsonrpc = "2.0",
            id = message.id,
            result = {
              content = {
                {
                  type = "text",
                  text = result_or_error.error
                }
              },
              isError = true
            }
          }
        end
        return {
          jsonrpc = "2.0",
          id = message.id,
          result = {
            content = {
              {
                type = "text",
                text = json.encode(result_or_error)
              }
            },
            isError = false
          }
        }
      elseif message.method == "tools/list" then
        return self:get_tools_list()
      else
        return {
          jsonrpc = "2.0",
          id = message.id,
          error = {
            code = -32601,
            message = "Method not found: " .. tostring(message.method)
          }
        }
      end
    end,
    handle_initialize = function(self, message)
      local params = message.params or { }
      local client_info = params.clientInfo or { }
      local client_capabilities = params.capabilities or { }
      local requested_version = params.protocolVersion or "2025-06-18"
      self.client_capabilities = client_capabilities
      if requested_version ~= self.protocol_version then
        return {
          jsonrpc = "2.0",
          id = message.id,
          error = {
            code = -32602,
            message = "Protocol version mismatch. Server supports: " .. tostring(self.protocol_version) .. ", client requested: " .. tostring(requested_version)
          }
        }
      end
      self.server_capabilities.tools = { }
      for name, tool in pairs(self.tools) do
        self.server_capabilities.tools[name] = true
      end
      self.initialized = true
      return {
        jsonrpc = "2.0",
        id = message.id,
        result = {
          protocolVersion = self.protocol_version,
          capabilities = self.server_capabilities,
          serverInfo = {
            name = "lapis-mcp",
            version = "0.1.0",
            vendor = "Lapis"
          }
        }
      }
    end,
    get_tools_list = function(self)
      if not (self.initialized) then
        return {
          jsonrpc = "2.0",
          error = {
            code = -32002,
            message = "Server not initialized. Call initialize first."
          }
        }
      end
      local tools_list = { }
      for name, tool in pairs(self.tools) do
        insert(tools_list, {
          name = tool.name,
          title = tool.title,
          description = tool.description,
          inputSchema = tool.inputSchema
        })
      end
      return {
        jsonrpc = "2.0",
        result = {
          tools = tools_list
        }
      }
    end,
    send_message = function(self, message)
      local response = self:handle_message(message)
      return response
    end,
    run = function(self)
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
      self:setup_tools()
      self.protocol_version = "2025-06-18"
      self.server_capabilities = {
        tools = { }
      }
      self.client_capabilities = { }
      self.initialized = false
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
