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
| `REGISTRY_BOT_APP_ID` | GitHub App ID (App `contents: write` + `metadata: read` on org repos) |
| `REGISTRY_BOT_PRIVATE_KEY` | Private key (PEM) for that GitHub App |

The same App handles both registry push AND upstream read; `sync.yml` mints two
separate tokens per run, each scoped to the specific repo (registry-ai for push,
the upstream repo for sparse-checkout). No personal access tokens are used; App
tokens are mint-on-demand with a 1-hour TTL and auto-expire when the job ends.

Add this **variable** (Settings → Secrets and variables → Actions → Variables tab):

| Variable | What it contains |
|---|---|
| `REGISTRY_BOT_USER_EMAIL` | Optional. Commit author email for the auto-sync bot. Format: `<bot-user-id>+fluttersdk-registry[bot]@users.noreply.github.com` (bot user ID from `gh api 'users/fluttersdk-registry[bot]'`). Falls back to `fluttersdk-registry[bot]@users.noreply.github.com` if unset. |

The App token is used by `sync.yml` when pushing back to fluttersdk/ai. An App-token push
re-triggers `deploy-registry.yml`; a plain `GITHUB_TOKEN` push would be silently skipped.

## Per-upstream setup

Repeat for each of: **wind, magic, dusk, telescope, artisan**.

**a. Add App secrets to the upstream repo.** Settings → Secrets → Actions → New repository secret:
- `REGISTRY_BOT_APP_ID` = same App ID as on fluttersdk/ai
- `REGISTRY_BOT_PRIVATE_KEY` = same PEM content as on fluttersdk/ai

No personal access tokens. The App is already installed on the org with the right permissions;
each upstream just needs the App credentials so its workflow can mint a registry-scoped token.

**b. Copy the template workflow** from fluttersdk/ai into the upstream repo:
```bash
cp docs/templates/upstream-dispatch-template.yml \
   <upstream-repo>/.github/workflows/dispatch-to-registry.yml
```

The template lives under `docs/templates/` (not `.github/workflows/`) so GitHub does not
execute it inside fluttersdk/ai. Once copied into an upstream repo's `.github/workflows/`
directory, it becomes a live workflow there.

**c. Replace placeholders** in the copied file:

| Placeholder | Replace with |
|---|---|
| `<SOURCE_NAME>` | `wind` / `magic` / `dusk` / `telescope` / `artisan` |
| `<SKILL_PATH>` | `fluttersdk_wind/skills/wind-ui` (wind), `skills/magic-framework` (magic), `skills/fluttersdk-dusk` (dusk), `skills/fluttersdk-telescope` (telescope), `skills/fluttersdk-artisan` (artisan) |

**d. Set the real default branch.** Change `branches: ["never-trigger-in-registry"]` to
`branches: ["main"]` (or `"master"`) in the copied file.

**e. Commit and push** to the upstream's default branch:
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
- The same GitHub App is used everywhere (registry push + registry-scoped dispatch from each
  upstream). One App, one private key, no PAT rotation. Tokens mint at job start and expire
  in 1 hour or when the job ends, whichever comes first.
- The template lives at `docs/templates/upstream-dispatch-template.yml`, outside the
  `.github/workflows/` directory, so GitHub does not load it as a workflow in fluttersdk/ai.
  It only becomes active when copied into an upstream repo's `.github/workflows/` directory.
