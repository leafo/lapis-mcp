json = require "cjson.safe"
colors = require "ansicolors"
import insert from table

-- MCP server implementation for Lapis
-- Follows Model Context Protocol spec: https://modelcontextprotocol.io/

class StdioTransport
  -- IO and message handling
  read_json_chunk: =>
    chunk = io.read "*l"
    unless chunk
      return false

    message = json.decode chunk
    unless message
      return nil, "Failed to decode JSON chunk"

    message

  write_json_chunk: (obj) =>
    data = assert json.encode(obj)
    io.write data .. "\n"
    io.flush!

class StdioTransportWithDebugLog
  new: =>
    @file_log = io.open "/tmp/lapis-mcp.log", "a"
    @file_log\write "START SESSION: " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n"

  -- IO and message handling
  read_json_chunk: =>
    chunk = io.read "*l"
    unless chunk
      return false

    @file_log\write "READ: " .. chunk .. "\n"
    @file_log\flush!

    message = json.decode chunk
    unless message
      return nil, "Failed to decode JSON chunk"

    message

  write_json_chunk: (obj) =>
    data = assert json.encode(obj)

    @file_log\write "WRITE: " .. data .. "\n"
    @file_log\flush!

    io.write data .. "\n"
    io.flush!

class StreamableHttpTransport
  read_json_chunk: =>
    error "TODO"

  write_json_chunk: =>
    error "TODO"

with_initialized = (fn) ->
  (message) =>
    unless @initialized
      return {
        jsonrpc: "2.0"
        id: message.id
        error: {
          code: -32002
          message: "Server not initialized. Call initialize first."
        }
      }

    fn @, message

-- Base MCP server class that can be extended
class McpServer
  -- @server_name: "lapis-mcp"
  @server_version: "1.0.0"
  @server_vendor: "Lapis"

  -- Generic CLI runner using argparse
  @run_cli: (config) =>
    import run_cli from require "lapis.mcp.cli"
    run_cli @, config

  -- utility for creating sub class when in Lua
  @extend: (name, tbl) =>
    lua = require "lapis.lua"

    if type(name) == "table"
      tbl = name
      name = nil

    class_fields = { }

    cls = lua.class name or "McpServer", tbl, @
    cls, cls.__base

  -- add tool to the server
  -- https://modelcontextprotocol.io/docs/concepts/tools#tool-definition-structure
  @add_tool: (details, call_fn) =>
    unless rawget(@, "tools")
      rawset(@, "tools", {})

    tool_def = {
      name: details.name
      description: details.description
      inputSchema: details.inputSchema
      annotations: details.annotations
      handler: call_fn
      hidden: details.hidden or false
    }

    table.insert(rawget(@, "tools"), tool_def)

  -- add resource to the server
  -- https://modelcontextprotocol.io/specification/2024-11-05/server/resources.md
  -- https://modelcontextprotocol.io/docs/concepts/resources#direct-resources
  -- https://modelcontextprotocol.io/docs/concepts/resources#resource-templates
  @add_resource: (details, read_fn) =>
    unless rawget(@, "resources")
      rawset(@, "resources", {})

    lpeg_pattern = if details.uriTemplate
      import parse_template from require "lapis.mcp.uri"
      parse_template\match details.uriTemplate

    resource_def = {
      uri: details.uri
      uriTemplate: details.uriTemplate

      :lpeg_pattern

      name: details.name
      description: details.description
      mimeType: details.mimeType

      annotations: details.annotations
      handler: read_fn
      hidden: details.hidden or false
    }

    table.insert(rawget(@, "resources"), resource_def)

  -- send tools list changed notification
  notify_tools_list_changed: =>
    return unless @initialized

    @write_json_chunk {
      jsonrpc: "2.0"
      method: "notifications/tools/list_changed"
    }
    @debug_log "info", "Sent tools/list_changed notification"

  notify_resources_list_changed: =>
    return unless @initialized

    @write_json_chunk {
      jsonrpc: "2.0"
      method: "notifications/resources/list_changed"
    }
    @debug_log "info", "Sent resources/list_changed notification"

  -- set tool visibility on this instance
  -- tool_name can be a string (with visible param) or a table of name: visibility pairs
  set_tool_visibility: (tool_name, visible) =>
    changed_count = 0

    if type(tool_name) == "table"
      -- Table mode: tool_name is {name: visibility, ...}
      for name, vis in pairs tool_name
        old_visibility = @tool_visibility[name]
        @tool_visibility[name] = vis
        if old_visibility != vis
          changed_count += 1
    else
      -- Single tool mode
      old_visibility = @tool_visibility[tool_name]
      @tool_visibility[tool_name] = visible
      if old_visibility != visible
        changed_count += 1

    -- Send notification if any visibility actually changed
    if changed_count > 0
      @notify_tools_list_changed!
      true

  -- unhide a tool by name
  unhide_tool: (tool_name) =>
    @set_tool_visibility tool_name, true

  -- hide a tool by name
  hide_tool: (tool_name) =>
    @set_tool_visibility tool_name, false

  new: (options = {}) =>
    @debug = options.debug or false
    @protocol_version = "2025-06-18"
    @server_capabilities = {
      tools: {
        listChanged: true
      }
      resources: {
        subscribe: false
        listChanged: true
      }
    }
    @client_capabilities = {}
    @initialized = false
    @tool_visibility = {}

  -- Debug logging helper
  debug_log: (level, message) =>
    return unless @debug

    color = switch level
      when "info" then "%{cyan}"
      when "success" then "%{green}"
      when "warning" then "%{yellow}"
      when "error" then "%{red}"
      when "debug" then "%{dim white}"
      else "%{white}"

    timestamp = os.date("%H:%M:%S")
    io.stderr\write colors "#{color}[#{timestamp}] #{level\upper!}: #{message}%{reset}\n"

  -- Skip initialization and mark server as initialized
  skip_initialize: =>
    return nil, "Server already initialized" if @initialized
    @initialized = true
    @debug_log "info", "Skipping initialization"
    @initialized

  find_tool: (name) =>
    -- Search up the inheritance chain for the tool
    current_class = @.__class
    while current_class
      tools = rawget(current_class, "tools")
      if tools
        -- Search through the array for the tool by name
        for tool in *tools
          if tool.name == name
            return tool
      current_class = current_class.__parent
    nil

  find_resource: (uri) =>
    -- Search up the inheritance chain for the resource
    current_class = @.__class

    while current_class
      resources = rawget(current_class, "resources")
      if resources
        -- Search through the array for the resource by URI
        for resource in *resources
          if resource.lpeg_pattern
            if uri_params = resource.lpeg_pattern\match uri
              return resource, uri_params
          else
            if resource.uri == uri
              return resource, {}

      current_class = current_class.__parent
    nil

  -- IO and message handling
  read_json_chunk: =>
    @transport\read_json_chunk!

  write_json_chunk: (obj) =>
    @transport\write_json_chunk obj

  -- Message handler
  handle_message: (message) =>
    @debug_log "info", "Received message: #{message.method}"

    switch message.method
      when "initialize"
        @handle_initialize message
      when "notifications/initialized"
        @debug_log "info", "Client notified initialized"
        @client_initialized = true
      when "notifications/cancelled"
        @handle_notifications_canceled message
      when "tools/list"
        @debug_log "info", "Listing available tools"
        @handle_tools_list message
      when "tools/call"
        @handle_tools_call message
      when "resources/list"
        @debug_log "info", "Listing available resources"
        @handle_resources_list message
      when "resources/read"
        @handle_resources_read message
      when "ping"
        @handle_ping message
      else
        @debug_log "warning", "Unknown method: #{message.method}"
        {
          jsonrpc: "2.0"
          id: message.id
          error: {
            code: -32601
            message: "Method not found: #{message.method}"
          }
        }

  -- Handle initialization message
  handle_initialize: (message) =>
    params = message.params or {}

    -- Extract client info
    client_info = params.clientInfo or {}
    client_capabilities = params.capabilities or {}
    requested_version = params.protocolVersion or "2025-06-18"

    @debug_log "info", "Initializing server with protocol version: #{requested_version}"
    if client_info.name
      @debug_log "debug", "Client: #{client_info.name} v#{client_info.version or 'unknown'}"

    -- Store client capabilities
    @client_capabilities = client_capabilities

    -- Check protocol version compatibility
    if requested_version != @protocol_version
      @debug_log "error", "Protocol version mismatch: server=#{@protocol_version}, client=#{requested_version}"
      return {
        jsonrpc: "2.0"
        id: message.id
        error: {
          code: -32602
          message: "Protocol version mismatch. Server supports: #{@protocol_version}, client requested: #{requested_version}"
        }
      }

    @initialized = true
    @debug_log "success", "Server initialized"

    {
      jsonrpc: "2.0"
      id: message.id
      result: @server_specification!
    }

  get_server_name: =>
    @@server_name or @@__name

  server_specification: =>
    capabilities = {k,v for k, v in pairs @server_capabilities}

    {
      protocolVersion: @protocol_version
      capabilities: @server_capabilities
      serverInfo: {
        name: @get_server_name!
        version: @@server_version
        vendor: @@server_vendor
      }
      instructions: @@instructions
    }

  handle_tools_call: with_initialized (message) =>
    tool_name = message.params.name
    params = message.params.arguments or {}

    @debug_log "info", "Executing tool: #{tool_name}"

    tool = @find_tool tool_name

    unless tool
      return {
        jsonrpc: "2.0"
        id: message.id
        result: {
          content: {
            {
              type: "text"
              text: "Unknown tool: #{tool_name}"
            }
          }
          isError: true
        }
      }

    -- Validate required parameters
    -- it might not be a table if it's json.empty_array
    if type(tool.inputSchema.required) == "table"
      for param_name in *tool.inputSchema.required
        if not params[param_name]
          return {
            jsonrpc: "2.0"
            id: message.id
            result: {
              content: {
                {
                  type: "text"
                  text: "Missing required parameter: #{param_name}"
                }
              }
              isError: true
            }
          }

    -- Call the tool handler
    ok, result_or_error, user_error = pcall(tool.handler, @, params)

    if not ok
      @debug_log "error", "Tool execution failed: #{result_or_error}"
      return {
        jsonrpc: "2.0"
        id: message.id
        result: {
          content: {
            {
              type: "text"
              text: "Error executing tool: #{result_or_error}"
            }
          }
          isError: true
        }
      }

    -- wrap nil, err into object
    if result_or_error == nil
      @debug_log "warning", "Tool returned error: #{user_error or "Unknown error"}"
      return {
        jsonrpc: "2.0"
        id: message.id
        result: {
          content: {
            {
              type: "text"
              text: "Error executing tool: #{user_error or "Unknown error"}"
            }
          }
          isError: true
        }
      }

    @debug_log "success", "Tool executed successfully: #{tool_name}"

    return {
      jsonrpc: "2.0"
      id: message.id
      result: {
        content: {
          {
            type: "text"
            text: switch type result_or_error
              when "string"
                result_or_error
              else
                json.encode(result_or_error) or result_or_error
          }
        }
        isError: false
      }
    }

  -- Get all tools from the inheritance chain
  get_all_tools: =>
    all_tools = {}
    current_class = @__class
    while current_class
      if tools = rawget(current_class, "tools")
        for tool in *tools
          unless all_tools[tool.name]  -- Don't override tools from parent classes
            all_tools[tool.name] = tool

      current_class = current_class.__parent
    all_tools

  -- Get all resources from the inheritance chain
  get_all_resources: =>
    all_resources = {}
    current_class = @__class
    while current_class
      if resources = rawget(current_class, "resources")
        for resource in *resources
          key = resource.uri or resource.uriTemplate

          unless all_resources[key]  -- Don't override resources from parent classes
            all_resources[key] = resource

      current_class = current_class.__parent
    all_resources

  -- Get tools list response (for API and testing)
  handle_tools_list: with_initialized (message) =>
    tools_list = for name, tool in pairs @get_all_tools!
      -- Check instance visibility override first, then tool default
      is_visible = if @tool_visibility[tool.name] != nil
        @tool_visibility[tool.name]
      else
        not tool.hidden

      continue unless is_visible
      {
        name: tool.name
        description: tool.description
        inputSchema: tool.inputSchema
        annotations: tool.annotations
      }

    table.sort tools_list, (a, b) -> a.name < b.name

    {
      jsonrpc: "2.0"
      id: message.id
      result: {
        tools: tools_list
      }
    }

  -- Get resources list response (for API and testing)
  handle_resources_list: with_initialized (message) =>
    resources_list = for uri, resource in pairs @get_all_resources!
      -- Check instance visibility override first, then resource default
      is_visible = if @tool_visibility[resource.uri] != nil
        @tool_visibility[resource.uri]
      else
        not resource.hidden

      continue unless is_visible
      {
        uri: resource.uri
        uriTemplate: resource.uriTemplate
        name: resource.name
        description: resource.description
        mimeType: resource.mimeType
        annotations: resource.annotations
      }

    table.sort resources_list, (a, b) -> (a.uri or a.uriTemplate) < (b.uri or b.uriTemplate)

    {
      jsonrpc: "2.0"
      id: message.id
      result: {
        resources: resources_list
      }
    }

  -- Handle resources/read request
  handle_resources_read: with_initialized (message) =>
    resource_uri = message.params.uri

    @debug_log "info", "Reading resource: #{resource_uri}"

    resource, uri_params = @find_resource resource_uri

    unless resource
      return {
        jsonrpc: "2.0"
        id: message.id
        error: {
          code: -32002
          message: "Resource not found: #{resource_uri}"
        }
      }

    -- Call the resource handler
    ok, result_or_error, user_error = pcall(resource.handler, @, uri_params, message)

    if not ok
      @debug_log "error", "Resource read failed: #{result_or_error}"
      return {
        jsonrpc: "2.0"
        id: message.id
        error: {
          code: -32603
          message: "Error reading resource: #{result_or_error}"
        }
      }

    -- wrap nil, err into error response
    if result_or_error == nil
      @debug_log "warning", "Resource returned error: #{user_error or "Unknown error"}"
      return {
        jsonrpc: "2.0"
        id: message.id
        error: {
          code: -32603
          message: "Error reading resource: #{user_error or "Unknown error"}"
        }
      }

    @debug_log "success", "Resource read successfully: #{resource_uri}"

    -- Ensure result is in the correct format for resources/read response
    contents = if type(result_or_error) == "table" and result_or_error.contents
      result_or_error.contents
    else
      {
        {
          uri: resource_uri
          mimeType: resource.mimeType or "text/plain"
          text: switch type result_or_error
            when "string"
              result_or_error
            else
              json.encode(result_or_error) or tostring(result_or_error)
        }
      }

    {
      jsonrpc: "2.0"
      id: message.id
      result: {
        contents: contents
      }
    }

  -- Handle ping message
  handle_ping: (message) =>
    @debug_log "debug", "Received ping request"
    {
      jsonrpc: "2.0"
      id: message.id
      result: {}
    }

  --- called to cancel a running job
  -- {"jsonrpc":"2.0","method":"notifications/cancelled","params":{"requestId":1,"reason":"McpError: MCP error -32001: Request timed out"}}
  handle_notifications_canceled: (message) =>
    id = message.params.requestId
    -- we ignore this now, there's nothing we can do without async tasks
    nil

  -- alias for handle_message that's used for direct invocation via CLI
  send_message: (message) =>
    @handle_message message

  -- Server main loop
  run_stdio: =>
    @debug_log "info", table.concat {
      "Starting MCP server #{@get_server_name!} in stdio mode"
      if @initialized
        ", ready for messages"
      else
        ", waiting for initialization..."
    }

    unless @transport
      @transport = StdioTransport!

    -- Process messages
    while true
      message = @read_json_chunk!
      if message == false
        @debug_log "info", "io closed, exiting..."
        break

      unless message
        @debug_log "warning", "Malformed message received: not valid JSON, ignoring..."
        continue

      response = @handle_message message
      if response
        @write_json_chunk response

{:McpServer, :StdioTransport}
