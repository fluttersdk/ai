# CLI command reference

Per-command flags, defaults, output format, and exit codes for the 6
`telescope:*` CLI commands. Two invocation forms reach the same code
path:

- `./bin/fsa telescope:<cmd> [flags]` (native AOT, ~110ms warm) is the
  default after `telescope:install` has scaffolded the wrapper.
- `dart run fluttersdk_telescope telescope:<cmd> [flags]` (~3s cold)
  works without prior install; this is how `telescope:install` itself
  runs the first time.

All read commands boot in `connected` mode: they attach to the running
app's VM Service before issuing the extension call, and fail with "VM
Service URI absent" if the app is not running. Output is always
human-readable (formatted lines), never JSON. Prefer the MCP tools when
the agent needs structured data.

## Contents

- [`telescope:install`](#telescopeinstall)
- [`telescope:tail`](#telescopetail)
- [`telescope:requests`](#telescoperequests)
- [`telescope:queries`](#telescopequeries)
- [`telescope:caches`](#telescopecaches)
- [`telescope:clear`](#telescopeclear)
- [Why some buffers are MCP-only](#why-some-buffers-are-mcp-only)
- [Common output behaviour](#common-output-behaviour)

---

## telescope:install

Bootstrap telescope in a consumer Flutter app. Idempotent: safe to
re-run.

**Flags:** none.

**What it does (3 steps):**

1. `dart run fluttersdk_artisan install` scaffolds `bin/dispatcher.dart`,
   `bin/fsa`, and `lib/app/_plugins.g.dart` (skipped when the wrapper
   already exists).
2. `./bin/fsa plugin:install fluttersdk_telescope` registers the
   plugin in `.artisan/plugins.json` and regenerates
   `lib/app/_plugins.g.dart`.
3. Patches `lib/main.dart` via `MainDartEditor`:
   - Adds imports for `kDebugMode` and `package:fluttersdk_telescope/telescope.dart`.
   - Injects a `kDebugMode` block before `await Magic.init(` (Magic
     apps) or `runApp(` (vanilla) with:
     ```dart
     TelescopePlugin.install();
     TelescopePlugin.registerWatcher(ExceptionWatcher());
     TelescopePlugin.registerWatcher(DumpWatcher());
     ```
   - When pubspec contains `magic_devtools:` (as a dependency or
     dev_dependency) and `lib/main.dart` contains `await Magic.init(`,
     also injects `import 'package:magic_devtools/telescope.dart';`
     plus `MagicTelescopeIntegration.install();` inside a second
     `kDebugMode` block after `Magic.init()` completes.

All three sub-steps check for a string anchor before inserting, so the
command is idempotent.

**Output:** human-readable status lines (info / success / error).

**Exit codes:** `0` on success. Non-zero only when an inner subprocess
(artisan install or plugin install) fails.

**Example:**

```bash
$ dart run fluttersdk_telescope telescope:install
[info] Scaffolding bin/dispatcher.dart, bin/fsa, lib/app/_plugins.g.dart...
[ok]   Wrapper ready.
[info] Registering fluttersdk_telescope plugin...
[ok]   Plugin registered.
[info] Patching lib/main.dart...
[ok]   TelescopePlugin.install() injected before await Magic.init(...).
[ok]   import 'package:magic_devtools/telescope.dart' injected.
[ok]   MagicTelescopeIntegration.install() injected after Magic.init(...).
[ok]   Done.
```

---

## telescope:tail

Print recent log records.

**Flags:**

| Flag | Default | Help |
|---|---|---|
| `--level=<NAME>` | (none, no filter) | Minimum-threshold filter, accepts `info`, `warning`, `severe`, `shout`, `fine`, etc. |
| `--limit=<N>` | `50` | Max records to print (most-recent N from the buffer). |

**VM extension:** `ext.telescope.console`.

**Output format:** one line per record:

```
2026-05-25T09:14:22.318Z [WARNING] UserController: User 42 reload returned no data
```

**Empty-buffer hint:** `"No log records."` (warning style, exit 0).

**Exit codes:** always `0` (success or empty).

**Example:**

```bash
./bin/fsa telescope:tail --level=warning --limit=20
```

---

## telescope:requests

Print recent HTTP records.

**Flags:**

| Flag | Default | Help |
|---|---|---|
| `--limit=<N>` | `50` | Max records to print. |

**VM extension:** `ext.telescope.requests`.

**Output format:**

```
2026-05-25T09:14:22.318Z GET https://api.example.test/users -> 200 (184ms)
2026-05-25T09:14:23.121Z POST https://api.example.test/users -> 422 (97ms)
```

**Empty-buffer hint:** `"No HTTP records (register a TelescopeHttpAdapter)."`

**Exit codes:** always `0`.

**Example:**

```bash
./bin/fsa telescope:requests --limit=10
```

---

## telescope:queries

Print recent DB queries.

**Flags:**

| Flag | Default | Help |
|---|---|---|
| `--limit=<N>` | `50` | Max records to print. |

**VM extension:** `ext.telescope.queries`.

**Output format:**

```
2026-05-25T09:14:22.318Z [default] SELECT * FROM users WHERE team_id = ? bindings=[team_3] (4ms)
```

**Empty-buffer hint:** `"No DB query records (register MagicQueryWatcher)."`

**Exit codes:** always `0`.

---

## telescope:caches

Print recent Magic Cache operations.

**Flags:**

| Flag | Default | Help |
|---|---|---|
| `--limit=<N>` | `50` | Max records to print. |

**VM extension:** `ext.telescope.caches`.

**Output format:**

```
2026-05-25T09:14:22.318Z [hit] team:3:users ttl=300000ms
2026-05-25T09:14:25.812Z [miss] user:7:profile
```

**Empty-buffer hint:** `"No cache records (register MagicCacheWatcher)."`

**Exit codes:** always `0`.

Note: the buffer is currently a placeholder, see the cache section in
`mcp-tools.md`.

---

## telescope:clear

Wipe all 9 ring buffers atomically.

**Flags:** none.

**VM extension:** `ext.telescope.clear`.

**Output:**

```
Cleared telescope buffers.
```

**Exit codes:** always `0`. Idempotent.

---

## Why some buffers are MCP-only

V1 ships 6 CLI commands and 9 MCP tools. The four buffers without a
CLI mirror (`exceptions`, `events`, `gates`, `dumps`) are MCP-only by
intent: their records are dense JSON objects (stack traces, payload
maps, arguments lists) that do not pretty-print well into a single
line, and the agent-driving use-case demanded structured access first.

CLI parity for those four is V1.x backlog. To read them from a shell,
use a Dart one-liner that calls the VM extension directly, or pipe the
MCP server output through a client like
`fluttersdk_artisan mcp:invoke`.

---

## Common output behaviour

- **Boot mode `connected`:** all read commands wait for the running
  app's VM Service before issuing the extension call. If the app is
  not running, the command exits with a "VM Service URI absent" error
  and a non-zero status from the substrate wrapper.

- **Always exit 0 on read commands:** even with an empty buffer or a
  hint message; the human-facing wording signals the cause. Scripting
  against an empty buffer must grep the output, not the exit code.

- **No JSON output.** Use the MCP tools when the agent needs
  structured data. The CLI is for the human at the keyboard or for
  one-shot inspection.

- **Stale AOT recovery.** If `./bin/fsa telescope:<cmd>` deadlocks on
  the lock file, run `rm -rf .artisan/.fsa.lock && ./bin/fsa list` to
  reclaim. The lock is PID-aware in current builds and should not
  normally need manual intervention.

- **Fallback when AOT is broken.** `dart run fluttersdk_telescope
  telescope:<cmd>` reaches the same providers but boots in ~3s
  instead of ~110ms; use it during install or when the AOT bundle is
  stale.
