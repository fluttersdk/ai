<!-- magic_devtools v0.0.4 | Updated: 2026-08-29 -->

# magic_devtools Plugin

Debug-only adapter layer that wires Magic's runtime into `fluttersdk_dusk` (LLM-agent E2E driver) and `fluttersdk_telescope` (runtime inspector), plus the performance data path and a dev-only component preview catalog. Enriches dusk snapshots and telescope records with Magic context (forms, navigation, controllers, gates, auth, broadcasting, HTTP) so an agent sees the app the way Magic sees it.

Lives outside `magic` core on purpose: the framework keeps no dev-tooling dependency in a production build.

## Installation

The one-step path, from a project that already has magic installed:

```bash
dart run magic:artisan magic:install --with-devtools
```

That adds the three packages to `dependencies` and injects the `kDebugMode` blocks into `lib/main.dart`. It is idempotent, so a re-run never duplicates the wiring.

The manual path, when the app is already installed and only the tooling is being added:

```yaml
dependencies:
  magic_devtools: ^0.0.4
  fluttersdk_dusk: ^0.0.12       # add if you use dusk
  fluttersdk_telescope: ^0.0.5   # add if you use telescope
```

Those two floors are the ones `magic_devtools` itself declares, and they are floors for a reason: the perf data path calls `perf_readers.dart` (dusk 0.0.12) and `FramePerfWatcher` / `TelescopeStore.recentFramePerf` (telescope 0.0.5), alongside `MagicController.onRefreshUI` (magic 0.0.7) and `WindPerfCounters` (wind 1.5.0). A caret range resolves to the newest, so a fresh graph always worked; an app whose own constraints hold one sibling back gets a satisfiable graph that then fails on undefined symbols.

These are regular `dependencies`, not `dev_dependencies`: `lib/main.dart` imports them, so a `dev_dependencies` entry trips the `depend_on_referenced_packages` lint. The `kDebugMode` guard is what keeps them out of a release build, not the dependency section.

Then wire the CLI side of each tool:

```bash
dart run magic:artisan plugin:install fluttersdk_dusk
dart run magic:artisan plugin:install fluttersdk_telescope
dart run magic:artisan dusk:install
dart run magic:artisan telescope:install
dart run magic:artisan mcp:install          # surfaces the dusk_* / telescope_* MCP tools
```

## Wiring: two phases that straddle `Magic.init()`

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (kDebugMode) MagicDevtools.installPre();

  await Magic.init(configFactories: [...]);

  if (kDebugMode) MagicDevtools.installPost();

  runApp(const MyApp());
}
```

| Call | Runs | What it does |
|:-----|:-----|:-------------|
| `MagicDevtools.installPre()` | BEFORE `Magic.init()` | `DuskPlugin.install()` + `TelescopePlugin.install()`, then registers telescope's opt-in `ExceptionWatcher` and `DumpWatcher`, then `MagicPerfIntegration.install()`. Must be first so the snapshot pipeline and the exception watcher are live while Magic boots, capturing boot-time errors and the first route resolve. |
| `MagicDevtools.installPost()` | AFTER `Magic.init()` | `MagicTelescopeIntegration.install()` (5 Magic watchers + `MagicHttpFacadeAdapter` + the dusk-to-telescope bridge readers) and `MagicDuskIntegration.install()` (14 Magic-aware snapshot enrichers + the `MagicRouter` navigate adapter). Must be last because every one of those resolves dependencies through the IoC container. |

Both halves are idempotent, so a second call in the same isolate is safe. `installPre()` is NOT safe to call LATE, though, and that changed in 0.0.4: the perf integration registers a `NavigatorObserver`, and `MagicRouter.addObserver` throws a `StateError` once the router has been built. A host that installs behind a lazy debug toggle after `runApp` used to get harmless no-ops and now crashes. The throw is deliberate: a silently unregistered observer would produce a performance report with no route transitions and nothing to explain their absence.

> [!WARNING]
> Keep `kDebugMode` at the CALL SITE. Moving the guard inside `installPre` / `installPost` makes the call live in release, which defeats the tree-shake and pulls dusk plus telescope into the production bundle. That tree-shake is the entire reason this package exists separately from magic core.

## The four import barrels

| Barrel | Entry point | Reach for it when |
|:-------|:------------|:------------------|
| `package:magic_devtools/magic_devtools.dart` | `MagicDevtools` | Default. Both tools, standard watcher set, two calls. |
| `package:magic_devtools/dusk.dart` | `MagicDuskIntegration` | Dusk only, without telescope. |
| `package:magic_devtools/telescope.dart` | `MagicTelescopeIntegration` | Telescope only, or a non-standard watcher set (register extras with `TelescopePlugin.registerWatcher` after `installPre`). |
| `package:magic_devtools/preview.dart` | `MagicPreview` | Hosting the component preview catalog. |

Single-tool wiring keeps the same pre/post split:

```dart
if (kDebugMode) DuskPlugin.install();
await Magic.init(configFactories: [...]);
if (kDebugMode) MagicDuskIntegration.install();
```

## MagicPerfIntegration: the performance data path (0.0.4+)

The one assembly point for performance diagnostics, because it is the only place dusk, telescope, wind and magic are visible at once. Dusk's frozen dependency contract forbids it from importing any of the packages whose data it reports, so it declares four function pointers with no-op defaults and someone else has to assign them. That someone is this class.

`MagicDevtools.installPre()` installs it. There is nothing else to wire.

| What it touches | Package | Why |
|:----------------|:--------|:----|
| `MagicController.onRefreshUI` | magic | Counts `refreshUI()` per controller runtime type, so a report can name which controller rebuilds the screen. |
| `MagicRouter.addObserver` | magic | A `NavigatorObserver` that times each route push to the first post-frame callback after the new route builds. Last 200 transitions retained. |
| `Wind.installPerfResolver()` | wind | Arms `WindPerfCounters` (parse-path and class-cache counts). Counting stays OFF until a session begins. |
| `TelescopePlugin.registerWatcher(FramePerfWatcher())` | telescope | Frame timings into telescope's frame buffer. |
| `framePerfReader`, `perfExtrasReader`, `perfSessionBeginHook`, `perfSessionEndHook` | dusk | The four pointers dusk reads all of the above through. |

| API | Signature | Notes |
|:----|:----------|:------|
| `MagicPerfIntegration.install()` | `static void` | Idempotent. Called for you by `installPre()`. |
| `MagicPerfIntegration.controllerNotifyCounts` | `Map<String, int>` | Notifies per controller type since the last session began. |
| `MagicPerfIntegration.routeTransitions` | `List<Map<String, Object?>>` | The retained transitions, most recent last. |

Session scoping is the part that surprises people: `perfSessionBeginHook` resets wind's counters, clears telescope's frame buffer (`clearFramePerf()`, never `clear()`, which would wipe the HTTP and log buffers a developer may be reading) and clears the controller and route counters. Without that reset every session would report the sum of all previous ones. `perfSessionEndHook` turns counting off but leaves the totals intact, because `perf_end` reads them to build its report.

## MagicPreview: the component preview catalog

A dev-only catalog served from two routes, `/preview` (first entry) and `/preview/:component` (entry by slug). The sidebar lists every registered entry, only the selected one is mounted, and the header carries a light/dark toggle bound to wind's `WindThemeController`.

The entries come from codegen: `dart run magic:artisan make:component` scaffolds a `*.preview.dart` file per component and `dart run magic:artisan previews:refresh` collects them into `lib/_previews.g.dart`, which exposes `previewEntries()` returning a `List<PreviewEntry>`.

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
| `kDebugMode` moved inside `installPre` / `installPost` | Dusk and telescope ship in the release bundle | Guard at the call site |
| `installPost()` called before `Magic.init()` | Enrichers and the HTTP adapter cannot resolve through the container | Keep the two calls on either side of `init` |
| `installPre()` behind a lazy debug toggle, after `runApp` | `StateError` from `MagicRouter.addObserver`: the router locks its observers once built (0.0.4+) | Call it at boot, before `Magic.init()`, and nowhere else |
| A perf report full of zeros | A pointer was never assigned; every dusk default is a structurally-complete no-op, so it reports zeros instead of failing | Check `MagicDevtools.installPre()` actually ran (it is what installs `MagicPerfIntegration`) |
| `MagicPreview.registerRoutes()` from anywhere but a provider `boot()` | Router already locked, `/preview` missing or `StateError` | Move it into `boot()` |
| Preview entries held in a top-level `const` list | Widget references survive the release tree-shake (dart-lang/sdk#33920) | Return them from `previewEntries()`, which is what the codegen already does |
| `magic_devtools` in `dev_dependencies` | `depend_on_referenced_packages` lint | Regular `dependencies`, guarded by `kDebugMode` |

For the tool surfaces themselves (the `dusk_*` and `telescope_*` MCP tools, the CLI verbs, the ring buffers), load the `fluttersdk-dusk` and `fluttersdk-telescope` skills. This file covers only the Magic adapter layer.
