import McpServer from require "lapis.mcp.server"
import ToolCallInterface from require "lapis.mcp.tool_call_interface"
import OpenAIToolCallInterface from require "lapis.mcp.tool_call_interface.openai"
import AnthropicToolCallInterface from require "lapis.mcp.tool_call_interface.anthropic"
json = require "cjson.safe"

describe "ToolCallInterface", ->
  describe "initialization", ->
    it "should create interface with valid MCP server", ->
      class TestServer extends McpServer
      server = TestServer!
      tool_interface = ToolCallInterface(server)

      assert.is_not_nil tool_interface
      assert.equal server, tool_interface.server

    it "should error when creating without server", ->
      assert.has_error ->
        ToolCallInterface(nil)

  describe "get_available_tools", ->
    local server, tool_interface

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
      tool_interface = ToolCallInterface(server)

    it "should return only visible tools", ->
      tools = tool_interface\get_available_tools!
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
      empty_interface = ToolCallInterface(empty_server)

      tools = empty_interface\get_available_tools!
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
      tool_interface = ToolCallInterface(server)

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
      tool_interface = ToolCallInterface(server)

      assert.has_error ->
        tool_interface\to_tools!

  describe "execute_tool_call", ->
    local server, tool_interface

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

        @add_tool {
          name: "throw-error-tool"
          description: "A tool that throws an error"
          inputSchema: {
            type: "object"
            properties: {}
            required: setmetatable {}, json.array_mt
          }
        }, -> error "Something went wrong"

      server = TestServer!
      tool_interface = ToolCallInterface(server)

    describe "successful execution", ->
      it "should execute tool with all required parameters", ->
        success, result = tool_interface\execute_tool_call("add-numbers", {a: 5, b: 3})

        assert.is_true success
        assert.equal 8, result

      it "should execute tool with optional parameters provided", ->
        success, result = tool_interface\execute_tool_call("greet", {name: "Alice", greeting: "Hi"})

        assert.is_true success
        assert.equal "Hi, Alice!", result

      it "should execute tool with optional parameters omitted", ->
        success, result = tool_interface\execute_tool_call("greet", {name: "Bob"})

        assert.is_true success
        assert.equal "Hello, Bob!", result

      it "should return string values correctly", ->
        success, result = tool_interface\execute_tool_call("greet", {name: "Charlie"})

        assert.is_true success
        assert.is_string result
        assert.equal "Hello, Charlie!", result

      it "should return table/object values correctly", ->
        success, result = tool_interface\execute_tool_call("get-user-data", {user_id: "123"})

        assert.is_true success
        assert.is_table result
        assert.same {
          id: "123"
          name: "Test User"
          email: "test@example.com"
        }, result

      it "should return number values correctly", ->
        success, result = tool_interface\execute_tool_call("add-numbers", {a: 10, b: 20})

        assert.is_true success
        assert.equal 30, result
        assert.equal "number", type(result)

    describe "error handling", ->
      it "should return error when tool not found", ->
        success, error = tool_interface\execute_tool_call("nonexistent-tool", {})

        assert.is_false success
        assert.is_string error
        assert.is_true error\find("Tool not found") != nil

      it "should return error when missing required parameter", ->
        success, error = tool_interface\execute_tool_call("add-numbers", {a: 5})

        assert.is_false success
        assert.is_string error
        assert.is_true error\find("Missing required parameter") != nil

      it "should return error when tool handler returns nil with error", ->
        success, error = tool_interface\execute_tool_call("error-tool", {})

        assert.is_false success
        assert.equal "This is an error message", error

      it "should catch and return error when tool handler throws", ->
        success, error = tool_interface\execute_tool_call("throw-error-tool", {})

        assert.is_false success
        assert.is_string error
        assert.is_true error\find("Tool execution error") != nil

      it "should handle multiple missing required parameters", ->
        success, error = tool_interface\execute_tool_call("add-numbers", {})

        assert.is_false success
        assert.is_string error

  describe "execute_tool_call_json", ->
    local server, tool_interface

    before_each ->
      class TestServer extends McpServer
        @add_tool {
          name: "return-string"
          description: "Returns a string"
          inputSchema: {
            type: "object"
            properties: {}
            required: setmetatable {}, json.array_mt
          }
        }, -> "simple string"

        @add_tool {
          name: "return-object"
          description: "Returns an object"
          inputSchema: {
            type: "object"
            properties: {}
            required: setmetatable {}, json.array_mt
          }
        }, -> {
          status: "success"
          data: {
            id: 123
            name: "Test"
          }
        }

        @add_tool {
          name: "return-number"
          description: "Returns a number"
          inputSchema: {
            type: "object"
            properties: {}
            required: setmetatable {}, json.array_mt
          }
        }, -> 42

      server = TestServer!
      tool_interface = ToolCallInterface(server)

    it "should return string results as-is", ->
      success, result = tool_interface\execute_tool_call_json("return-string", {})

      assert.is_true success
      assert.is_string result
      assert.equal "simple string", result

    it "should encode table results as JSON", ->
      success, json_result = tool_interface\execute_tool_call_json("return-object", {})

      assert.is_true success
      assert.is_string json_result

      -- Parse back to verify it's valid JSON
      parsed = json.decode(json_result)
      assert.same {
        status: "success"
        data: {
          id: 123
          name: "Test"
        }
      }, parsed

    it "should encode number results as JSON", ->
      success, json_result = tool_interface\execute_tool_call_json("return-number", {})

      assert.is_true success
      assert.is_string json_result
      assert.equal "42", json_result

    it "should propagate errors from execute_tool_call", ->
      success, error = tool_interface\execute_tool_call_json("nonexistent", {})

      assert.is_false success
      assert.is_string error

describe "OpenAIToolCallInterface", ->
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
      tool_interface = OpenAIToolCallInterface(server)

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
      tool_interface = OpenAIToolCallInterface(server)

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
      tool_interface = OpenAIToolCallInterface(server)

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
      tool_interface = OpenAIToolCallInterface(server)

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
      tool_interface = OpenAIToolCallInterface(server)

    it "should convert all visible tools", ->
      openai_tools = tool_interface\to_tools!

      assert.equal 2, #openai_tools
      assert.equal "function", openai_tools[1].type
      assert.equal "function", openai_tools[2].type
      assert.is_table openai_tools[1].function
      assert.is_table openai_tools[2].function

describe "AnthropicToolCallInterface", ->
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
      tool_interface = AnthropicToolCallInterface(server)

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
      tool_interface = AnthropicToolCallInterface(server)

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
      tool_interface = AnthropicToolCallInterface(server)

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
      tool_interface = AnthropicToolCallInterface(server)

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

describe "complex realistic scenarios", ->
  local tool_interface_openai, tool_interface_anthropic

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
      tool_interface_openai = OpenAIToolCallInterface(server)
      tool_interface_anthropic = AnthropicToolCallInterface(server)

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
      success, result = tool_interface_openai\execute_tool_call("db-query", {
        table: "users"
        where: {
          status: "active"
          age: {gt: 18}
        }
        limit: 50
      })

      assert.is_true success
      assert.same {
        table: "users"
        conditions: {
          status: "active"
          age: {gt: 18}
        }
        limit: 50
        offset: 0
      }, result
