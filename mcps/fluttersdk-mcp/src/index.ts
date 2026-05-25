#!/usr/bin/env node

import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StreamableHTTPClientTransport } from "@modelcontextprotocol/sdk/client/streamableHttp.js";
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { CallToolRequestSchema, ListToolsRequestSchema, type Tool } from "@modelcontextprotocol/sdk/types.js";

const UPSTREAM_URL = process.env["FLUTTERSDK_MCP_URL"] ?? "https://mcp.fluttersdk.com/";
const ALLOW_TOOLS = process.env["BRIDGE_ALLOW_TOOLS"] ?? "search-docs";

/**
 * Filters a list of tools by the allowlist string.
 *
 * @param tools - The full tool list returned by the upstream server.
 * @param allowlist - Comma-separated tool names, or "*" for unrestricted access.
 * @returns The filtered subset of tools.
 */
export function filterTools(tools: Tool[], allowlist: string): Tool[] {
    if (allowlist.trim() === "*") {
        return tools;
    }

    const allowed = new Set(
        allowlist.split(",").map((name) => name.trim()).filter(Boolean),
    );

    return tools.filter((tool) => allowed.has(tool.name));
}

const server = new Server(
    { name: "fluttersdk-bridge", version: "1.1.0" },
    { capabilities: { tools: {} } },
);

// Lazily initialized upstream client and cached tool list.
let upstreamClient: Client | null = null;
let cachedTools: Tool[] | null = null;

async function getUpstreamClient(): Promise<Client> {
    if (upstreamClient !== null) {
        return upstreamClient;
    }

    const client = new Client({ name: "fluttersdk-bridge-client", version: "1.1.0" });
    const transport = new StreamableHTTPClientTransport(new URL(UPSTREAM_URL));
    await client.connect(transport);
    upstreamClient = client;

    return client;
}

async function getFilteredTools(): Promise<Tool[]> {
    if (cachedTools !== null) {
        return cachedTools;
    }

    const client = await getUpstreamClient();
    const result = await client.listTools();
    cachedTools = filterTools(result.tools, ALLOW_TOOLS);

    return cachedTools;
}

server.setRequestHandler(ListToolsRequestSchema, async () => {
    const tools = await getFilteredTools();
    return { tools };
});

server.setRequestHandler(CallToolRequestSchema, async (request) => {
    const tools = await getFilteredTools();
    const allowed = tools.some((tool) => tool.name === request.params.name);

    if (!allowed) {
        throw new Error(`Tool "${request.params.name}" is not available through this bridge.`);
    }

    const client = await getUpstreamClient();
    return client.callTool(request.params);
});

const transport = new StdioServerTransport();
await server.connect(transport);
