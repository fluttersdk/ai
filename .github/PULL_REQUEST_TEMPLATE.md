## What

-

## Why

-

## Testing

- [ ] `actionlint .github/workflows/*.yml` is clean and the JSON files parse (`jq empty`)
- [ ] `bash -n scripts/install.sh` passes when the installer changed; the MCP bridge tests pass when `mcps/` changed
- [ ] `CHANGELOG.md` has an entry under `[Unreleased]` (or the `skip-changelog` label fits)
- [ ] README, `docs/`, `registry-sources.json` and `CLAUDE.md` match the change
- [ ] No mirrored `skills/<name>/` file was edited by hand (edit the source repo)
