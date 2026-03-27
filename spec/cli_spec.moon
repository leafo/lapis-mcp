import McpServer from require "lapis.mcp.server"
import run_cli from require "lapis.mcp.cli"
json = require "cjson.safe"

run_cli_capture = (ServerClass, cli_args) ->
  printed = {}
  old_arg, old_print = _G.arg, _G.print

  _G.arg = cli_args
  _G.print = (...) ->
    values = {...}
    table.insert printed, table.concat([tostring(v) for v in *values], "\t")

  ok, result = pcall ->
    run_cli ServerClass

  _G.arg = old_arg
  _G.print = old_print

  ok, result, printed

describe "run_cli", ->
  class TestServer extends McpServer
    @add_tool {
      name: "visible-tool-1"
      description: "First visible tool"
      inputSchema: {
        type: "object"
        properties: {
          name: {
            type: "string"
          }
        }
        required: {"name"}
      }
    }, (params) => "hello #{params.name}"

    @add_tool {
      name: "hidden-tool"
      description: "Hidden tool"
      inputSchema: {
        type: "object"
        properties: {}
        required: setmetatable {}, json.array_mt
      }
      hidden: true
    }, -> "hidden"

    @add_tool {
      name: "visible-tool-2"
      description: "Second visible tool"
      inputSchema: {
        type: "object"
        properties: {
          count: {
            type: "number"
          }
        }
        required: {"count"}
      }
    }, (params) => params.count

  it "dumps OpenAI tool definitions", ->
    ok, result, printed = run_cli_capture TestServer, {"--dump-tools", "openai"}
    assert.is_true ok
    assert.is_nil result
    assert.equal 1, #printed

    tools = assert json.decode printed[1]
    assert.equal 2, #tools

    tool_names = {}
    for tool in *tools
      assert.equal "function", tool.type
      tool_names[tool.function.name] = true

    assert.is_true tool_names["visible-tool-1"]
    assert.is_true tool_names["visible-tool-2"]
    assert.is_nil tool_names["hidden-tool"]

  it "dumps Anthropic tool definitions", ->
    ok, result, printed = run_cli_capture TestServer, {"--dump-tools", "anthropic"}
    assert.is_true ok
    assert.is_nil result

    tools = assert json.decode printed[1]
    assert.equal 2, #tools

    tool_names = {}
    for tool in *tools
      assert.is_table tool.input_schema
      tool_names[tool.name] = true

    assert.is_true tool_names["visible-tool-1"]
    assert.is_true tool_names["visible-tool-2"]
    assert.is_nil tool_names["hidden-tool"]

  it "dumps Gemini tool definitions", ->
    ok, result, printed = run_cli_capture TestServer, {"--dump-tools", "gemini"}
    assert.is_true ok
    assert.is_nil result

    tools = assert json.decode printed[1]
    assert.equal 1, #tools
    assert.is_table tools[1].functionDeclarations
    assert.equal 2, #tools[1].functionDeclarations

    tool_names = {}
    for tool in *tools[1].functionDeclarations
      tool_names[tool.name] = true

    assert.is_true tool_names["visible-tool-1"]
    assert.is_true tool_names["visible-tool-2"]
    assert.is_nil tool_names["hidden-tool"]

  it "dumps single OpenAI tool when --tool is combined with --dump-tools", ->
    ok, result, printed = run_cli_capture TestServer, {
      "--dump-tools", "openai"
      "--tool", "visible-tool-1"
    }

    assert.is_true ok
    assert.is_nil result
    assert.equal 1, #printed

    tool = assert json.decode printed[1]
    assert.equal "function", tool.type
    assert.equal "visible-tool-1", tool.function.name

  it "dumps single Anthropic tool when --tool is combined with --dump-tools", ->
    ok, result, printed = run_cli_capture TestServer, {
      "--dump-tools", "anthropic"
      "--tool", "visible-tool-2"
    }

    assert.is_true ok
    assert.is_nil result
    assert.equal 1, #printed

    tool = assert json.decode printed[1]
    assert.equal "visible-tool-2", tool.name
    assert.is_table tool.input_schema
