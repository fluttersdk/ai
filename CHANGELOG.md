# Changelog

All notable changes to what this repository itself ships are recorded here. Mirrored skills and the plugin version triplet change through automated sync commits and GitHub Releases (`vX.Y.Z`), not through this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Changed

- **`magic_starter` syncs from `master`.** The starter repository renamed its default branch from `main` to `master`, so its `registry-sources.json` entry names `master`.
- **The registry moved to `anilcancakir/ai` and its default branch is `master`.** Install with `npx skills add anilcancakir/ai`. The Claude Code plugin is `anilcancakir` and the marketplace `anilcancakir-marketplace`, so skills are `/anilcancakir:<skill>` and the subagents `anilcancakir:flutter-reviewer` and `anilcancakir:flutter-reviewer-deep`. Remove the old `fluttersdk-marketplace` and add the new one. Pages moved to `https://anilcancakir.github.io/ai/`.
- **`sync.yml` is data-driven.** The allowed sources (repo, branch, skill directory, replaced skills) live in `registry-sources.json`; a dispatch whose source is not listed there is rejected before anything is checked out. Upstream repositories are read with the default token, and one App token (`anilcancakir-ai-registry`) writes to the registry. A source's `replaces` entries leave `skills/` and `skills/index.json` on its first sync.
- **CI follows the repo standard.** Every action is pinned by commit SHA, `ci.yml` has no `paths:` filter and ends in the `Lint & Test` aggregator, and a `Changelog` workflow asks for an entry when shipped files change.
- **The README, `CLAUDE.md` and the issue and pull request templates were rewritten** for the new names, the standard layout and the For AI coding agents rules.
- **The bundled MCP server is `https://mcp.anilcancakir.com/`.** `.mcp.json` (loaded with the Claude Code plugin) no longer points at `mcp.fluttersdk.com`; its server key is `anilcancakir` and it serves the read-only docs of the packages on anilcancakir.com (`list_packages`, `list_docs`, `search_docs`, `read_doc`). `scripts/install.sh --with-mcp` writes the same URL and key for every tool, and `docs/MCP.md` is rewritten around the new tools. Clients that only speak stdio use `npx -y mcp-remote https://mcp.anilcancakir.com/`.

### Added

- `registry-sources.json`, `SECURITY.md`, this changelog, a pull request template and issue forms.

### Removed

- The VS Code Copilot instruction file (`.github/copilot-instructions.md`) and the Copilot step of `scripts/install.sh`; VS Code keeps its MCP config target.
- **The `@fluttersdk/mcp` stdio bridge:** `mcps/fluttersdk-mcp/`, its npm publish workflow (`publish-mcp.yml`), the Dependabot npm entry, `server.json` and the `MCP bridge (build + test)` CI job. The npm package stays on the registry, unmaintained; stdio clients use `mcp-remote`.

### Fixed

- `scripts/update-skill-index.mjs` removes the entries of replaced skills (`REPLACES`), so a retired skill no longer stays in the OpenCode index with files that return 404.
