# Upstream Skill Sync Setup

## Purpose

This guide is for the maintainer wiring auto-sync between upstream skill source repos
(wind_kit, magic, dowel, tapir, crumbs and the Magic plugins) and the registry (anilcancakir/ai).
Each upstream repo needs one workflow file and one secret. Once in place, a published
release fires `repository_dispatch` to anilcancakir/ai, triggering `sync.yml` to pull the
updated skill subtree and commit it to master.

**Release-scoped on purpose.** The dispatch does not fire on ordinary pushes. It used to,
and the registry paid a version per commit for it: v1.3.75, most of those re-publishing
byte-identical skill content because a docs commit and a release commit each triggered a
sync. A skill edit now reaches users with the release that carries it. When a skill fix
cannot wait for a release, run the upstream's "Dispatch skill update to registry"
workflow manually from the Actions tab.

## One-time prerequisite (registry side)

Add these secrets to **anilcancakir/ai** (Settings → Secrets and variables → Actions):

| Secret | What it contains |
|---|---|
| `REGISTRY_BOT_APP_ID` | GitHub App ID (`anilcancakir-ai-registry`: `contents: write` + `metadata: read`, installed on `anilcancakir/ai` only) |
| `REGISTRY_BOT_PRIVATE_KEY` | Private key (PEM) for that GitHub App |

The App is installed on `anilcancakir/ai` and nowhere else. `sync.yml` mints one token
per run, scoped to this repository, for the push; the upstream repositories are public,
so their subtree is read with the default `GITHUB_TOKEN`. No personal access tokens are
used; App tokens are mint-on-demand with a 1-hour TTL and auto-expire when the job ends.

Add this **variable** (Settings → Secrets and variables → Actions → Variables tab):

| Variable | What it contains |
|---|---|
| `REGISTRY_BOT_USER_EMAIL` | Optional. Commit author email for the auto-sync bot. Format: `<bot-user-id>+anilcancakir-ai-registry[bot]@users.noreply.github.com` (bot user ID from `gh api 'users/anilcancakir-ai-registry[bot]'`). Falls back to `anilcancakir-ai-registry[bot]@users.noreply.github.com` if unset. |

The App token is used by `sync.yml` when pushing back to anilcancakir/ai. An App-token push
re-triggers `deploy-registry.yml`; a plain `GITHUB_TOKEN` push would be silently skipped.

## Per-upstream setup

Repeat for each source repo. A new source starts with one entry in
`registry-sources.json` (key = the repo name, for example `magic_sentry`):

```json
"magic_sentry": {
    "repo": "anilcancakir/magic_sentry",
    "branch": "master",
    "skill": "magic-sentry",
    "replaces": []
}
```

`replaces` lists skill directories this source supersedes; they are deleted from `skills/`
on its first sync (for example `fluttersdk-artisan` when `dowel` syncs for the first time).
A dispatch whose `source` is not a key in that file is rejected before anything is checked out.

**a. Add App secrets to the upstream repo.** Settings → Secrets → Actions → New repository secret:
- `REGISTRY_BOT_APP_ID` = same App ID as on anilcancakir/ai
- `REGISTRY_BOT_PRIVATE_KEY` = same PEM content as on anilcancakir/ai

No personal access tokens. The App is installed only on `anilcancakir/ai`; each upstream just
needs the App credentials so its workflow can mint a registry-scoped token.

**b. Copy the template workflow** from anilcancakir/ai into the upstream repo:
```bash
cp docs/templates/upstream-dispatch-template.yml \
   <upstream-repo>/.github/workflows/dispatch-to-registry.yml
```

The template lives under `docs/templates/` (not `.github/workflows/`) so GitHub does not
execute it inside anilcancakir/ai. Once copied into an upstream repo's `.github/workflows/`
directory, it becomes a live workflow there.

**c. Replace the one placeholder** in the copied file:

| Placeholder | Replace with |
|---|---|
| `<SOURCE_NAME>` | the key you added to `registry-sources.json` (`wind_kit`, `magic`, `dowel`, `tapir`, `crumbs`, `magic_<plugin>`) |

The skill path itself is not a placeholder any more: the registry resolves it from
`source` through `registry-sources.json`, and the workflow no longer filters pushes by path
because it no longer triggers on push. There is also no branch to set, for the same
reason.

**d. Commit and push** to the upstream's default branch:
```bash
git add .github/workflows/dispatch-to-registry.yml
git commit -m "chore: add registry dispatch workflow"
git push
```

## Testing

1. Go to the upstream repo's Actions tab → "Dispatch skill update to registry" → Run workflow.
2. Switch to **anilcancakir/ai** Actions and confirm `sync.yml` triggered.
3. Verify `sync.yml` commits synced files to anilcancakir/ai's master branch.
4. Confirm `deploy-registry.yml` fires automatically on that commit.

## Notes

- `client_payload` carries 3 keys (`source`, `version`, `sha`), well under the 10-property cap.
- The same GitHub App is used everywhere (registry push + registry-scoped dispatch from each
  upstream). One App, one private key, no PAT rotation. Tokens mint at job start and expire
  in 1 hour or when the job ends, whichever comes first.
- The template lives at `docs/templates/upstream-dispatch-template.yml`, outside the
  `.github/workflows/` directory, so GitHub does not load it as a workflow in anilcancakir/ai.
  It only becomes active when copied into an upstream repo's `.github/workflows/` directory.
- On a `release: published` event the checkout lands on the release tag, so `Extract version`
  reads the released `pubspec.yaml`. These packages tag without a `v` prefix, so the
  `^v[0-9]` branch of that step does not match and the pubspec fallback is the live path;
  both shapes resolve to the same string. A manual run from the default branch reads that
  branch's pubspec instead, which is what you want for an unreleased skill fix.
- `sync.yml` bumps the registry patch version on every accepted dispatch, so the registry
  version counts syncs, not upstream releases. With the release-only trigger those are now
  roughly one to one.
- **Fire manual dispatches one at a time, waiting for each sync to finish.** The
  `sync-registry` concurrency group serializes running jobs, but GitHub keeps only ONE
  pending run per group: fire four dispatches within a few seconds and the two that queue
  behind the pending one are cancelled outright, with no failure to notice. Measured on
  2026-08-03: four dispatches produced one success, one push rejection, and two silent
  cancellations. The push rejection is handled now (the sync step rebuilds on the live
  `master` and retries up to three times), but a cancelled run never starts, so nothing can
  recover it except firing again.
