local json = require("cjson")
local insert
insert = table.insert
local read_json_chunk
read_json_chunk = function()
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
end
local write_json_chunk
write_json_chunk = function(obj)
  local data = json.encode(obj)
  io.write(#data .. "\n")
  io.write(data .. "\n")
  return io.flush()
end
local find_lapis_application
find_lapis_application = function(config)
  local app_module = "app"
  if config.app_module then
    app_module = config.app_module
  end
  local ok, app = pcall(require, app_module)
  if ok then
    return app
  end
  local lapis = require("lapis")
  io.stderr:write("Warning: Loading empty Lapis application\n")
  return lapis.Application()
end
local list_routes
list_routes = function(app)
  local routes = { }
  if app.router and app.router.named_routes then
    for name, route in pairs(app.router.named_routes) do
      insert(routes, {
        name = name,
        path = route[1],
        method = route[2] or "GET"
      })
    end
  end
  return routes
end
local list_models
list_models = function()
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
end
local get_model_schema
get_model_schema = function(model_name)
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
end
local tools = {
  routes = {
    description = "Lists all named routes in the Lapis application",
    parameters = { },
    handler = function(app, params)
      return list_routes(app)
    end
  },
  models = {
    description = "Lists all database models defined in the application",
    parameters = { },
    handler = function(app, params)
      return list_models()
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
    handler = function(app, params)
      local schema, err = get_model_schema(params.model_name)
      if not schema then
        return {
          error = err
        }
      end
      return schema
    end
  }
}
local handle_message
handle_message = function(app, message)
  if message.type == "tool_call" then
    local tool_name = message.tool_call.name
    local params = message.tool_call.parameters
    if not (tools[tool_name]) then
      return {
        type = "tool_result",
        id = message.id,
        tool_result = {
          error = "Unknown tool: " .. tostring(tool_name)
        }
      }
    end
    local tool = tools[tool_name]
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
    local ok, result_or_error = pcall(tool.handler, app, params)
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
    local tools_list = { }
    for name, tool in pairs(tools) do
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
  else
    return {
      type = "error",
      error = "Unsupported message type: " .. tostring(message.type)
    }
  end
end
local run_mcp_server
run_mcp_server = function(app)
  write_json_chunk({
    type = "server_info",
    server = {
      name = "lapis-mcp",
      version = "0.1.0",
      vendor = "Lapis"
    }
  })
  while true do
    local message = read_json_chunk()
    if not (message) then
      break
    end
    local response = handle_message(app, message)
    write_json_chunk(response)
  end
end
return {
  argparser = function()
    return require("argparse")("lapis mcp", "Run an MCP server over stdin/out that can communicate with details of Lapis app")
  end,
  function(self, args, lapis_args)
    if args.hello then
      print("Hello from Lapis MCP!")
      return 
    end
    local config = self:get_config(lapis_args.environment)
    local app = find_lapis_application(config)
    return run_mcp_server(app)
  end
}
