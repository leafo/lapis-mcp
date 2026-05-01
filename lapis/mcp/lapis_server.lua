local json = require("cjson.safe")
local McpServer
McpServer = require("lapis.mcp.server").McpServer
local LapisMcpServer
do
  local _class_0
  local ok, pg_schema
  local _parent_0 = McpServer
  local _base_0 = { }
  _base_0.__index = _base_0
  setmetatable(_base_0, _parent_0.__base)
  _class_0 = setmetatable({
    __init = function(self, options)
      if options == nil then
        options = { }
      end
      self.app = options.app
      self.config = options.config
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
  ok, pg_schema = pcall(require, "lapis.annotate.pg_schema")
  if ok then
    self:add_tool({
      name = "schema",
      description = "Returns the SQL schema (CREATE TABLE, indexes, constraints) for one or more database models, dumped live from the project's PostgreSQL database via pg_dump.",
      inputSchema = {
        type = "object",
        properties = {
          models = {
            type = "array",
            items = {
              type = "string"
            },
            description = "Model class names to dump (e.g. [\"Users\", \"Posts\"])"
          }
        },
        required = {
          "models"
        }
      },
      annotations = {
        title = "Get Model Schema"
      }
    }, function(self, params)
      if not (self.config) then
        return nil, "schema tool requires Lapis project config (none was provided when starting the server)"
      end
      local autoload
      autoload = require("lapis.util").autoload
      local loader = autoload("models")
      local results = { }
      local _list_0 = params.models
      for _index_0 = 1, #_list_0 do
        local _continue_0 = false
        repeat
          local model_name = _list_0[_index_0]
          local model = loader[model_name]
          if not (model) then
            results[model_name] = {
              error = "Model not found: " .. tostring(model_name)
            }
            _continue_0 = true
            break
          end
          local schema_lines
          ok, schema_lines = pcall(pg_schema.extract_schema_sql, self.config, model)
          if not (ok) then
            results[model_name] = {
              error = tostring(schema_lines)
            }
            _continue_0 = true
            break
          end
          results[model_name] = {
            schema = table.concat(schema_lines, "\n")
          }
          _continue_0 = true
        until true
        if not _continue_0 then
          break
        end
      end
      return results
    end)
  end
  if _parent_0.__inherited then
    _parent_0.__inherited(_parent_0, _class_0)
  end
  LapisMcpServer = _class_0
  return _class_0
end
