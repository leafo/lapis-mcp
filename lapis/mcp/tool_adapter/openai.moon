ToolAdapter = require "lapis.mcp.tool_adapter"
json = require "cjson.safe"

array = (items) ->
  setmetatable items, json.array_mt

has_value = (items, value) ->
  return false unless type(items) == "table"
  for item in *items
    return true if item == value
  false

copy_schema = (schema) ->
  return schema unless type(schema) == "table"

  out = {}
  for key, value in pairs schema
    out[key] = copy_schema value

  if getmetatable(schema) == json.array_mt
    setmetatable out, json.array_mt

  out

make_nullable = (schema) ->
  return schema unless type(schema) == "table"

  if type(schema.type) == "string"
    schema.type = array { schema.type, "null" }
  elseif type(schema.type) == "table"
    unless has_value schema.type, "null"
      table.insert schema.type, "null"

  if type(schema.enum) == "table"
    unless has_value schema.enum, json.null
      table.insert schema.enum, json.null

  schema

strict_schema_node = (schema, nullable=false) ->
  return schema unless type(schema) == "table"

  schema = copy_schema schema
  schema.default = nil

  is_object = schema.type == "object"
  if type(schema.type) == "table"
    is_object = has_value schema.type, "object"

  if is_object or schema.properties
    schema.properties = {} unless type(schema.properties) == "table"

    original_required = {}
    if type(schema.required) == "table"
      for key in *schema.required
        original_required[key] = true

    required = {}
    for key, property in pairs schema.properties
      table.insert required, key
      normalized_property = strict_schema_node property
      schema.properties[key] = if original_required[key]
        normalized_property
      else
        make_nullable normalized_property

    table.sort required
    schema.required = array required

    unless schema.additionalProperties != nil
      schema.additionalProperties = false

  if schema.items
    schema.items = strict_schema_node schema.items

  if nullable
    make_nullable schema

  schema

-- OpenAI-specific tool format conversion and execution
-- Reference: https://platform.openai.com/docs/guides/function-calling

class OpenAIToolAdapter extends ToolAdapter
  normalized_schema: (tool) =>
    strict_schema_node super tool

  convert_tool: (tool) =>
    {
      type: "function"
      function: {
        name: tool.name
        description: tool.description
        parameters: @normalized_schema tool
        strict: true
      }
    }

  -- Normalize tool calls from an OpenAI assistant message
  extract_tool_calls: (message) =>
    return {} unless message.tool_calls

    tool_calls = {}
    for tool_call in *message.tool_calls
      func = tool_call.function
      args = {}
      decode_error = nil

      if func.arguments and func.arguments != ""
        args, decode_error = json.decode func.arguments
        unless args
          args = {}

      table.insert tool_calls, {
        id: tool_call.id
        name: func.name
        arguments: args
        error: if decode_error
          "Failed to decode tool arguments as JSON: #{decode_error}"
      }

    tool_calls

  build_tool_result_message: (tool_result) =>
    {
      role: "tool"
      tool_call_id: tool_result.tool_call.id
      content: tool_result.content
    }
