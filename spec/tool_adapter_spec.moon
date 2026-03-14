import McpServer from require "lapis.mcp.server"
ToolAdapter = require "lapis.mcp.tool_adapter"
OpenAIToolAdapter = require "lapis.mcp.tool_adapter.openai"
AnthropicToolAdapter = require "lapis.mcp.tool_adapter.anthropic"
json = require "cjson.safe"

describe "ToolAdapter", ->
  describe "initialization", ->
    it "should create interface with valid MCP server", ->
      class TestServer extends McpServer
      server = TestServer!
      tool_interface = ToolAdapter(server)

      assert.is_not_nil tool_interface
      assert.equal server, tool_interface.server

    it "should error when creating without server", ->
      assert.has_error ->
        ToolAdapter(nil)

  describe "get_enabled_tools", ->
    local server

    before_each ->
      class TestServer extends McpServer
        @add_tool {
          name: "visible-tool-1"
          description: "First visible tool"
          inputSchema: {
            type: "object"
            properties: {}
            required: setmetatable {}, json.array_mt
          }
        }, -> "result1"

        @add_tool {
          name: "hidden-tool"
          description: "Hidden tool"
          inputSchema: {
            type: "object"
            properties: {}
            required: setmetatable {}, json.array_mt
          }
          hidden: true
        }, -> "hidden-result"

        @add_tool {
          name: "visible-tool-2"
          description: "Second visible tool"
          inputSchema: {
            type: "object"
            properties: {}
            required: setmetatable {}, json.array_mt
          }
        }, -> "result2"

      server = TestServer!

    it "should return only visible tools", ->
      tools = server\get_enabled_tools!
      assert.is_table tools
      assert.equal 2, #tools

      -- Collect tool names
      tool_names = {}
      for tool in *tools
        tool_names[tool.name] = true

      -- Check visible tools are included and hidden tool is not
      assert.is_true tool_names["visible-tool-1"]
      assert.is_true tool_names["visible-tool-2"]
      assert.is_nil tool_names["hidden-tool"]

    it "should handle server with no tools", ->
      class EmptyServer extends McpServer
      empty_server = EmptyServer!

      tools = empty_server\get_enabled_tools!
      assert.is_table tools
      assert.equal 0, #tools

  describe "convert_tool and to_tools on base class", ->
    it "should error when calling convert_tool on base class", ->
      class TestServer extends McpServer
        @add_tool {
          name: "test-tool"
          description: "A test tool"
          inputSchema: {
            type: "object"
            properties: {}
            required: setmetatable {}, json.array_mt
          }
        }, -> "result"

      server = TestServer!
      tool_interface = ToolAdapter(server)

      assert.has_error ->
        tool_interface\convert_tool({name: "test"})

    it "should error when calling to_tools on base class", ->
      class TestServer extends McpServer
        @add_tool {
          name: "test-tool"
          description: "A test tool"
          inputSchema: {
            type: "object"
            properties: {}
            required: setmetatable {}, json.array_mt
          }
        }, -> "result"

      server = TestServer!
      tool_interface = ToolAdapter(server)

      assert.has_error ->
        tool_interface\to_tools!

    it "should error when calling extract_tool_calls on base class", ->
      class TestServer extends McpServer
      tool_interface = ToolAdapter(TestServer!)

      assert.has_error ->
        tool_interface\extract_tool_calls {}

    it "should error when calling build_tool_result_message on base class", ->
      class TestServer extends McpServer
      tool_interface = ToolAdapter(TestServer!)

      assert.has_error ->
        tool_interface\build_tool_result_message {}

  describe "execute_tool", ->
    local server

    before_each ->
      class TestServer extends McpServer
        @add_tool {
          name: "add-numbers"
          description: "Adds two numbers"
          inputSchema: {
            type: "object"
            properties: {
              a: { type: "number", description: "First number" }
              b: { type: "number", description: "Second number" }
            }
            required: {"a", "b"}
          }
        }, (params) => params.a + params.b

        @add_tool {
          name: "greet"
          description: "Greets a user"
          inputSchema: {
            type: "object"
            properties: {
              name: { type: "string", description: "User name" }
              greeting: { type: "string", description: "Greeting type", default: "Hello" }
            }
            required: {"name"}
          }
        }, (params) =>
          greeting = params.greeting or "Hello"
          "#{greeting}, #{params.name}!"

        @add_tool {
          name: "get-user-data"
          description: "Returns user data as object"
          inputSchema: {
            type: "object"
            properties: {
              user_id: { type: "string" }
            }
            required: {"user_id"}
          }
        }, (params) => {
          id: params.user_id
          name: "Test User"
          email: "test@example.com"
        }

        @add_tool {
          name: "error-tool"
          description: "A tool that returns an error"
          inputSchema: {
            type: "object"
            properties: {}
            required: setmetatable {}, json.array_mt
          }
        }, -> nil, "This is an error message"

      server = TestServer!

    describe "successful execution", ->
      it "should execute tool with all required parameters", ->
        result = server\execute_tool "add-numbers", {a: 5, b: 3}
        assert.equal 8, result

      it "should execute tool with optional parameters provided", ->
        result = server\execute_tool "greet", {name: "Alice", greeting: "Hi"}
        assert.equal "Hi, Alice!", result

      it "should execute tool with optional parameters omitted", ->
        result = server\execute_tool "greet", {name: "Bob"}
        assert.equal "Hello, Bob!", result

      it "should return string values correctly", ->
        result = server\execute_tool "greet", {name: "Charlie"}
        assert.is_string result
        assert.equal "Hello, Charlie!", result

      it "should return table/object values correctly", ->
        result = server\execute_tool "get-user-data", {user_id: "123"}
        assert.is_table result
        assert.same {
          id: "123"
          name: "Test User"
          email: "test@example.com"
        }, result

      it "should return number values correctly", ->
        result = server\execute_tool "add-numbers", {a: 10, b: 20}
        assert.equal 30, result
        assert.equal "number", type(result)

    describe "error handling", ->
      it "should return error when tool not found", ->
        result, err = server\execute_tool "nonexistent-tool", {}
        assert.is_nil result
        assert.equal "Unknown tool: nonexistent-tool", err

      it "should return error when missing required parameter", ->
        result, err = server\execute_tool "add-numbers", {a: 5}
        assert.is_nil result
        assert.equal "Missing required parameter: b", err

      it "should return error when tool handler returns nil with error", ->
        result, err = server\execute_tool "error-tool", {}
        assert.is_nil result
        assert.equal "This is an error message", err

      it "should handle multiple missing required parameters", ->
        result, err = server\execute_tool "add-numbers", {}
        assert.is_nil result
        assert.is_string err

  describe "normalized_schema", ->
    local tool_interface

    before_each ->
      class TestServer extends McpServer
      tool_interface = ToolAdapter(TestServer!)

    it "should include required fields when present", ->
      schema = tool_interface\normalized_schema {
        inputSchema: {
          type: "object"
          properties: {
            query: {
              type: "string"
            }
          }
          required: {"query"}
        }
      }

      assert.same {
        type: "object"
        properties: {
          query: {
            type: "string"
          }
        }
        required: {"query"}
      }, schema

    it "should omit empty required arrays", ->
      schema = tool_interface\normalized_schema {
        inputSchema: {
          type: "object"
          properties: {}
          required: setmetatable {}, json.array_mt
        }
      }

      assert.same {
        type: "object"
        properties: {}
      }, schema

  describe "shared tool execution", ->
    local tool_interface

    before_each ->
      class TestServer extends McpServer
        @add_tool {
          name: "return-table"
          description: "Returns a table"
          inputSchema: {
            type: "object"
            properties: {}
            required: setmetatable {}, json.array_mt
          }
        }, -> {
          ok: true
        }

        @add_tool {
          name: "return-string"
          description: "Returns a string"
          inputSchema: {
            type: "object"
            properties: {}
            required: setmetatable {}, json.array_mt
          }
        }, -> "plain text"

      tool_interface = ToolAdapter(TestServer!)

    it "should serialize string results as-is", ->
      assert.equal "plain text", tool_interface\serialize_result("plain text")

    it "should serialize table results as JSON", ->
      tool_result = tool_interface\execute_tool_call {
        name: "return-table"
        arguments: {}
      }

      assert.is_false tool_result.is_error
      assert.is_string tool_result.content
      parsed = json.decode tool_result.content
      assert.same {
        ok: true
      }, parsed

    it "should serialize tool execution errors as JSON", ->
      tool_result = tool_interface\execute_tool_call {
        name: "missing-tool"
        arguments: {}
      }

      assert.is_true tool_result.is_error
      assert.same {
        error: "Unknown tool: missing-tool"
      }, json.decode(tool_result.content)

describe "OpenAIToolAdapter", ->
  local tool_interface

  describe "with no parameters", ->
    before_each ->
      class TestServer extends McpServer
        @add_tool {
          name: "simple-tool"
          description: "A tool with no parameters"
          inputSchema: {
            type: "object"
            properties: {}
            required: setmetatable {}, json.array_mt
          }
        }, -> "result"

      server = TestServer!
      tool_interface = OpenAIToolAdapter(server)

    it "should convert to OpenAI format with empty properties", ->
      openai_tools = tool_interface\to_tools!

      expected = {
        {
          type: "function"
          function: {
            name: "simple-tool"
            description: "A tool with no parameters"
            parameters: {
              type: "object"
              properties: {}
            }
          }
        }
      }

      assert.same expected, openai_tools

  describe "with only required parameters", ->
    before_each ->
      class TestServer extends McpServer
        @add_tool {
          name: "required-params-tool"
          description: "A tool with required parameters"
          inputSchema: {
            type: "object"
            properties: {
              name: {
                type: "string"
                description: "User name"
              }
              age: {
                type: "number"
                description: "User age"
              }
            }
            required: {"name", "age"}
          }
        }, -> "result"

      server = TestServer!
      tool_interface = OpenAIToolAdapter(server)

    it "should include required array in parameters", ->
      openai_tools = tool_interface\to_tools!

      expected = {
        {
          type: "function"
          function: {
            name: "required-params-tool"
            description: "A tool with required parameters"
            parameters: {
              type: "object"
              properties: {
                name: {
                  type: "string"
                  description: "User name"
                }
                age: {
                  type: "number"
                  description: "User age"
                }
              }
              required: {"name", "age"}
            }
          }
        }
      }

      assert.same expected, openai_tools

  describe "with mixed required and optional parameters", ->
    before_each ->
      class TestServer extends McpServer
        @add_tool {
          name: "mixed-params-tool"
          description: "A tool with mixed parameters"
          inputSchema: {
            type: "object"
            properties: {
              required_field: {
                type: "string"
                description: "Required field"
              }
              optional_field: {
                type: "string"
                description: "Optional field"
                default: "default-value"
              }
            }
            required: {"required_field"}
          }
        }, -> "result"

      server = TestServer!
      tool_interface = OpenAIToolAdapter(server)

    it "should include only required fields in required array", ->
      openai_tools = tool_interface\to_tools!

      expected = {
        {
          type: "function"
          function: {
            name: "mixed-params-tool"
            description: "A tool with mixed parameters"
            parameters: {
              type: "object"
              properties: {
                required_field: {
                  type: "string"
                  description: "Required field"
                }
                optional_field: {
                  type: "string"
                  description: "Optional field"
                  default: "default-value"
                }
              }
              required: {"required_field"}
            }
          }
        }
      }

      assert.same expected, openai_tools

  describe "with various parameter types", ->
    before_each ->
      class TestServer extends McpServer
        @add_tool {
          name: "typed-params-tool"
          description: "A tool with various parameter types"
          inputSchema: {
            type: "object"
            properties: {
              str_param: {
                type: "string"
                description: "A string parameter"
              }
              num_param: {
                type: "number"
                description: "A number parameter"
              }
              bool_param: {
                type: "boolean"
                description: "A boolean parameter"
              }
            }
            required: {"str_param"}
          }
        }, -> "result"

      server = TestServer!
      tool_interface = OpenAIToolAdapter(server)

    it "should preserve all parameter types", ->
      openai_tools = tool_interface\to_tools!

      expected = {
        {
          type: "function"
          function: {
            name: "typed-params-tool"
            description: "A tool with various parameter types"
            parameters: {
              type: "object"
              properties: {
                str_param: {
                  type: "string"
                  description: "A string parameter"
                }
                num_param: {
                  type: "number"
                  description: "A number parameter"
                }
                bool_param: {
                  type: "boolean"
                  description: "A boolean parameter"
                }
              }
              required: {"str_param"}
            }
          }
        }
      }

      assert.same expected, openai_tools

  describe "with multiple tools", ->
    before_each ->
      class TestServer extends McpServer
        @add_tool {
          name: "tool-one"
          description: "First tool"
          inputSchema: {
            type: "object"
            properties: {
              param1: { type: "string" }
            }
            required: {"param1"}
          }
        }, -> "result1"

        @add_tool {
          name: "tool-two"
          description: "Second tool"
          inputSchema: {
            type: "object"
            properties: {
              param2: { type: "number" }
            }
            required: setmetatable {}, json.array_mt
          }
        }, -> "result2"

      server = TestServer!
      tool_interface = OpenAIToolAdapter(server)

    it "should convert all visible tools", ->
      openai_tools = tool_interface\to_tools!

      assert.equal 2, #openai_tools
      assert.equal "function", openai_tools[1].type
      assert.equal "function", openai_tools[2].type
      assert.is_table openai_tools[1].function
      assert.is_table openai_tools[2].function

  describe "process_tool_calls", ->
    before_each ->
      class TestServer extends McpServer
        @add_tool {
          name: "echo-tool"
          description: "Echoes a value"
          inputSchema: {
            type: "object"
            properties: {
              value: {
                type: "string"
              }
            }
            required: {"value"}
          }
        }, (params) => {
          echoed: params.value
        }

      server = TestServer!
      tool_interface = OpenAIToolAdapter(server)

    it "should execute tool calls and return OpenAI tool messages", ->
      messages = tool_interface\process_tool_calls {
        tool_calls: {
          {
            id: "call_123"
            function: {
              name: "echo-tool"
              arguments: '{"value":"hello"}'
            }
          }
        }
      }

      assert.same {
        {
          role: "tool"
          tool_call_id: "call_123"
          content: '{"echoed":"hello"}'
        }
      }, messages

    it "should return JSON error content when execution fails", ->
      messages = tool_interface\process_tool_calls {
        tool_calls: {
          {
            id: "call_missing_tool"
            function: {
              name: "missing-tool"
              arguments: "{}"
            }
          }
        }
      }

      assert.same {
        error: "Unknown tool: missing-tool"
      }, json.decode(messages[1].content)

    it "should return JSON error content when arguments are invalid JSON", ->
      messages = tool_interface\process_tool_calls {
        tool_calls: {
          {
            id: "call_bad_json"
            function: {
              name: "echo-tool"
              arguments: '{"value":'
            }
          }
        }
      }

      assert.equal 1, #messages
      assert.equal "tool", messages[1].role
      assert.equal "call_bad_json", messages[1].tool_call_id
      parsed = json.decode messages[1].content
      assert.is_string parsed.error
      assert.truthy parsed.error\find "Failed to decode tool arguments as JSON"

describe "AnthropicToolAdapter", ->
  local tool_interface

  describe "with no parameters", ->
    before_each ->
      class TestServer extends McpServer
        @add_tool {
          name: "simple-tool"
          description: "A tool with no parameters"
          inputSchema: {
            type: "object"
            properties: {}
            required: setmetatable {}, json.array_mt
          }
        }, -> "result"

      server = TestServer!
      tool_interface = AnthropicToolAdapter(server)

    it "should convert to Anthropic format with empty properties", ->
      anthropic_tools = tool_interface\to_tools!

      expected = {
        {
          name: "simple-tool"
          description: "A tool with no parameters"
          input_schema: {
            type: "object"
            properties: {}
          }
        }
      }

      assert.same expected, anthropic_tools

  describe "with required parameters", ->
    before_each ->
      class TestServer extends McpServer
        @add_tool {
          name: "required-params-tool"
          description: "A tool with required parameters"
          inputSchema: {
            type: "object"
            properties: {
              query: {
                type: "string"
                description: "Search query"
              }
              limit: {
                type: "number"
                description: "Result limit"
              }
            }
            required: {"query", "limit"}
          }
        }, -> "result"

      server = TestServer!
      tool_interface = AnthropicToolAdapter(server)

    it "should include required array in input_schema", ->
      anthropic_tools = tool_interface\to_tools!

      expected = {
        {
          name: "required-params-tool"
          description: "A tool with required parameters"
          input_schema: {
            type: "object"
            properties: {
              query: {
                type: "string"
                description: "Search query"
              }
              limit: {
                type: "number"
                description: "Result limit"
              }
            }
            required: {"query", "limit"}
          }
        }
      }

      assert.same expected, anthropic_tools

  describe "with mixed parameters", ->
    before_each ->
      class TestServer extends McpServer
        @add_tool {
          name: "mixed-tool"
          description: "Mixed parameters tool"
          inputSchema: {
            type: "object"
            properties: {
              required_param: {
                type: "string"
              }
              optional_param: {
                type: "string"
                default: "default"
              }
            }
            required: {"required_param"}
          }
        }, -> "result"

      server = TestServer!
      tool_interface = AnthropicToolAdapter(server)

    it "should preserve parameter structure with defaults", ->
      anthropic_tools = tool_interface\to_tools!

      expected = {
        {
          name: "mixed-tool"
          description: "Mixed parameters tool"
          input_schema: {
            type: "object"
            properties: {
              required_param: {
                type: "string"
              }
              optional_param: {
                type: "string"
                default: "default"
              }
            }
            required: {"required_param"}
          }
        }
      }

      assert.same expected, anthropic_tools

  describe "with multiple tools", ->
    before_each ->
      class TestServer extends McpServer
        @add_tool {
          name: "anthropic-tool-one"
          description: "First Anthropic tool"
          inputSchema: {
            type: "object"
            properties: {
              id: { type: "string" }
            }
            required: {"id"}
          }
        }, -> "result1"

        @add_tool {
          name: "anthropic-tool-two"
          description: "Second Anthropic tool"
          inputSchema: {
            type: "object"
            properties: {
              count: { type: "number" }
            }
            required: setmetatable {}, json.array_mt
          }
        }, -> "result2"

      server = TestServer!
      tool_interface = AnthropicToolAdapter(server)

    it "should convert all visible tools to Anthropic format", ->
      anthropic_tools = tool_interface\to_tools!

      assert.equal 2, #anthropic_tools

      -- Find tools by name (order not guaranteed)
      tool_one = nil
      tool_two = nil
      for tool in *anthropic_tools
        if tool.name == "anthropic-tool-one"
          tool_one = tool
        elseif tool.name == "anthropic-tool-two"
          tool_two = tool

      assert.is_not_nil tool_one
      assert.is_not_nil tool_two
      assert.is_table tool_one.input_schema
      assert.is_table tool_two.input_schema

  describe "process_tool_calls", ->
    before_each ->
      class TestServer extends McpServer
        @add_tool {
          name: "echo-tool"
          description: "Echoes a value"
          inputSchema: {
            type: "object"
            properties: {
              value: {
                type: "string"
              }
            }
            required: {"value"}
          }
        }, (params) => {
          echoed: params.value
        }

      server = TestServer!
      tool_interface = AnthropicToolAdapter(server)

    it "should convert tool_use blocks into a single user tool_result message", ->
      messages = tool_interface\process_tool_calls {
        role: "assistant"
        content: {
          {
            type: "text"
            text: "Let me look that up."
          }
          {
            type: "tool_use"
            id: "toolu_123"
            name: "echo-tool"
            input: {
              value: "hello"
            }
          }
        }
      }

      assert.same {
        {
          role: "user"
          content: {
            {
              type: "tool_result"
              tool_use_id: "toolu_123"
              content: '{"echoed":"hello"}'
            }
          }
        }
      }, messages

    it "should include is_error for tool execution failures", ->
      messages = tool_interface\process_tool_calls {
        role: "assistant"
        content: {
          {
            type: "tool_use"
            id: "toolu_missing"
            name: "missing-tool"
            input: {}
          }
        }
      }

      assert.equal 1, #messages
      assert.equal "user", messages[1].role
      assert.same {
        type: "tool_result"
        tool_use_id: "toolu_missing"
        content: '{"error":"Unknown tool: missing-tool"}'
        is_error: true
      }, messages[1].content[1]

    it "should include is_error for malformed tool inputs", ->
      messages = tool_interface\process_tool_calls {
        role: "assistant"
        content: {
          {
            type: "tool_use"
            id: "toolu_bad_input"
            name: "echo-tool"
            input: "not-an-object"
          }
        }
      }

      assert.same {
        type: "tool_result"
        tool_use_id: "toolu_bad_input"
        content: '{"error":"Expected tool_use input to be an object"}'
        is_error: true
      }, messages[1].content[1]

describe "complex realistic scenarios", ->
  local server, tool_interface_openai, tool_interface_anthropic

  describe "database query tool", ->
    before_each ->
      class TestServer extends McpServer
        @add_tool {
          name: "db-query"
          description: "Execute a database query"
          inputSchema: {
            type: "object"
            properties: {
              table: {
                type: "string"
                description: "Table name"
              }
              where: {
                type: "object"
                description: "WHERE conditions"
              }
              limit: {
                type: "number"
                description: "Result limit"
                default: 10
              }
              offset: {
                type: "number"
                description: "Result offset"
                default: 0
              }
            }
            required: {"table", "where"}
          }
        }, (params) => {
          table: params.table
          conditions: params.where
          limit: params.limit or 10
          offset: params.offset or 0
        }

      server = TestServer!
      tool_interface_openai = OpenAIToolAdapter(server)
      tool_interface_anthropic = AnthropicToolAdapter(server)

    it "should convert complex tool to OpenAI format", ->
      openai_tools = tool_interface_openai\to_tools!

      expected_tool = {
        type: "function"
        function: {
          name: "db-query"
          description: "Execute a database query"
          parameters: {
            type: "object"
            properties: {
              table: {
                type: "string"
                description: "Table name"
              }
              where: {
                type: "object"
                description: "WHERE conditions"
              }
              limit: {
                type: "number"
                description: "Result limit"
                default: 10
              }
              offset: {
                type: "number"
                description: "Result offset"
                default: 0
              }
            }
            required: {"table", "where"}
          }
        }
      }

      assert.same expected_tool, openai_tools[1]

    it "should convert complex tool to Anthropic format", ->
      anthropic_tools = tool_interface_anthropic\to_tools!

      expected_tool = {
        name: "db-query"
        description: "Execute a database query"
        input_schema: {
          type: "object"
          properties: {
            table: {
              type: "string"
              description: "Table name"
            }
            where: {
              type: "object"
              description: "WHERE conditions"
            }
            limit: {
              type: "number"
              description: "Result limit"
              default: 10
            }
            offset: {
              type: "number"
              description: "Result offset"
              default: 0
            }
          }
          required: {"table", "where"}
        }
      }

      assert.same expected_tool, anthropic_tools[1]

    it "should execute with complex nested parameters", ->
      result = server\execute_tool "db-query", {
        table: "users"
        where: {
          status: "active"
          age: {gt: 18}
        }
        limit: 50
      }

      assert.same {
        table: "users"
        conditions: {
          status: "active"
          age: {gt: 18}
        }
        limit: 50
        offset: 0
      }, result
