ToolAdapter = require "lapis.mcp.tool_adapter"
json = require "cjson.safe"

-- Gemini-specific tool format conversion and execution
-- Reference: https://ai.google.dev/gemini-api/docs/function-calling
-- Schema reference: https://ai.google.dev/api/caching#Schema

GEMINI_TYPE_NAMES = {
  string: "STRING"
  number: "NUMBER"
  integer: "INTEGER"
  boolean: "BOOLEAN"
  array: "ARRAY"
  object: "OBJECT"
  ["null"]: "NULL"
}

class GeminiToolAdapter extends ToolAdapter
  normalize_schema_type: (schema_type) =>
    return nil unless schema_type
    GEMINI_TYPE_NAMES[schema_type] or schema_type

  normalize_schema_node: (schema) =>
    return nil unless type(schema) == "table"

    normalized = {}

    for key, value in pairs schema
      if key == "type"
        normalized.type = @normalize_schema_type value
      elseif key == "properties" and type(value) == "table"
        properties = {}
        for property_name, property_schema in pairs value
          properties[property_name] = @normalize_schema_node property_schema
        normalized.properties = properties
      elseif key == "items" and type(value) == "table"
        normalized.items = @normalize_schema_node value
      elseif key == "anyOf" and type(value) == "table"
        normalized.anyOf = [@normalize_schema_node option_schema for option_schema in *value]
      elseif key == "required" and type(value) == "table"
        if #value > 0
          normalized.required = value
      else
        normalized[key] = value

    normalized

  normalized_schema: (tool) =>
    input_schema = tool.inputSchema or tool
    schema = @normalize_schema_node input_schema

    unless schema.type
      schema.type = @normalize_schema_type "object"

    if (input_schema.type == nil or input_schema.type == "object" or input_schema.properties) and not schema.properties
      schema.properties = {}

    schema

  convert_tool: (tool) =>
    {
      name: tool.name
      description: tool.description
      parameters: @normalized_schema tool
    }

  to_tools: =>
    declarations = [@convert_tool(tool) for tool in *@server\get_enabled_tools!]
    return setmetatable({}, json.array_mt) if #declarations == 0

    setmetatable {
      {
        functionDeclarations: declarations
      }
    }, json.array_mt

  extract_tool_calls: (message) =>
    candidates = if type(message.candidates) == "table"
      message.candidates
    else
      {}

    tool_calls = {}
    for candidate in *candidates
      parts = if type(candidate.content) == "table" and type(candidate.content.parts) == "table"
        candidate.content.parts
      else
        {}

      for part in *parts
        continue unless type(part.functionCall) == "table"

        function_call = part.functionCall
        args = if type(function_call.args) == "table"
          function_call.args
        else
          {}

        table.insert tool_calls, {
          name: function_call.name
          arguments: args
          error: if function_call.args != nil and type(function_call.args) != "table"
            "Expected functionCall args to be an object"
        }

    tool_calls

  build_tool_result_message: =>
    error "GeminiToolAdapter does not support individual tool result messages, use build_tool_result_messages instead"

  build_tool_result_messages: =>
    error "GeminiToolAdapter requires process_tool_calls to build Gemini responses"

  process_tool_calls: (message) =>
    tool_calls = @extract_tool_calls message
    return {} unless tool_calls

    tool_results = [@execute_tool_call(tool_call) for tool_call in *tool_calls]
    return {} unless #tool_results > 0

    model_contents = {}
    candidates = if type(message.candidates) == "table"
      message.candidates
    else
      {}

    for candidate in *candidates
      continue unless type(candidate.content) == "table" and type(candidate.content.parts) == "table"
      table.insert model_contents, candidate.content

    response_parts = {}
    for tool_result in *tool_results
      payload = json.decode(tool_result.content) or tool_result.content
      error_payload = if type(payload) == "table" and payload.error != nil
        payload.error
      else
        payload

      response = if tool_result.is_error
        {
          error: error_payload
        }
      else
        {
          result: payload
        }

      table.insert response_parts, {
        functionResponse: {
          name: tool_result.tool_call.name
          :response
        }
      }

    messages = [content for content in *model_contents]
    table.insert messages, {
      role: "user"
      parts: response_parts
    }

    messages
