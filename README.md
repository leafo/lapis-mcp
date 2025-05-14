# Lapis MCP

A Model Context Protocol (MCP) server for the [Lapis](https://leafo.net/lapis/) web framework that provides information about the current Lapis application to AI agents.

## Features

- List all named routes and their URLs
- List all models/database tables in your application 
- Show detailed schema for specific models

## Installation

```bash
luarocks install lapis-mcp
```

## Usage

Start the MCP server by running:

```bash
lapis mcp
```

This will start an MCP server that communicates over stdin/stdout, which can be connected to by any MCP client.

## Commands

The MCP server provides the following tools:

- `routes` - Lists all named routes in your Lapis application with their URL patterns
- `models` - Lists all models/database tables defined in your application
- `schema <model_name>` - Shows the database schema for a specific model

## License

MIT
