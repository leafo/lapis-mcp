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
    find_tool = function(self, name)
      local current_class = self.__class
      while current_class do
        local tools = rawget(current_class, "tools")
        if tools then
          for _index_0 = 1, #tools do
            local tool = tools[_index_0]
            if tool.name == name then
              return tool
            end
          end
        end
        current_class = current_class.__parent
      end
      return nil
    end,
    read_json_chunk = function(self)
      return self.transport:read_json_chunk()
    end,
    write_json_chunk = function(self, obj)
      return self.transport:write_json_chunk(obj)
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
      elseif "ping" == _exp_0 then
        return self:handle_ping(message)
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
      local tools = self:get_all_tools()
      local count = 0
      for name, tool in pairs(tools) do
        self.server_capabilities.tools[name] = true
        count = count + 1
      end
      self.initialized = true
      self:debug_log("success", "Server initialized successfully with " .. tostring(count) .. " tools")
      return {
        jsonrpc = "2.0",
        id = message.id,
        result = self:server_specification()
      }
    end,
    server_specification = function(self)
      return {
        protocolVersion = self.protocol_version,
        capabilities = self.server_capabilities,
        serverInfo = {
          name = self.__class.server_name or self.__class.__name,
          version = self.__class.server_version,
          vendor = self.__class.server_vendor
        },
        instructions = self.__class.instructions
      }
    end,
    handle_tools_call = with_initialized(function(self, message)
      local tool_name = message.params.name
      local params = message.params.arguments or { }
      self:debug_log("info", "Executing tool: " .. tostring(tool_name))
      local tool = self:find_tool(tool_name)
      if not (tool) then
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
      local ok, result_or_error, user_error = pcall(tool.handler, self, params)
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
      if result_or_error == nil then
        self:debug_log("warning", "Tool returned error: " .. tostring(user_error or "Unknown error"))
        return {
          jsonrpc = "2.0",
          id = message.id,
          result = {
            content = {
              {
                type = "text",
                text = "Error executing tool: " .. tostring(user_error or "Unknown error")
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
    get_all_tools = function(self)
      local all_tools = { }
      local current_class = self.__class
      while current_class do
        do
          local tools = rawget(current_class, "tools")
          if tools then
            for _index_0 = 1, #tools do
              local tool = tools[_index_0]
              if not (all_tools[tool.name]) then
                all_tools[tool.name] = tool
              end
            end
          end
        end
        current_class = current_class.__parent
      end
      return all_tools
    end,
    handle_tools_list = with_initialized(function(self, message)
      local tools_list
      do
        local _accum_0 = { }
        local _len_0 = 1
        for name, tool in pairs(self:get_all_tools()) do
          _accum_0[_len_0] = {
            name = tool.name,
            description = tool.description,
            inputSchema = tool.inputSchema,
            annotations = tool.annotations
          }
          _len_0 = _len_0 + 1
        end
        tools_list = _accum_0
      end
      table.sort(tools_list, function(a, b)
        return a.name < b.name
      end)
      return {
        jsonrpc = "2.0",
        id = message.id,
        result = {
          tools = tools_list
        }
      }
    end),
    handle_ping = function(self, message)
      self:debug_log("debug", "Received ping request")
      return {
        jsonrpc = "2.0",
        id = message.id,
        result = { }
      }
    end,
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
    __init = function(self, options)
      if options == nil then
        options = { }
      end
      self.debug = options.debug or false
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
  self.server_version = "1.0.0"
  self.server_vendor = "Lapis"
  self.extend = function(self, name, tbl)
    local lua = require("lapis.lua")
    if type(name) == "table" then
      tbl = name
      name = nil
    end
    local class_fields = { }
    local cls = lua.class(name or "McpServer", tbl, self)
    return cls, cls.__base
  end
  self.add_tool = function(self, details, call_fn)
    if not (rawget(self, "tools")) then
      rawset(self, "tools", { })
    end
    local tool_def = {
      name = details.name,
      description = details.description,
      inputSchema = details.inputSchema,
      annotations = details.annotations,
      handler = call_fn
    }
    return table.insert(rawget(self, "tools"), tool_def)
  end
  McpServer = _class_0
end
local LapisMcpServer
do
  local _class_0
  local _parent_0 = McpServer
  local _base_0 = { }
  _base_0.__index = _base_0
  setmetatable(_base_0, _parent_0.__base)
  _class_0 = setmetatable({
    __init = function(self, app, options)
      if options == nil then
        options = { }
      end
      self.app = app
      return _class_0.__parent.__init(self, options)
    end,
    __base = _base_0,
    __name = "LapisMcpServer",
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
  local self = _class_0
  self.server_name = "lapis-mcp"
  self.instructions = [[Tools to query information about the Lapis web application located in the current directory]]
  self:add_tool({
    name = "list_routes",
    description = "Lists all named routes in the Lapis application",
    inputSchema = {
      type = "object",
      properties = { },
      required = setmetatable({ }, json.array_mt)
    },
    annotations = {
      title = "List Routes"
    }
  }, function(self, params)
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
  end)
  self:add_tool({
    name = "list_models",
    description = "Lists all database models defined in the application. A model is a class that represents a database table.",
    inputSchema = {
      type = "object",
      properties = { },
      required = setmetatable({ }, json.array_mt)
    },
    annotations = {
      title = "List Models"
    }
  }, function(self, params)
    local shell_escape
    shell_escape = require("lapis.cmd.path").shell_escape
    local autoload
    autoload = require("lapis.util").autoload
    local loader = autoload("models")
    local models = { }
    for file in io.popen("find models/ -type f \\( -name '*.lua' -o -name '*.moon' \\)"):lines() do
      local model_name = file:match("([^/]+)%.%w+$")
      local model = loader[model_name]
      if model_name and not models[model_name] then
        models[model_name] = {
          name = model_name
        }
      end
    end
    return models
  end)
  self:add_tool({
    name = "schema",
    description = "Shows the SQl schema for a specific database model",
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
    annotations = {
      title = "Get Model Schema"
    }
  }, function(self, params)
    local model_name = params.model_name
    local ok, db = pcall(require, "models")
    if not ok or type(db) ~= "table" or not db[model_name] then
      return nil, "Model not found: " .. tostring(model_name)
    end
    local model = db[model_name]
    return error("not implemented yet")
  end)
  if _parent_0.__inherited then
    _parent_0.__inherited(_parent_0, _class_0)
  end
  LapisMcpServer = _class_0
end
return {
  McpServer = McpServer,
  LapisMcpServer = LapisMcpServer,
  StdioTransport = StdioTransport
}
