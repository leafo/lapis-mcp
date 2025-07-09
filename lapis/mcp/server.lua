local json = require("cjson.safe")
local colors = require("ansicolors")
local insert
insert = table.insert
local StdioTransport
do
  local _class_0
  local _base_0 = {
    read_json_chunk = function(self)
      local chunk = io.read("*l")
      if not (chunk) then
        return false
      end
      local message = json.decode(chunk)
      if not (message) then
        return nil, "Failed to decode JSON chunk"
      end
      return message
    end,
    write_json_chunk = function(self, obj)
      local data = assert(json.encode(obj))
      io.write(data .. "\n")
      return io.flush()
    end
  }
  _base_0.__index = _base_0
  _class_0 = setmetatable({
    __init = function() end,
    __base = _base_0,
    __name = "StdioTransport"
  }, {
    __index = _base_0,
    __call = function(cls, ...)
      local _self_0 = setmetatable({}, _base_0)
      cls.__init(_self_0, ...)
      return _self_0
    end
  })
  _base_0.__class = _class_0
  StdioTransport = _class_0
end
local StdioTransportWithDebugLog
do
  local _class_0
  local _base_0 = {
    read_json_chunk = function(self)
      local chunk = io.read("*l")
      if not (chunk) then
        return false
      end
      self.file_log:write("READ: " .. chunk .. "\n")
      self.file_log:flush()
      local message = json.decode(chunk)
      if not (message) then
        return nil, "Failed to decode JSON chunk"
      end
      return message
    end,
    write_json_chunk = function(self, obj)
      local data = assert(json.encode(obj))
      self.file_log:write("WRITE: " .. data .. "\n")
      self.file_log:flush()
      io.write(data .. "\n")
      return io.flush()
    end
  }
  _base_0.__index = _base_0
  _class_0 = setmetatable({
    __init = function(self)
      self.file_log = io.open("/tmp/lapis-mcp.log", "a")
      return self.file_log:write("START SESSION: " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n")
    end,
    __base = _base_0,
    __name = "StdioTransportWithDebugLog"
  }, {
    __index = _base_0,
    __call = function(cls, ...)
      local _self_0 = setmetatable({}, _base_0)
      cls.__init(_self_0, ...)
      return _self_0
    end
  })
  _base_0.__class = _class_0
  StdioTransportWithDebugLog = _class_0
end
local StreamableHttpTransport
do
  local _class_0
  local _base_0 = {
    read_json_chunk = function(self)
      return error("TODO")
    end,
    write_json_chunk = function(self)
      return error("TODO")
    end
  }
  _base_0.__index = _base_0
  _class_0 = setmetatable({
    __init = function() end,
    __base = _base_0,
    __name = "StreamableHttpTransport"
  }, {
    __index = _base_0,
    __call = function(cls, ...)
      local _self_0 = setmetatable({}, _base_0)
      cls.__init(_self_0, ...)
      return _self_0
    end
  })
  _base_0.__class = _class_0
  StreamableHttpTransport = _class_0
end
local with_initialized
with_initialized = function(fn)
  return function(self, message)
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
    return fn(self, message)
  end
end
local McpServer
do
  local _class_0
  local _base_0 = {
    debug_log = function(self, level, message)
      if not (self.debug) then
        return 
      end
      local color
      local _exp_0 = level
      if "info" == _exp_0 then
        color = "%{cyan}"
      elseif "success" == _exp_0 then
        color = "%{green}"
      elseif "warning" == _exp_0 then
        color = "%{yellow}"
      elseif "error" == _exp_0 then
        color = "%{red}"
      elseif "debug" == _exp_0 then
        color = "%{dim white}"
      else
        color = "%{white}"
      end
      local timestamp = os.date("%H:%M:%S")
      return io.stderr:write(colors(tostring(color) .. "[" .. tostring(timestamp) .. "] " .. tostring(level:upper()) .. ": " .. tostring(message) .. "%{reset}\n"))
    end,
    setup_tools = function(self)
      self.tools = {
        routes = {
          name = "routes",
          title = "List Routes",
          description = "Lists all named routes in the Lapis application",
          inputSchema = {
            type = "object",
            properties = { },
            required = json.empty_array
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
            required = json.empty_array
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
      return self.transport:read_json_chunk()
    end,
    write_json_chunk = function(self, obj)
      return self.transport:write_json_chunk(obj)
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
      self:debug_log("info", "Received message: " .. tostring(message.method))
      local _exp_0 = message.method
      if "initialize" == _exp_0 then
        return self:handle_initialize(message)
      elseif "notifications/initialized" == _exp_0 then
        self:debug_log("info", "Client notified initialized")
        self.client_initialized = true
      elseif "notifications/cancelled" == _exp_0 then
        return self:handle_notifications_canceled(message)
      elseif "tools/list" == _exp_0 then
        self:debug_log("info", "Listing available tools")
        return self:handle_tools_list(message)
      elseif "tools/call" == _exp_0 then
        return self:handle_tools_call(message)
      else
        self:debug_log("warning", "Unknown method: " .. tostring(message.method))
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
      self:debug_log("info", "Initializing server with protocol version: " .. tostring(requested_version))
      if client_info.name then
        self:debug_log("debug", "Client: " .. tostring(client_info.name) .. " v" .. tostring(client_info.version or 'unknown'))
      end
      self.client_capabilities = client_capabilities
      if requested_version ~= self.protocol_version then
        self:debug_log("error", "Protocol version mismatch: server=" .. tostring(self.protocol_version) .. ", client=" .. tostring(requested_version))
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
      self:debug_log("success", "Server initialized successfully with " .. tostring(table.getn((function()
        local _accum_0 = { }
        local _len_0 = 1
        for k, v in pairs(self.tools) do
          _accum_0[_len_0] = k
          _len_0 = _len_0 + 1
        end
        return _accum_0
      end)())) .. " tools")
      return {
        jsonrpc = "2.0",
        id = message.id,
        result = {
          protocolVersion = self.protocol_version,
          capabilities = self.server_capabilities,
          serverInfo = {
            name = self.__class.server_name,
            version = self.__class.server_version,
            vendor = self.__class.server_vendor
          }
        }
      }
    end,
    handle_tools_call = with_initialized(function(self, message)
      local tool_name = message.params.name
      local params = message.params.arguments or { }
      self:debug_log("info", "Executing tool: " .. tostring(tool_name))
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
      if type(tool.inputSchema.required) == "table" then
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
      end
      local ok, result_or_error = pcall(tool.handler, self, params)
      if not ok then
        self:debug_log("error", "Tool execution failed: " .. tostring(result_or_error))
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
        self:debug_log("warning", "Tool returned error: " .. tostring(result_or_error.error))
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
      self:debug_log("success", "Tool executed successfully: " .. tostring(tool_name))
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
    end),
    handle_tools_list = with_initialized(function(self, message)
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
        id = message.id,
        result = {
          tools = tools_list
        }
      }
    end),
    handle_notifications_canceled = function(self, message)
      local id = message.params.requestId
      return nil
    end,
    send_message = function(self, message)
      return self:handle_message(message)
    end,
    run_stdio = function(self)
      self:debug_log("info", "Starting MCP server in stdio mode, waiting for initialization...")
      self.transport = StdioTransport()
      while true do
        local _continue_0 = false
        repeat
          local message = self:read_json_chunk()
          if message == false then
            self:debug_log("info", "io closed, exiting...")
            break
          end
          if not (message) then
            self:debug_log("warning", "Malformed message received: not valid JSON, ignoring...")
            _continue_0 = true
            break
          end
          local response = self:handle_message(message)
          if response then
            self:write_json_chunk(response)
          end
          _continue_0 = true
        until true
        if not _continue_0 then
          break
        end
      end
    end
  }
  _base_0.__index = _base_0
  _class_0 = setmetatable({
    __init = function(self, app, debug)
      if debug == nil then
        debug = false
      end
      self.app, self.debug = app, debug
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
  local self = _class_0
  self.server_name = "lapis-mcp"
  self.server_version = "1.0.0"
  self.server_vendor = "Lapis"
  McpServer = _class_0
end
return {
  McpServer = McpServer,
  StdioTransport = StdioTransport
}
