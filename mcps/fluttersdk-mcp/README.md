# @fluttersdk/mcp

HTTP-to-stdio bridge for the [FlutterSDK Docs MCP server](https://mcp.fluttersdk.com/).

The upstream server at `mcp.fluttersdk.com` speaks the Streamable HTTP MCP transport.
This bridge wraps it with a stdio transport so clients that do not support
Streamable HTTP natively (Claude Desktop, older Codex CLI, any shell-based MCP host)
can connect to it without modification.

## When to use

Use this bridge when your MCP client:

- Only supports stdio MCP transport (e.g. Claude Desktop, older Cursor versions).
- Cannot talk to HTTP-based MCP servers directly.
- Needs a proxy in front of the upstream for allowlist control.

If your client natively supports Streamable HTTP, point it directly at
`https://mcp.fluttersdk.com/` instead.

## Install and run

```bash
npx @fluttersdk/mcp
```

The bridge starts a local stdio MCP server. It does not connect to the upstream
until the first `tools/list` or `tools/call` request arrives (lazy connect).

## Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `FLUTTERSDK_MCP_URL` | `https://mcp.fluttersdk.com/` | Upstream MCP server URL |
| `BRIDGE_ALLOW_TOOLS` | `search-docs` | Comma-separated list of tool names to expose. Use `*` for unrestricted access. |

### Examples

Expose only the default `search-docs` tool (default behavior):

```bash
npx @fluttersdk/mcp
```

Expose all tools the upstream provides:

```bash
BRIDGE_ALLOW_TOOLS=* npx @fluttersdk/mcp
```

Point at a local upstream during development:

```bash
FLUTTERSDK_MCP_URL=http://localhost:8000/ npx @fluttersdk/mcp
```

## Claude Desktop configuration

Add the following to your Claude Desktop `claude_desktop_config.json`:

```json
{
    "mcpServers": {
        "fluttersdk": {
            "command": "npx",
            "args": ["@fluttersdk/mcp"]
        }
    }
}
```

To allow all upstream tools:

```json
{
    "mcpServers": {
        "fluttersdk": {
            "command": "npx",
            "args": ["@fluttersdk/mcp"],
            "env": {
                "BRIDGE_ALLOW_TOOLS": "*"
            }
        }
    }
}
```

## Available tools

The upstream server exposes one tool by default (and the bridge allowlist matches it):

| Tool | Description |
|------|-------------|
| `search-docs` | Search Flutter and Dart documentation. Accepts `queries`, `packages`, `version`, and `token_limit` parameters. |

## License

MIT
