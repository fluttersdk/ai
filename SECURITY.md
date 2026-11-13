# Security Policy

## Supported Versions

Only the latest registry version (the newest `vX.Y.Z` release) receives fixes.

## Reporting a Vulnerability

Report it through GitHub's private vulnerability reporting:
**[Open a private vulnerability report](https://github.com/anilcancakir/ai/security/advisories/new)**

The report stays confidential until a fix is ready. Include the affected file or workflow, how to trigger it, and the impact.

## Scope

This policy covers what the repository ships: the sync and deploy workflows, `scripts/install.sh`, the plugin manifests, the owned `flutter-review` skill and subagents, and the bundled MCP server config (`.mcp.json`). The content of a mirrored skill belongs to its source repository. Issues in a third-party tool the installer configures belong to its maintainers.
