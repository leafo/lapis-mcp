# CLAUDE.md

## Build

```bash
make build   # compile .moon -> .lua
make test    # busted
make local   # luarocks make --local
```

## Editing rules

- Only edit `.moon` files. The `.lua` files are checked in so MoonScript isn't an install-time dependency, but they are generated.
- After editing `.moon`, run `make build` and commit both the `.moon` and `.lua` files together.
- When adding a new module, add it to the `modules` table in `lapis-mcp-dev-1.rockspec`.

## MCP protocol changes

If you are changing the MCP protocol implementation, consult the relevant spec section first:

- Lifecycle: https://modelcontextprotocol.io/specification/2024-11-05/basic/lifecycle.md
- Tools: https://modelcontextprotocol.io/specification/2024-11-05/server/tools.md
- Resources: https://modelcontextprotocol.io/specification/2024-11-05/server/resources.md
- Prompts: https://modelcontextprotocol.io/specification/2024-11-05/server/prompts.md
