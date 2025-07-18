# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

When making any changes to the implementation of the MCP protocol, please
review `mcp-guide.md` first.

## Build Commands

```bash
# Build MoonScript to Lua
make build

# Run tests
make test

# Install locally for development
make local
```

## Project Architecture

Lapis MCP is a Model Context Protocol (MCP) server for the Lapis web framework.
It follows the MCP specification to provide tools that help examine and
introspect Lapis applications.

If you are making changes to the implementation of the MCP protocol, please
download the respective specification document and review it before making any
changes:

* Basic Lifecycle: https://modelcontextprotocol.io/specification/2024-11-05/basic/lifecycle.md
* Tools: https://modelcontextprotocol.io/specification/2024-11-05/server/tools.md
* Resources: https://modelcontextprotocol.io/specification/2024-11-05/server/resources.md
* Prompts: https://modelcontextprotocol.io/specification/2024-11-05/server/prompts.md

### Core Components

1. **MCP Transport Layer** - Handles the MCP protocol communication
   - `StdioTransport` - Standard I/O transport for JSON-RPC messages
   - `StdioTransportWithDebugLog` - Debug version that logs to `/tmp/lapis-mcp.log`
   - `StreamableHttpTransport` - HTTP transport (TODO implementation)

2. **Base MCP Server** (`McpServer` class) - Generic MCP server implementation
   - `handle_message()` - Dispatches incoming messages to appropriate handlers
   - `run_stdio()` - Main loop that reads messages and sends responses
   - `@add_tool()` - Class method for registering tools with the server
   - `@extend()` - Utility for creating subclasses in Lua environments

3. **Lapis-Specific Implementation** (`LapisMcpServer` class) - Extends `McpServer`
   - `find_lapis_application()` - Attempts to load the application from standard locations
   - Pre-registered tools specific to Lapis applications

4. **CLI Interface** - Command-line interface for the MCP server
   - `--tool` - Direct tool invocation for testing
   - `--send-message` - Send raw MCP messages
   - `--debug` - Enable debug logging
   - `--skip-initialize` - Skip initialization for testing

### Available Tools

The Lapis MCP server provides these tools:
- `list_routes` - Lists all named routes in the Lapis application
- `list_models` - Lists all defined database models in the application
- `schema` - Shows the SQL schema for a specific model (TODO: implementation incomplete)

### File Structure

- `lapis/mcp/server.moon` - Base MCP server implementation with transport layers
- `lapis/cmd/actions/mcp.moon` - Lapis-specific MCP server and CLI interface
- `spec/server_spec.moon` - Test specifications
- `examples/file_system_mcp_server.moon` - Example MCP server implementation
- `Makefile` - Build system for the project
- `README.md` - Project documentation

The code is written in MoonScript, which compiles to Lua.

## Rockspec Configuration

The project uses a LuaRocks rockspec file (`lapis-mcp-dev-1.rockspec`) to
define the module and its installation. If any metadata changes, the rockspec
should be reviewed and updated.

When adding new modules to the project, they must be added to the `modules`
table in the rockspec file to be included in the installation.

## Development Guidelines

1. **Only edit .moon files** - Never modify the compiled .lua files directly. The Lua files are checked into the repository only so that MoonScript isn't a dependency at install time.

2. After making changes to .moon files, run `make build` to compile them to Lua, and then commit both the .moon and .lua files.

3. **Update rockspec when adding modules** - If you add new .moon/.lua files that should be part of the module, add them to the `modules` table in the rockspec file.
