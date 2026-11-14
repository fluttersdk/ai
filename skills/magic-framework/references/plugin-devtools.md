<!-- magic_devtools v1.0.0 | Updated: 2026-11-14 -->

# magic_devtools Plugin

Debug-only adapter layer that wires Magic's runtime into `tapir` (LLM-agent E2E driver) and `crumbs` (runtime inspector), plus the performance data path and a dev-only component preview catalog. Enriches tapir snapshots and crumbs records with Magic context (forms, navigation, controllers, gates, auth, broadcasting, HTTP) so an agent sees the app the way Magic sees it.

Lives outside `magic` core on purpose: the framework keeps no dev-tooling dependency in a production build.

## Installation

The one-step path, from a project that already has magic installed:

```bash
dart run magic:dowel magic:install --with-devtools
```

That adds `magic_devtools ^1.0.0`, `tapir ^1.0.0` and `crumbs ^1.0.0` to `dependencies` and wires `lib/main.dart` under `!kReleaseMode` (debug and profile builds carry the tools, so a perf measurement runs on a profile build; release tree-shakes them): the imports of `package:flutter/foundation.dart` (`show kReleaseMode`), `package:crumbs/crumbs.dart`, `package:magic_devtools/crumbs.dart`, `package:magic_devtools/magic_devtools.dart`, `package:magic_devtools/tapir.dart` and `package:tapir/tapir.dart`; BEFORE `Magic.init(` it calls `TapirPlugin.install()`, `CrumbsPlugin.install()`, `CrumbsPlugin.registerWatcher(ExceptionWatcher())`, `CrumbsPlugin.registerWatcher(DumpWatcher())` and `MagicPerfIntegration.install()`; AFTER it, `MagicCrumbsIntegration.install()` then `MagicTapirIntegration.install()`. Call presence decides what is written: an app already calling `MagicDevtools.installPre(` is left untouched, and a block whose call (`TapirPlugin.install(`, `CrumbsPlugin.install(`, `MagicPerfIntegration.install(`, `MagicTapirIntegration.install(`, `MagicCrumbsIntegration.install(`) is already in `lib/main.dart` is not written again, so a re-run or hand wiring never duplicates a watcher. It writes `MagicPerfIntegration`, so the perf path is wired, but not the `MagicDevtools` umbrella: `MagicDevtools.installPre()` / `installPost()` is the alternative to this wiring, never mixed with it.

The manual path, when the app is already installed and only the tooling is being added:

```yaml
dependencies:
  magic_devtools: ^1.0.0
  tapir: ^1.0.0   # add if you use tapir
  crumbs: ^1.0.0  # add if you use crumbs
```

`magic_devtools` declares `tapir ^1.0.0` and `crumbs ^1.0.0`, beside `magic ^1.0.0`, `magic_socket ^1.0.0` and `wind_kit ^1.12.0`, so the lines above match its own floors. It depends on `magic`, `tapir` and `crumbs` directly, so the tools resolve through it rather than transitively through `magic`.

These are regular `dependencies`, not `dev_dependencies`: `lib/main.dart` imports them, so a `dev_dependencies` entry trips the `depend_on_referenced_packages` lint. The `!kReleaseMode` guard is what keeps them out of a release build, not the dependency section.

Then wire the CLI side of each tool:

```bash
flutter pub get
dart run magic:dowel plugin:install tapir
dart run magic:dowel plugin:install crumbs
dart run magic:dowel tapir:install
dart run magic:dowel crumbs:install
dart run magic:dowel mcp:install          # surfaces the tapir_* / crumbs_* MCP tools
```

`tapir:install` and `crumbs:install` write single-tool blocks into `lib/main.dart` when `magic_devtools` is a dependency, and each skips a block whose `TapirPlugin.install(` / `CrumbsPlugin.install(` call is already in the file, so running them after `--with-devtools` writes nothing twice. On their own they write neither `MagicDevtools` nor `MagicPerfIntegration`, so an app wired only by these two installers gets the all-zero perf report. An app that calls `MagicDevtools.installPre()` does not need them.

## Wiring: two phases that straddle `Magic.init()`

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kReleaseMode) MagicDevtools.installPre();

  await Magic.init(configFactories: [...]);

  if (!kReleaseMode) MagicDevtools.installPost();

  runApp(const MyApp());
}
```

| Call | Runs | What it does |
|:-----|:-----|:-------------|
| `MagicDevtools.installPre()` | BEFORE `Magic.init()` | `TapirPlugin.install()` + `CrumbsPlugin.install()`, then registers crumbs' opt-in `ExceptionWatcher` and `DumpWatcher` once (a second call adds none), then `MagicPerfIntegration.install()`. Must be first so the snapshot pipeline and the exception watcher are live while Magic boots, capturing boot-time errors and the first route resolve. |
| `MagicDevtools.installPost()` | AFTER `Magic.init()` | `MagicCrumbsIntegration.install()` (5 Magic watchers + `MagicHttpFacadeAdapter`, and it assigns tapir's `pendingHttpCountReader`, `recentLogsReader` and `recentExceptionsReader` to read crumbs) and `MagicTapirIntegration.install()` (14 Magic-aware snapshot enrichers, three of which read `CrumbsStore`, + the `MagicRouter` navigate adapter). Must be last because every one of those resolves dependencies through the IoC container. |

Both halves are idempotent, so a second call in the same isolate is safe: `installPre()` keeps the pair of watchers it registered and adds none on a second call (a second pair would record every exception and `debugPrint` twice). `installPre()` is NOT safe to call LATE, though: the perf integration registers a `NavigatorObserver`, and `MagicRouter.addObserver` throws a `StateError` once the router has been built. A host that installs behind a lazy debug toggle after `runApp` crashes instead of getting a harmless no-op. The throw is deliberate: a silently unregistered observer would produce a performance report with no route transitions and nothing to explain their absence.

`MagicDevtools.resetForTesting()` is test-only: it uninstalls the two watchers `installPre()` registered (restoring `FlutterError.onError`, the platform error callback and `debugPrint`) so the next `installPre()` registers a pair again.

> [!WARNING]
> Keep `!kReleaseMode` at the CALL SITE. Moving the guard inside `installPre` / `installPost` makes the call live in release, which defeats the tree-shake and pulls tapir plus crumbs into the production bundle. That tree-shake is the entire reason this package exists separately from magic core.

## The four import barrels

| Barrel | Entry point | Reach for it when |
|:-------|:------------|:------------------|
| `package:magic_devtools/magic_devtools.dart` | `MagicDevtools` | Default. Both tools, standard watcher set, two calls. |
| `package:magic_devtools/tapir.dart` | `MagicTapirIntegration` | Tapir only, without crumbs. |
| `package:magic_devtools/crumbs.dart` | `MagicCrumbsIntegration` | Crumbs only, or a non-standard watcher set (register extras with `CrumbsPlugin.registerWatcher` after `installPre`). |
| `package:magic_devtools/preview.dart` | `MagicPreview` | Hosting the component preview catalog. |

Single-tool wiring keeps the same pre/post split:

```dart
if (!kReleaseMode) TapirPlugin.install();
await Magic.init(configFactories: [...]);
if (!kReleaseMode) MagicTapirIntegration.install();
```

## MagicPerfIntegration: the performance data path

The one assembly point for performance diagnostics, because it is the only place tapir, crumbs, wind and magic are visible at once. Tapir's frozen dependency contract forbids it from importing any of the packages whose data it reports, so it declares function pointers with no-op defaults and someone else has to assign them. That someone is this class.

`MagicDevtools.installPre()` installs it, and so does `magic:install --with-devtools` (it writes `MagicPerfIntegration.install()` before `Magic.init(`). There is nothing else to wire.

| What it touches | Package | Why |
|:----------------|:--------|:----|
| `MagicPerfHooks.sink` | magic | Set only for an attribution session: counts notifies by controller and cause, query reloads, actions, event dispatches, casts, timer ticks and broadcasts, each linked to the tapir interaction open at the time. |
| `MagicRouter.addObserver` | magic | A `NavigatorObserver` that times each route push to the first post-frame callback after the new route builds. Last 200 transitions retained. |
| `Wind.installPerfResolver()` | wind | Arms `WindPerfCounters` (parse-path and class-cache counts). Counting stays OFF until a session begins. |
| `CrumbsPlugin.registerWatcher(FramePerfWatcher())` | crumbs | Frame timings into crumbs' frame buffer. |
| `framePerfReader`, `perfExtrasReader`, `perfSessionBeginHook`, `perfSessionEndHook`, `perfTimelineReader`, `perfInsightContributors` | tapir | The pointers tapir reads all of the above through: frames, magic counters, session start (with its mode) and end, the trace rows, and the wind and magic insight rules. |

| API | Signature | Notes |
|:----|:----------|:------|
| `MagicPerfIntegration.install()` | `static void` | Idempotent. Called for you by `installPre()`. |
| `MagicPerfIntegration.controllerNotifyCounts` | `Map<String, int>` | Notifies per controller type since the last session began. |
| `MagicPerfIntegration.routeTransitions` | `List<Map<String, Object?>>` | The retained transitions, most recent last. |

Session scoping is the part that surprises people: `perfSessionBeginHook` resets wind's counters, clears crumbs' frame buffer (`clearFramePerf()`, never `clear()`, which would wipe the HTTP and log buffers a developer may be reading) and clears the controller and route counters. Without that reset every session would report the sum of all previous ones. `perfSessionEndHook` turns counting off but leaves the totals intact, because `perf_end` reads them to build its report.

## MagicPreview: the component preview catalog

A dev-only catalog served from two routes, `/preview` (first entry) and `/preview/:component` (entry by slug). The sidebar lists every registered entry, only the selected one is mounted, and the header carries a light/dark toggle bound to wind's `WindThemeController`.

The entries come from codegen: `dart run magic:dowel make:component` scaffolds a `*.preview.dart` file per component and `dart run magic:dowel previews:refresh` collects them into `lib/_previews.g.dart`, which exposes `previewEntries()` returning a `List<PreviewEntry>`.

```dart
// lib/app/providers/route_service_provider.dart
@override
Future<void> boot() async {
  registerAppRoutes();

  if (kDebugMode) {
    MagicPreview.register(previewEntries());   // from _previews.g.dart
    MagicPreview.registerRoutes();
  }
}
```

| API | Signature | Notes |
|:----|:----------|:------|
| `MagicPreview.register(entries)` | `static void` | Snapshots the catalog into an unmodifiable list. Call before `registerRoutes()`. |
| `MagicPreview.registerRoutes()` | `static void` | Registers the two pages, named `magic-preview.index` and `magic-preview.component`. |
| `MagicPreview.entries` | `List<PreviewEntry>` | Read-only view of what is registered. |
| `PreviewEntry({label, slug, builder})` | `const`, `@immutable` | `label` is the sidebar name, `slug` is the `:component` segment (unique; `previews:refresh` collision-checks at build time), `builder` is a `WidgetBuilder`. |

Two rules decide whether the catalog appears at all:

1. **Register inside a provider `boot()`.** `MagicRouter` locks its route table the first time `routerConfig` is read, and `addRoute` throws `StateError` after that. A `boot()` runs during the Magic bootstrap, before `MaterialApp` reads the router, so it is the only safe window. Register later and `/preview` silently never exists.
2. **Release is closed.** `registerRoutes()` returns early on `kReleaseMode`, and again when `kPreviewEnabled` is false. That flag is `const bool.fromEnvironment('PREVIEW_ENABLED', defaultValue: kDebugMode)`, so both guards const-fold and the optimizer proves the route, the catalog widget, and every registered entry unreachable. A profile build can opt in with `--dart-define=PREVIEW_ENABLED=true`; a debug build can force it off with `false`. Release stays closed either way.

## Gotchas

| Mistake | Consequence | Fix |
|:--------|:------------|:----|
| `!kReleaseMode` moved inside `installPre` / `installPost` | Tapir and crumbs ship in the release bundle | Guard at the call site |
| `installPost()` called before `Magic.init()` | Enrichers and the HTTP adapter cannot resolve through the container | Keep the two calls on either side of `init` |
| `installPre()` behind a lazy debug toggle, after `runApp` | `StateError` from `MagicRouter.addObserver`: the router locks its observers once built | Call it at boot, before `Magic.init()`, and nowhere else |
| A perf report full of zeros | A pointer was never assigned; every tapir default is a structurally-complete no-op, so it reports zeros instead of failing | Check `MagicPerfIntegration.install()` actually ran (`MagicDevtools.installPre()` and `magic:install --with-devtools` both install it); an app wired only by `tapir:install` / `crumbs:install` never runs it |
| `MagicPreview.registerRoutes()` from anywhere but a provider `boot()` | Router already locked, `/preview` missing or `StateError` | Move it into `boot()` |
| Preview entries held in a top-level `const` list | Widget references survive the release tree-shake (dart-lang/sdk#33920) | Return them from `previewEntries()`, which is what the codegen already does |
| `magic_devtools` in `dev_dependencies` | `depend_on_referenced_packages` lint | Regular `dependencies`, guarded by `!kReleaseMode` |

For the tool surfaces themselves (the `tapir_*` and `crumbs_*` MCP tools, the CLI verbs, the ring buffers), load the `tapir` and `crumbs` skills. This file covers only the Magic adapter layer.
