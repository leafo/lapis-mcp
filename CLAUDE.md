# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

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

Lapis MCP is a Model Context Protocol (MCP) server for the Lapis web framework. It follows the MCP specification to provide tools that help examine and introspect Lapis applications.

### Core Components

1. **MCP Communication Layer** - Handles the MCP protocol communication over stdin/stdout with JSON chunks
   - `read_json_chunk()` - Reads and parses incoming JSON messages
   - `write_json_chunk()` - Serializes and writes outgoing JSON messages

2. **Lapis Application Discovery** - Finds and loads the Lapis application to introspect
   - `find_lapis_application()` - Attempts to load the application from standard locations

3. **Tool Implementations** - Functions that extract information from the Lapis app
   - `list_routes()` - Extracts route information from the application router
   - `list_models()` - Discovers database models in the application
   - `get_model_schema()` - Extracts schema information from a specific model

4. **MCP Server** - Manages the protocol flow
   - `handle_message()` - Dispatches incoming messages to appropriate handlers
   - `run_mcp_server()` - Main loop that reads messages and sends responses

### Tool Structure

The MCP server provides these tools:
- `routes` - Lists all named routes in the application
- `models` - Lists all defined database models
- `schema` - Shows the schema for a specific model

### File Structure

- `lapis/cmd/actions/mcp.moon` - Main MCP server implementation
- `Makefile` - Build system for the project
- `README.md` - Project documentation

The code is written in MoonScript, which compiles to Lua.

## Development Guidelines

1. **Only edit .moon files** - Never modify the compiled .lua files directly. The Lua files are checked into the repository only so that MoonScript isn't a dependency at install time.

2. After making changes to .moon files, run `make build` to compile them to Lua, and then commit both the .moon and .lua files.
