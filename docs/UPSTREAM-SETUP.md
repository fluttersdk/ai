# Upstream Skill Sync Setup

## Purpose

This guide is for the maintainer wiring auto-sync between upstream skill source repos
(fluttersdk/wind, magic, dusk, telescope, artisan) and the registry (fluttersdk/ai).
Each upstream repo needs one workflow file and one secret. Once in place, any push to a
skill path or a new release fires `repository_dispatch` to fluttersdk/ai, triggering
`sync.yml` to pull updated files and commit them to main.

## One-time prerequisite (registry side)

Add these secrets to **fluttersdk/ai** (Settings → Secrets and variables → Actions):

| Secret | What it contains |
|---|---|
| `REGISTRY_BOT_APP_ID` | GitHub App ID; App must have `contents: write` on fluttersdk/ai only |
| `REGISTRY_BOT_PRIVATE_KEY` | Private key (PEM) for that GitHub App |
| `UPSTREAM_READ_PAT` | Fine-grained PAT with `contents: read` on all 5 upstream repos |

The App token is used by `sync.yml` when pushing back to fluttersdk/ai. An App-token push
re-triggers `deploy-registry.yml`; a plain `GITHUB_TOKEN` push would be silently skipped.

## Per-upstream setup

Repeat for each of: **wind, magic, dusk, telescope, artisan**.

**a. Create a fine-grained PAT** scoped to **fluttersdk/ai** with `metadata: read` and
`contents: write` (required by peter-evans/repository-dispatch v4 to fire `repository_dispatch`).

**b. Add secret to the upstream repo.** Settings → Secrets → Actions → New repository secret:
`REGISTRY_DISPATCH_PAT` = the PAT above. Each upstream gets its own independent PAT; never
share one across all five repos.

**c. Copy the template workflow** from fluttersdk/ai into the upstream repo:
```bash
cp .github/workflows/upstream-dispatch-template.yml \
   <upstream-repo>/.github/workflows/dispatch-to-registry.yml
```

**d. Replace placeholders** in the copied file:

| Placeholder | Replace with |
|---|---|
| `<SOURCE_NAME>` | `wind` / `magic` / `dusk` / `telescope` / `artisan` |
| `<SKILL_PATH>` | `fluttersdk_wind/skills/wind-ui` (wind), `skills/magic-framework` (magic), `skills/fluttersdk-dusk` (dusk), `skills/fluttersdk-telescope` (telescope), `skills/fluttersdk-artisan` (artisan) |

**e. Set the real default branch.** Change `branches: ["never-trigger-in-registry"]` to
`branches: ["main"]` (or `"master"`) in the copied file.

**f. Commit and push** to the upstream's default branch:
```bash
git add .github/workflows/dispatch-to-registry.yml
git commit -m "chore: add registry dispatch workflow"
git push
```

## Testing

1. Go to the upstream repo's Actions tab → "Dispatch skill update to registry" → Run workflow.
2. Switch to **fluttersdk/ai** Actions and confirm `sync.yml` triggered.
3. Verify `sync.yml` commits synced files to fluttersdk/ai's main branch.
4. Confirm `deploy-registry.yml` fires automatically on that commit.

## Notes

- `client_payload` carries 3 keys (`source`, `version`, `sha`), well under the 10-property cap.
- PAT is acceptable for the upstream-to-registry trigger (least privilege); rotate every 90 days.
  The App token is registry-side only (used by `sync.yml` to push with attribution).
- This template file does not fire in fluttersdk/ai because the branch
  `never-trigger-in-registry` does not exist in this repo.
