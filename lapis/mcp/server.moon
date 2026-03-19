json = require "cjson.safe"
colors = require "ansicolors"
import insert from table

import types from require "tableshape"
import with_args from require "tableshape.ext.with_args"
import subclass_of from require "tableshape.moonscript"

-- MCP server implementation for Lapis
-- Follows Model Context Protocol spec: https://modelcontextprotocol.io/

fix_t = (t, b) -> t + b * t

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

clone_table = (value, seen=nil) ->
  return value unless type(value) == "table"

  seen or= {}
  return seen[value] if seen[value]

  cloned = {}
  seen[value] = cloned

  for k, v in pairs value
    cloned[clone_table(k, seen)] = clone_table(v, seen)

  setmetatable cloned, getmetatable value

schema_from_shape = (shape, label) ->
  import is_type from require "tableshape"
  assert is_type(shape), "#{label}: expected a tableshape type"
  import to_json_schema from require "tableshape.ext.json_schema"
  assert to_json_schema\transform shape

text_content = (value) ->
  {
    {
      type: "text"
      text: switch type value
        when "string"
          value
        else
          json.encode(value) or tostring(value)
    }
  }

collect_all_tools = (server_class) ->
  all_tools = {}
  current_class = server_class
  while current_class
    if tools = rawget(current_class, "tools")
      for tool in *tools
        unless all_tools[tool.name]
          all_tools[tool.name] = tool

    current_class = current_class.__parent

  all_tools

tool_exists_in_chain = (server_class, tool_name) ->
  current_class = server_class
  while current_class
    if tools = rawget(current_class, "tools")
      for tool in *tools
        return true if tool.name == tool_name

    current_class = current_class.__parent

  false

-- Base MCP server class that can be extended
class McpServer
  -- @server_name: "lapis-mcp"
  @server_version: "1.0.0"
  @server_vendor: "Lapis"
  -- @server_title: nil
  -- @server_description: nil
  -- @server_icons: nil
  -- @server_website_url: nil

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

    -- use a tableshape object for validation and input schema
    input_schema = if details.inputShape
      schema_from_shape details.inputShape, "inputShape"

    output_schema = if details.outputShape
      schema_from_shape details.outputShape, "outputShape"

    tool_def = {
      name: details.name
      description: details.description
      title: details.title
      icons: details.icons
      inputSchema: input_schema or details.inputSchema
      inputShape: details.inputShape
      outputSchema: output_schema or details.outputSchema
      outputShape: details.outputShape
      annotations: details.annotations
      handler: call_fn
      hidden: details.hidden or false
      tags: details.tags
    }

    table.insert(rawget(@, "tools"), tool_def)

  @include: with_args {
    assert: true
    types.table -- self

    fix_t subclass_of("McpServer")\describe("subclass of McpServer"), types.string / require

    types.shape({
      prefix: types.string\is_optional!
      add_tags: types.array_of(types.string)\is_optional!
      filter_tags: types.array_of(types.string)\is_optional!
    })\is_optional!
  }, (other_server_class, opts={}) =>
    prefix = opts.prefix or ""

    target_name = @server_name or @__name or "McpServer"
    source_name = other_server_class.server_name or other_server_class.__name or "McpServer"

    for original_name, tool in pairs collect_all_tools other_server_class
      final_name = prefix .. original_name

      if opts.filter_tags
        tool_tags = if tool.tags
          {t, true for t in *tool.tags}
        continue unless tool_tags
        has_match = false
        for t in *opts.filter_tags
          if tool_tags[t]
            has_match = true
            break
        continue unless has_match

      if tool_exists_in_chain @, final_name
        error "include collision on #{target_name}: source #{source_name} tool #{original_name} maps to existing tool #{final_name}"

      @add_tool {
        name: final_name
        description: tool.description
        title: tool.title
        icons: clone_table tool.icons
        inputSchema: clone_table tool.inputSchema
        inputShape: tool.inputShape
        outputSchema: clone_table tool.outputSchema
        outputShape: tool.outputShape
        annotations: clone_table tool.annotations
        hidden: tool.hidden
        tags: if opts.add_tags
          combined = {t, true for t in *(tool.tags or {})}
          for t in *opts.add_tags
            combined[t] = true
          [t for t in pairs combined]
        else
          tool.tags
      }, tool.handler

    @

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
      title: details.title
      icons: details.icons
      size: details.size
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

  -- hide all tools that don't match at least one of the provided tags
  -- tags: array of strings
  set_visibility_by_tags: (tags) =>
    return unless tags and #tags > 0
    tag_set = {t, true for t in *tags}
    for name, tool in pairs @get_all_tools!
      has_match = false
      if tool.tags
        for t in *tool.tags
          if tag_set[t]
            has_match = true
            break
      unless has_match
        @set_tool_visibility name, false

  new: (options = {}) =>
    @debug = options.debug or false
    @protocol_version = "2025-11-25"
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

  -- Execute a tool by name with the given arguments. Arguments should be a
  -- parsed object, not a json string
  -- Returns result on success, or nil and an error message on failure
  execute_tool: (tool_name, arguments={}) =>
    tool = @find_tool tool_name
    unless tool
      return nil, "Unknown tool: #{tool_name}"

    if tool.inputShape
      -- tableshape input validation and transformation
      arguments, err = tool.inputShape\transform arguments
      unless arguments
        return nil, err
    elseif type(tool.inputSchema.required) == "table"
      -- default validation strategy, just checking for parameters
      for param_name in *tool.inputSchema.required
        if arguments[param_name] == nil
          return nil, "Missing required parameter: #{param_name}"

    result, user_error = tool.handler @, arguments

    if result == nil
      return nil, user_error or "Unknown error"

    result

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
      when "resources/templates/list"
        @debug_log "info", "Listing available resource templates"
        @handle_resources_templates_list message
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

    -- Version negotiation: respond with our supported version, let client decide compatibility
    if requested_version != @protocol_version
      @debug_log "warn", "Client requested protocol version #{requested_version}, responding with #{@protocol_version}"

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
        title: @@server_title
        description: @@server_description
        icons: @@server_icons
        version: @@server_version
        vendor: @@server_vendor
        websiteUrl: @@server_website_url
      }
      instructions: @@instructions
    }

  handle_tools_call: with_initialized (message) =>
    tool_name = message.params.name
    tool = @find_tool tool_name

    @debug_log "info", "Executing tool: #{tool_name}"

    result, err = @execute_tool tool_name, message.params.arguments or {}

    if err
      @debug_log "error", err
      return {
        jsonrpc: "2.0"
        id: message.id
        result: {
          content: {
            {
              type: "text"
              text: err
            }
          }
          isError: true
        }
      }

    @debug_log "success", "Tool executed successfully: #{tool_name}"

    response_result = {
      content: text_content result
      isError: false
    }

    if tool and tool.outputSchema and type(result) == "table"
      response_result.structuredContent = result

    return {
      jsonrpc: "2.0"
      id: message.id
      result: response_result
    }

  -- Get all tools from the inheritance chain
  get_all_tools: =>
    collect_all_tools @__class

  -- Get enabled (visible) tools as an array, respecting tool_visibility and hidden
  get_enabled_tools: =>
    tools = for name, tool in pairs @get_all_tools!
      is_visible = if @tool_visibility[tool.name] != nil
        @tool_visibility[tool.name]
      else
        not tool.hidden

      continue unless is_visible
      tool

    table.sort tools, (a, b) -> a.name < b.name
    tools

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
    tools_list = for tool in *@get_enabled_tools!
      {
        name: tool.name
        description: tool.description
        title: tool.title
        icons: tool.icons
        inputSchema: tool.inputSchema
        outputSchema: tool.outputSchema
        annotations: tool.annotations
      }

    {
      jsonrpc: "2.0"
      id: message.id
      result: {
        tools: setmetatable tools_list, json.array_mt
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
      continue unless resource.uri

      {
        uri: resource.uri
        name: resource.name
        description: resource.description
        title: resource.title
        icons: resource.icons
        size: resource.size
        mimeType: resource.mimeType
        annotations: resource.annotations
      }

    table.sort resources_list, (a, b) -> a.uri < b.uri

    {
      jsonrpc: "2.0"
      id: message.id
      result: {
        resources: setmetatable resources_list, json.array_mt
      }
    }

  -- Get resource templates list response
  handle_resources_templates_list: with_initialized (message) =>
    resource_templates = for uri, resource in pairs @get_all_resources!
      -- Only include resources that have uriTemplate
      continue unless resource.uriTemplate

      -- Check instance visibility override first, then resource default
      is_visible = if @tool_visibility[resource.uri] != nil
        @tool_visibility[resource.uri]
      else
        not resource.hidden

      continue unless is_visible
      {
        uriTemplate: resource.uriTemplate
        name: resource.name
        description: resource.description
        title: resource.title
        icons: resource.icons
        mimeType: resource.mimeType
        annotations: resource.annotations
      }

    table.sort resource_templates, (a, b) -> a.uriTemplate < b.uriTemplate

    {
      jsonrpc: "2.0"
      id: message.id
      result: {
        resourceTemplates: setmetatable resource_templates, json.array_mt
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

  xml_response: (fn) =>
    -- this should create a buffer that can be used to generate a prompt using xml tags to wrap chunks of data
    import Buffer, element from require "lapis.html"

    buffer = Buffer {}

    fn setmetatable {
      raw: (...) -> buffer\write ...
      text: (...) -> buffer\write ...
    }, {
      __index: (key) =>
        (...) ->
          element buffer, key, ...
          @text "\n"
    }

    table.concat buffer.buffer

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
