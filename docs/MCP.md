# anilcancakir.com Docs MCP Server

`https://mcp.anilcancakir.com/` is the docs MCP server of anilcancakir.com. It gives an agent read-only access to the documentation of the packages published there (`wind_kit`, `dowel`, `magic_device` and the rest as they land), over the Streamable HTTP MCP transport. It is public: no account and no token.

The Claude Code plugin from this repository registers it for you through `.mcp.json`. Use the snippets below to add it to a client that does not install the plugin.

---

## Tools

| Tool | Input | Use it to |
|:-----|:------|:----------|
| `list_packages` | none | See every package with its current version, the readable minor series and the docs URL. Call it first: its slugs and series are the `package` and `version` inputs of the other tools |
| `list_docs` | `package` (required), `version` | List the pages of one package, grouped by section, each with an id (`section/page`) |
| `search_docs` | `query` (required, at most six words), `package`, `version`, `limit` (at most 20) | Find the pages that contain every word of the query, best first, with an excerpt |
| `read_doc` | `package` (required), `page` (required, `section/page`), `version` | Read the full markdown of one page |

`version` is a minor series such as `1.10`; omit it for the current one. The server also lists resources and prompts through the standard MCP calls.

### Example call

```json
{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "tools/call",
    "params": {
        "name": "search_docs",
        "arguments": {
            "package": "wind_kit",
            "query": "flex responsive"
        }
    }
}
```

---

## Client configuration

### 1. Claude Code (native HTTP)

> **The plugin registers this for you.** If you installed `anilcancakir@anilcancakir-marketplace`, the plugin ships its own `.mcp.json` and Claude Code loads it. The manual config below is for adding only the MCP server.

**File:** `.mcp.json` at the project root

```json
{
    "mcpServers": {
        "anilcancakir": {
            "type": "http",
            "url": "https://mcp.anilcancakir.com/"
        }
    }
}
```

Or add it with the CLI:

```bash
claude mcp add --transport http anilcancakir https://mcp.anilcancakir.com/
```

---

### 2. Claude Desktop (stdio bridge)

Claude Desktop speaks stdio only. Bridge the HTTP server with `mcp-remote`:

**File:** `~/Library/Application Support/Claude/claude_desktop_config.json`
(macOS) or `%APPDATA%\Claude\claude_desktop_config.json` (Windows)

```json
{
    "mcpServers": {
        "anilcancakir": {
            "command": "npx",
            "args": ["-y", "mcp-remote", "https://mcp.anilcancakir.com/"]
        }
    }
}
```

The same bridge serves any other client that only supports stdio, such as an older Codex CLI.

---

### 3. Cursor

**File:** `.cursor/mcp.json`

```json
{
    "mcpServers": {
        "anilcancakir": {
            "type": "http",
            "url": "https://mcp.anilcancakir.com/"
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
        "anilcancakir": {
            "type": "remote",
            "url": "https://mcp.anilcancakir.com/"
        }
    }
}
```

---

### 5. Codex CLI

**File:** `~/.codex/config.toml`

```toml
[mcp_servers.anilcancakir]
url = "https://mcp.anilcancakir.com/"
```

---

### 6. Antigravity CLI

**File:** `~/.gemini/config/mcp_config.json`

```json
{
    "mcpServers": {
        "anilcancakir": {
            "serverUrl": "https://mcp.anilcancakir.com/"
        }
    }
}
```

Use `serverUrl`, not `httpUrl`.

---

### 7. Gemini CLI

**File:** `~/.gemini/settings.json`

```json
{
    "mcpServers": {
        "anilcancakir": {
            "url": "https://mcp.anilcancakir.com/"
        }
    }
}
```

---

### 8. VS Code

**File:** `.vscode/mcp.json`

```json
{
    "servers": {
        "anilcancakir": {
            "type": "http",
            "url": "https://mcp.anilcancakir.com/"
        }
    }
}
```

### 9. Cline (VS Code extension)

**File:** `cline_mcp_settings.json` (the path varies by OS; on macOS it lives under `~/Library/Application Support/Code/User/globalStorage/saoudrizwan.claude-dev/settings/`).

```json
{
    "mcpServers": {
        "anilcancakir": {
            "url": "https://mcp.anilcancakir.com/"
        }
    }
}
```

### 10. Roo Code (VS Code extension)

**File:** `.roo/mcp.json` (project) or the global Roo Code MCP settings file.

```json
{
    "mcpServers": {
        "anilcancakir": {
            "url": "https://mcp.anilcancakir.com/"
        }
    }
}
```

---

## Verification

Confirm the server is reachable and lists its tools:

```bash
curl -sS -X POST https://mcp.anilcancakir.com/ \
    -H 'Accept: application/json,text/event-stream' \
    -H 'Content-Type: application/json' \
    -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
```

Expected: HTTP 200 with a `tools` array holding `list_packages`, `list_docs`, `search_docs` and `read_doc`.

---

## Troubleshooting

| Symptom | Cause | Fix |
|:--------|:------|:----|
| Tools missing after adding the config | The client cached its tool list | Restart the MCP client or reload the window |
| `mcp-remote` hangs on first start | It waits for the first MCP request | Send any request; it connects lazily |
| An unknown `package` or `version` error | The slug or series is not listed | Call `list_packages` and use its slugs and series |

For anything else, open an issue at [github.com/anilcancakir/ai/issues](https://github.com/anilcancakir/ai/issues).
