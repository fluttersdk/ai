# FlutterSDK Docs MCP Server

`mcp.fluttersdk.com` is the FlutterSDK Docs MCP server. It exposes a single
tool, `search-docs`, via the Streamable HTTP MCP transport. The server is
**public** — no credentials required after production redeploy
(rate limit: 60 requests/minute per source IP, soft cap).

---

## `search-docs` tool

Search Flutter and Dart package documentation across the FlutterSDK ecosystem.

### Input schema

| Parameter | Type | Required | Default | Notes |
|-----------|------|----------|---------|-------|
| `queries` | string[] | yes | — | One or more search queries |
| `packages` | string[] | no | all | Filter by package name(s) |
| `version` | string | no | latest | Semver string, e.g. `1.0.0-alpha.6` |
| `token_limit` | integer | no | 3000 | Max tokens in response. Hard ceiling: 100000 |

### Example call

```json
{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "tools/call",
    "params": {
        "name": "search-docs",
        "arguments": {
            "queries": ["WDiv flex layout", "className responsive"],
            "packages": ["wind_ui"],
            "token_limit": 5000
        }
    }
}
```

---

## Client configuration

### 1. Claude Code (native HTTP)

Claude Code supports Streamable HTTP natively. Add the server to your
`.mcp.json` at the project root:

**File:** `.mcp.json`

```json
{
    "mcpServers": {
        "fluttersdk": {
            "type": "http",
            "url": "https://mcp.fluttersdk.com/"
        }
    }
}
```

Or add via CLI:

```bash
claude mcp add --transport http fluttersdk https://mcp.fluttersdk.com/
```

---

### 2. Claude Desktop (npx bridge)

Claude Desktop only supports stdio transport. Use the npx bridge:

**File:** `~/Library/Application Support/Claude/claude_desktop_config.json`
(macOS) or `%APPDATA%\Claude\claude_desktop_config.json` (Windows)

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

See the [npx bridge section](#npx-bridge) for environment variable options.

---

### 3. Cursor

**File:** `.cursor/mcp.json`

```json
{
    "mcpServers": {
        "fluttersdk": {
            "type": "http",
            "url": "https://mcp.fluttersdk.com/"
        }
    }
}
```

---

### 4. OpenCode

**File:** `opencode.json` (project root or `~/.config/opencode/opencode.json`)

```json
{
    "mcp": {
        "fluttersdk": {
            "type": "remote",
            "url": "https://mcp.fluttersdk.com/"
        }
    }
}
```

---

### 5. Codex CLI

**File:** `~/.codex/config.toml`

```toml
[mcp_servers.fluttersdk]
url = "https://mcp.fluttersdk.com/"
```

Older Codex CLI versions that do not support native HTTP should use the
[npx bridge](#npx-bridge) instead.

---

### 6. Antigravity CLI

**File:** `~/.gemini/config/mcp_config.json`

```json
{
    "mcpServers": {
        "fluttersdk": {
            "serverUrl": "https://mcp.fluttersdk.com/"
        }
    }
}
```

Note: use `serverUrl`, not `httpUrl`.

---

### 7. Gemini CLI (enterprise tier)

**File:** `~/.gemini/settings.json`

```json
{
    "mcpServers": {
        "fluttersdk": {
            "url": "https://mcp.fluttersdk.com/"
        }
    }
}
```

---

### 8. VS Code Copilot

**File:** `.vscode/mcp.json`

```json
{
    "servers": {
        "fluttersdk": {
            "type": "http",
            "url": "https://mcp.fluttersdk.com/"
        }
    }
}
```

### 9. Cline (VS Code extension)

**File:** `cline_mcp_settings.json` (path varies by OS; check Cline docs for the
current location; on macOS it lives under `~/Library/Application Support/Code/User/globalStorage/saoudrizwan.claude-dev/settings/`).

```json
{
    "mcpServers": {
        "fluttersdk": {
            "url": "https://mcp.fluttersdk.com/"
        }
    }
}
```

### 10. Roo Code (VS Code extension)

**File:** `.roo/mcp.json` (project) or the global Roo Code MCP settings file.

```json
{
    "mcpServers": {
        "fluttersdk": {
            "url": "https://mcp.fluttersdk.com/"
        }
    }
}
```

---

## npx bridge

Use `npx @fluttersdk/mcp` when your client only supports stdio transport (e.g.
Claude Desktop, older Codex CLI without native HTTP, any shell-based MCP host).

The bridge is a thin HTTP-to-stdio proxy. It connects lazily: no upstream
connection is made until the first `tools/list` or `tools/call` arrives.

### Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `FLUTTERSDK_MCP_URL` | `https://mcp.fluttersdk.com/` | Upstream MCP server URL |
| `BRIDGE_ALLOW_TOOLS` | `search-docs` | Comma-separated tool names. Use `*` for all. |

### Examples

```bash
# Default: expose search-docs only
npx @fluttersdk/mcp

# Expose all upstream tools
BRIDGE_ALLOW_TOOLS=* npx @fluttersdk/mcp

# Point at a local upstream during development
FLUTTERSDK_MCP_URL=http://localhost:8000/ npx @fluttersdk/mcp
```

Full bridge documentation: [mcps/fluttersdk-mcp/README.md](../mcps/fluttersdk-mcp/README.md)

---

## Verification

Confirm the server is reachable and exposes `search-docs`:

```bash
curl -sS -X POST https://mcp.fluttersdk.com/ \
    -H 'Accept: application/json,text/event-stream' \
    -H 'Content-Type: application/json' \
    -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
```

Expected: HTTP 200 with a `tools` array containing an entry with `name: "search-docs"`.

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| HTTP 403 with `missing_token` body | Production not yet redeployed with public access | Wait for deployment or report at [GitHub Issues](https://github.com/fluttersdk/ai/issues) |
| Tool not found after adding config | Client cache stale | Restart the MCP client or reload the window |
| `npx @fluttersdk/mcp` hangs | No incoming MCP request yet | The bridge connects lazily; send a `tools/list` to trigger the connection |
| 429 Too Many Requests | Exceeded 60 req/min soft limit | Add a delay between calls or batch queries into a single `search-docs` call |

For issues not listed here, open a ticket at
[github.com/fluttersdk/ai/issues](https://github.com/fluttersdk/ai/issues).
