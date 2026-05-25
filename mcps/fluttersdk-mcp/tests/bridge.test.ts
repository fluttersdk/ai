import { describe, it, expect } from "vitest";
import { filterTools } from "../src/index.js";
import type { Tool } from "@modelcontextprotocol/sdk/types.js";

const MOCK_TOOLS: Tool[] = [
    {
        name: "search-docs",
        description: "Search FlutterSDK documentation",
        inputSchema: {
            type: "object",
            properties: {
                queries: { type: "array", items: { type: "string" } },
            },
            required: ["queries"],
        },
    },
    {
        name: "other-tool",
        description: "Some other tool",
        inputSchema: { type: "object" },
    },
];

describe("filterTools", () => {
    it("returns only search-docs when BRIDGE_ALLOW_TOOLS is unset (default allowlist)", () => {
        const result = filterTools(MOCK_TOOLS, "search-docs");

        expect(result).toHaveLength(1);
        expect(result[0]!.name).toBe("search-docs");
    });

    it("returns all tools when BRIDGE_ALLOW_TOOLS is *", () => {
        const result = filterTools(MOCK_TOOLS, "*");

        expect(result).toHaveLength(2);
        expect(result.map((t) => t.name)).toEqual(["search-docs", "other-tool"]);
    });
});
