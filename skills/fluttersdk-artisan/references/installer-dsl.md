# PluginInstaller DSL reference

Authoritative source: `lib/src/installer/plugin_installer.dart` (DSL methods), `lib/src/installer/install_operation.dart` (26 sealed variants), `lib/src/installer/install_transaction.dart:58-234` (atomic commit semantics).

The fluent `PluginInstaller` is the procedural escape hatch when `install.yaml` is insufficient: complex conditional logic, branching prompts that depend on filesystem state, custom file generation, multi-step shell flows.

## When to reach for the DSL

Use `install.yaml` when:
- The install is a fixed list of file copies + injections + permissions.
- Prompts are flat (no conditional follow-ups).
- The schema's existing sections cover every needed mutation.

Use `PluginInstaller` when:
- A prompt's answer changes which subsequent files / injections fire.
- A file's content depends on runtime conditions (existing config, env detection).
- The install needs to call into the consumer's existing code (read config, query DB).

Hybrid is supported: a plugin can ship both `install.yaml` (declarative core) and a custom `ArtisanInstallCommand` (procedural extension that runs `post_install` style work).

## Two execution phases

The DSL splits into IMMEDIATE methods (fire during the chain) and DEFERRED methods (enqueue typed `InstallOperation` until `commit()` is called).

### IMMEDIATE (run synchronously during the chain)

| Method | Purpose |
|--------|---------|
| `ask(varName, question, [defaultValue])` | Free-text prompt. Returns the answer; also stored under `_vars[varName]`. |
| `confirm(varName, question, [defaultValue])` | Yes/no prompt. Returns bool. |
| `choice(varName, question, options, [defaultValue])` | Selection from list. Returns the chosen string. |
| `startWith(hook)` | Register a `Future<void>` to run at the start of `commit()`. |
| `endWith(hook)` | Register a `Future<void>` to run at the end of `commit()`, after all ops. |

IMMEDIATE methods are the only DSL methods that return values usable in the chain. They are how a procedural installer branches: prompt first, then conditionally enqueue different DEFERRED ops.

### DEFERRED (enqueue an `InstallOperation`, fire at commit)

Categorized by concern. Each method takes typed args, returns `this` for chaining, and adds one entry to the transaction's op queue.

**Pubspec ops**:

| Method | Operation type |
|--------|----------------|
| `addDependency(name, version)` | `AddDependency` |
| `addDevDependency(name, version)` | `AddDevDependency` |
| `addPathDependency(name, path)` | `AddPathDependency` (rare; for monorepo plugins only) |
| `removeDependency(name)` | `RemoveDependency` |
| `addPubspecAsset(assetPath)` | `AddPubspecAsset` |

**File ops**:

| Method | Operation type |
|--------|----------------|
| `publishConfig(stubName, targetPath, [replacements])` | `PublishFile` |
| `writeFile(targetPath, content)` | `WriteFile` |
| `deleteFile(targetPath)` | `DeleteFile` |
| `copyFile(sourcePath, targetPath)` | `CopyFile` |
| `mergeJson(targetPath, sourceData, [additive])` | `MergeJson` |

**Code injection ops (Dart files)**:

| Method | Operation type |
|--------|----------------|
| `injectImport(targetFile, importStatement)` | `InjectImport` |
| `injectBefore(targetFile, pattern, code)` | `InjectBeforePattern` |
| `injectAfter(targetFile, pattern, code)` | `InjectAfterPattern` |
| `injectMainDartImport(importStatement)` | `InjectMainDartImport` |
| `injectBeforeMagicInit(code)` | `InjectIntoMainDart` (variant) |
| `injectAfterMagicInit(code)` | `InjectIntoMainDart` (variant) |
| `wrapRunApp(wrapperBuilder)` | `InjectIntoMainDart` (variant) |
| `injectProvider(providerClass, package)` | `InjectImport` + `InjectAfterPattern` (2 ops) |
| `injectRoute(routesFile, registration)` | `InjectRouteRegistration` |

**Android ops** (mutate `android/app/src/main/AndroidManifest.xml` and `android/app/build.gradle`):

| Method | Operation type |
|--------|----------------|
| `injectAndroidPermission(permission)` | `InjectAndroidPermission` |
| `injectAndroidMetaData(name, value)` | `InjectAndroidMetaData` |
| `injectGradlePlugin(id, [version])` | `InjectGradlePlugin` |
| `injectGradleDependency(scope, notation)` | `InjectGradleDependency` |

**iOS / macOS ops** (mutate `Info.plist`, entitlements, `Podfile`):

| Method | Operation type |
|--------|----------------|
| `injectInfoPlistKey(platform, key, value)` | `InjectInfoPlistKey` |
| `injectEntitlement(platform, key, value)` | `InjectEntitlement` |
| `injectPodfileLine(platform, line)` | `InjectPodfileLine` |

**Web ops** (mutate `web/index.html`):

| Method | Operation type |
|--------|----------------|
| `injectIntoWebHead(html)` | `InjectIntoWebHead` |
| `addWebMetaTag(name, content)` | `AddWebMetaTag` |

**Env op** (mutate `.env`):

| Method | Operation type |
|--------|----------------|
| `injectEnvVar(name, defaultValue, [comment])` | `InjectEnvVar` |

**Shell ops** (run external commands):

| Method | Operation type |
|--------|----------------|
| `runShell(cmd, args, [workingDir])` | `RunShell` (unconditional) |
| `askToRunShell(prompt, cmd, args, [workingDir])` | Prompts IMMEDIATELY, enqueues `RunShell` only when user confirms |

Total: 26 sealed `InstallOperation` variants.

## Atomic commit

`commit({dryRun: false, force: false})` walks the transaction in five phases:

1. **Prepare**: walk every enqueued op, resolve relative paths, validate target file existence preconditions.
2. **Pre-flight checks**: idempotency probes (does this `injectImport` already match the file's existing content?). Skip already-applied ops.
3. **Helper-write phase**: ops that delegate to in-place editors (`ConfigEditor`, `MainDartEditor`, `XmlEditor`, `PlistWriter`, `GradleEditor`, `PodfileEditor`, `EnvEditor`, `HtmlEditor`, `RouteRegistryEditor`) commit synchronously. These bypass the atomic stage because helpers do their own validation. Track helper-written paths in `_helperWrittenTargets` so subsequent runs detect "unmanaged" files correctly.
4. **Atomic stage**: every `WriteFile` / `DeleteFile` / `CopyFile` / `PublishFile` / `MergeJson` stages writes to `<absPath>.tmp`. Throws on any single failure: delete all staged `.tmp` files, return `Error(rolledBack: true)`.
5. **Atomic rename**: every `.tmp` renames over the target. POSIX rename boundary. If a rename fails mid-batch, prior renames stick (cannot roll back across the boundary); return `Error(rolledBack: false)`.

One-shot guard: `_committed` flips true on the first `commit` call. Subsequent calls throw `StateError`. Replay requires a fresh installer instance.

`dryRun: true`: walk phases 1 + 2 only, print the operation list with target paths, commit nothing.

`force: true`: bypass idempotency checks in phase 2, overwrite existing files.

## ArtisanInstallCommand skeleton

A plugin ships a custom installer by extending `ArtisanInstallCommand` and overriding `installCommand()`:

```dart
import 'package:fluttersdk_artisan/artisan.dart';

final class MyPluginInstallCommand extends ArtisanInstallCommand {
  @override
  String get name => 'my_plugin:install';

  @override
  String get description => 'Install my_plugin into the consumer project.';

  @override
  Future<void> installCommand(PluginInstaller installer, ArtisanContext ctx) async {
    // IMMEDIATE: prompt the user
    final apiUrl = installer.ask('apiUrl', 'API base URL?', 'https://api.example.com');
    final useCache = installer.confirm('useCache', 'Enable response cache?', true);
    final transport = installer.choice('transport', 'Transport layer?', ['rest', 'graphql'], 'rest');

    // DEFERRED: enqueue ops based on the answers
    installer
      ..addDependency('dio', '^5.0.0')
      ..publishConfig('install/my_plugin_config.dart.stub', 'lib/config/my_plugin.dart', {
        'apiUrl': apiUrl,
        'useCache': useCache.toString(),
        'transport': transport,
      })
      ..injectImport('lib/config/app.dart', "import '../config/my_plugin.dart';")
      ..injectProvider('MyPluginServiceProvider', 'my_plugin')
      ..injectEnvVar('MY_PLUGIN_API_URL', apiUrl)
      ..injectAndroidPermission('android.permission.INTERNET');

    if (useCache) {
      installer.addDependency('hive', '^4.0.0');
    }

    if (transport == 'graphql') {
      installer.addDependency('graphql_flutter', '^5.0.0');
    }

    // Optional: run a shell command after commit
    installer.askToRunShell(
      'Run pub get now?',
      'flutter',
      ['pub', 'get'],
    );
  }
}
```

The framework calls `commit()` automatically after `installCommand()` returns. The plugin author does not manage transaction lifecycle.

## Idempotency

The 26 op variants each handle their own idempotency:

- `AddDependency` / `AddDevDependency` use `ConfigEditor.addDependencyToPubspec` which detects "already present" by parsing the YAML and early-returning when the version matches.
- `InjectImport` early-returns when `content.contains(importStatement)`.
- `InjectAfterPattern` / `InjectBeforePattern` early-return when `content.contains(code.trim())`.
- `InjectAndroidPermission` parses AndroidManifest.xml as XML DOM, checks for an existing `<uses-permission>` with the same `android:name`, no-ops on match.
- `InjectGradlePlugin` regex-matches existing plugins block, no-ops when id matches.
- `WriteFile` / `CopyFile` / `PublishFile` compare existing content to the new content via SHA-256; no-op on equality. With `--force`, overwrites unconditionally.
- `MergeJson` deep-compare with additive mode preserves existing keys; no-op when the source is a subset.

Net effect: running the same installer twice produces zero second-run mutations. Plugin authors do not need to guard against re-runs.

## Reversibility (V1)

`InstallTransaction` records every op to `.artisan/installed/<plugin>.json` (op type + target path + content hash for verification). `plugin:uninstall` walks the record in reverse:

- `WriteFile` / `PublishFile` -> `DeleteFile` (with tamper-check via the recorded hash; refuses to delete when the file has been edited since install)
- `DeleteFile` -> not reversible (original content not preserved)
- `CopyFile` -> `DeleteFile` on the target
- `AddDependency` / `AddDevDependency` / `AddPathDependency` -> `RemoveDependency`
- `RemoveDependency` -> not reversible
- All `Inject*` ops -> `[skipped]` warning (V1 limitation; anchor-bracketed reverse pending V1.1)
- `MergeJson`, `AddPubspecAsset`, `RunShell` -> `[skipped]` warning

Run `plugin:uninstall <name> --dry-run` first to preview the reverse plan and identify any `[skipped]` ops that need manual cleanup.

## Indentation contract

Two specific helper methods produce code that goes into auto-generated lists, and their indentation is part of the contract because it must match the surrounding generated scaffold:

- `injectProvider(providerClass, package)` emits `      (app) => <ProviderClass>(app),` with 6-space indent (matches the `providers:` block format that `install` writes).
- `injectConfigFactory(factoryName)` emits `      () => <factoryName>,` with 6-space indent.

Changing the indent breaks layout for every consumer that ran `install` before the change. The indent is hard-coded; do not parametrize.

## Helper-vs-staged ops

Helpers (`ConfigEditor`, `MainDartEditor`, `XmlEditor`, `PlistWriter`, `GradleEditor`, `PodfileEditor`, `EnvEditor`, `HtmlEditor`, `RouteRegistryEditor`) bypass the atomic stage because they perform their own in-place validation. The trade-off in V1:

- Helpers commit synchronously during phase 3. If phase 4 or 5 fails afterward, helper edits already on disk are NOT rolled back.
- For plugin authors, this means: an `injectAndroidPermission` may apply even when a later `writeFile` fails the atomic stage.
- The transaction record still logs the helper op so `plugin:uninstall` can reverse it (when the op type supports reverse).

Plugin authors who need full all-or-nothing semantics should keep file writes in `writeFile` / `publishConfig` (atomic) and reserve helpers for the less-critical mutations.
