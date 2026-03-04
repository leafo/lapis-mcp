-- Example: Using ToolCallInterface to bridge MCP servers with LLM APIs
--
-- This example demonstrates how to:
-- 1. Create an MCP server with tools
-- 2. Use provider-specific subclasses for format conversion
-- 3. Convert tools to OpenAI and Anthropic formats via to_tools()
-- 4. Execute tool calls from LLM responses

import McpServer from require "lapis.mcp.server"
import OpenAIToolCallInterface from require "lapis.mcp.tool_call_interface.openai"
import AnthropicToolCallInterface from require "lapis.mcp.tool_call_interface.anthropic"
json = require "cjson.safe"

-- Create a simple MCP server with some example tools
class ExampleMcpServer extends McpServer
  @server_name: "example-server"
  @instructions: [[Example server for demonstrating ToolCallInterface]]

  @add_tool {
    name: "add_numbers"
    description: "Adds two numbers together"
    inputSchema: {
      type: "object"
      properties: {
        a: {
          type: "number"
          description: "First number"
        }
        b: {
          type: "number"
          description: "Second number"
        }
      }
      required: {"a", "b"}
    }
  }, (params) =>
    params.a + params.b

  @add_tool {
    name: "greet_user"
    description: "Generates a greeting message for a user"
    inputSchema: {
      type: "object"
      properties: {
        name: {
          type: "string"
          description: "Name of the user to greet"
        }
        language: {
          type: "string"
          description: "Language for the greeting (en, es, fr)"
          default: "en"
        }
      }
      required: {"name"}
    }
  }, (params) =>
    greetings = {
      en: "Hello"
      es: "Hola"
      fr: "Bonjour"
    }
    language = params.language or "en"
    greeting = greetings[language] or greetings.en
    "#{greeting}, #{params.name}!"

-- Initialize the MCP server
server = ExampleMcpServer {}

-- Create provider-specific interfaces
openai_interface = OpenAIToolCallInterface(server)
anthropic_interface = AnthropicToolCallInterface(server)

print "=== Example: ToolCallInterface Usage ==="
print ""

-- 1. Convert to OpenAI format
print "1. OpenAI Tool Format:"
print "----------------------"
openai_tools = openai_interface\to_tools!
print json.encode(openai_tools)
print ""

-- 2. Convert to Anthropic format
print "2. Anthropic Tool Format:"
print "-------------------------"
anthropic_tools = anthropic_interface\to_tools!
print json.encode(anthropic_tools)
print ""

-- 3. Simulate executing a tool call from OpenAI response
print "3. Executing Tool Calls:"
print "------------------------"

-- Example: OpenAI returns this in the function_call
print "Calling add_numbers with {a: 5, b: 3}..."
success, result = openai_interface\execute_tool_call("add_numbers", {a: 5, b: 3})
if success
  print "Result: #{result}"
else
  print "Error: #{result}"
print ""

-- Example: Anthropic returns this in tool_use
print "Calling greet_user with {name: 'Alice', language: 'es'}..."
success, result = anthropic_interface\execute_tool_call("greet_user", {name: "Alice", language: "es"})
if success
  print "Result: #{result}"
else
  print "Error: #{result}"
print ""

-- 4. Execute with JSON formatting
print "4. Execute with JSON Result:"
print "----------------------------"
success, json_result = openai_interface\execute_tool_call_json("add_numbers", {a: 10, b: 20})
if success
  print "JSON Result: #{json_result}"
else
  print "Error: #{json_result}"
print ""

-- 5. Error handling example
print "5. Error Handling:"
print "------------------"
print "Calling add_numbers with missing required parameter 'b'..."
success, error_msg = openai_interface\execute_tool_call("add_numbers", {a: 5})
if success
  print "Result: #{error_msg}"
else
  print "Error: #{error_msg}"
print ""

print "=== Example Complete ==="

-- Usage in a real LLM API workflow:
--
-- Step 1: Get tools in the format your LLM API expects
--   openai_tools = openai_interface\to_tools!
--   anthropic_tools = anthropic_interface\to_tools!
--
-- Step 2: Send tools to LLM API in your request
--
-- Step 3: When LLM responds with a tool call, extract the tool name and arguments
--
-- Step 4: Execute the tool
--   success, result = openai_interface\execute_tool_call(tool_name, arguments)
--
-- Step 5: Send result back to LLM API for the next turn
--   (Implementation depends on your specific LLM API client)
