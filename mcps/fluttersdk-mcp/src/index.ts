#!/usr/bin/env node

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";

const server = new McpServer({
    name: "fluttersdk",
    version: "1.0.0",
});

/**
 * Ping tool — verifies the MCP server is running.
 */
server.tool(
    "ping",
    { message: z.string().optional() },
    async ({ message }) => {
        return {
            content: [
                {
                    type: "text",
                    text: message
                        ? `pong: ${message}`
                        : "pong",
                },
            ],
        };
    },
);

const transport = new StdioServerTransport();
await server.connect(transport);
