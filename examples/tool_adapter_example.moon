-- Example: End-to-end OpenAI integration using MCP tools via lua-openai
--
-- This example demonstrates a complete tool-calling loop:
-- 1. Define MCP tools on a server
-- 2. Convert them to OpenAI format via OpenAIToolAdapter
-- 3. Send a prompt to OpenAI that triggers tool calls
-- 4. Execute the tool calls and return results
-- 5. Get the final assistant response
--
-- Usage:
--   OPENAI_API_KEY=sk-... moon examples/tool_adapter_example.moon [model]

import McpServer from require "lapis.mcp.server"
OpenAIToolAdapter = require "lapis.mcp.tool_adapter.openai"
openai = require "openai"

-- Create a simple MCP server with some example tools
class ExampleMcpServer extends McpServer
  @server_name: "example-server"
  @instructions: [[Example server for demonstrating OpenAI tool calling]]

  @add_tool {
    name: "add_numbers"
    description: "Adds two numbers together and returns the sum"
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
    description: "Generates a greeting message for a user in the specified language"
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

-- Determine which model to use
model = arg[1] or os.getenv("OPENAI_TEST_MODEL") or "gpt-4.1"

-- Verify API key is set
api_key = os.getenv "OPENAI_API_KEY"
unless api_key
  print "Error: OPENAI_API_KEY environment variable is required"
  os.exit 1

-- Initialize components
interface = OpenAIToolAdapter ExampleMcpServer {}
client = openai.new api_key

-- Create a chat session with MCP tools converted to OpenAI format
chat = client\new_chat_session {
  :model
  tools: interface\to_tools!
  tool_choice: "auto"
}

print "=== OpenAI Tool Calling with MCP ==="
print "Model: #{model}"
print ""

prompt = "What is 15 + 27? Then greet Alice in Spanish."
print "User: #{prompt}"
print ""

-- Send initial message
response, err = chat\send prompt

unless response
  print "Error: #{err}"
  os.exit 1

-- Tool-calling loop: process tool calls until we get a text response
while type(response) == "table" and response.tool_calls
  for msg in *interface\process_tool_calls response
    print "Tool call: #{msg.tool_call_id}"
    print "Result: #{msg.content}"
    print ""
    chat\append_message msg

  -- Get next response after all tool results are sent
  response, err = chat\generate_response!

  unless response
    print "Error: #{err}"
    os.exit 1

-- Print final text response
print "Assistant: #{response}"
print ""
print "=== Done ==="
