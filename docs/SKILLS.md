# FlutterSDK AI Skills

Five skills are available in the registry. Each one is a structured knowledge file that an AI coding agent loads to generate correct code on the first try.

Skills are fetched automatically via `skills/index.json` (OpenCode) or the Claude Code plugin marketplace. See [README.md](../README.md) for installation options.

Every skill here is a mirror of the upstream package's own `skills/` directory, delivered by [`sync.yml`](../.github/workflows/sync.yml) when that package publishes a release. The upstream repo is the place to file an issue or send a fix. The synced version of each skill is the `version:` field in its `SKILL.md` frontmatter, so it is not repeated below.

---

## wind-ui

**Package:** `fluttersdk_wind`
**Upstream repo:** https://github.com/fluttersdk/wind

### Triggers on

Any UI work in a Flutter app that depends on `fluttersdk_wind`: a `className` string, a W-prefix widget, a `WindTheme` / `WindThemeData` reference, or a request phrased as Tailwind for Flutter.

### What it provides

Utility-first Flutter styling: every visual decision lives in a `className` string that a 20-parser pipeline turns into a cached immutable `WindStyle`. The skill teaches the 27 public widgets (`WDiv`, `WText`, `WButton`, `WInput`, `WSelect`, `WCheckbox`, `WDatePicker`, `WPopover`, `WAnchor`, `WIcon`, `WImage`, `WSvg`, `WSpacer`, `WBreakpoint`, `WDynamic`, `WKeyboardActions`, `WBadge`, `WCard`, `WSwitch`, `WRadio`, `WTabs`, five `WForm*` wrappers), the full token catalog with its arbitrary-value patterns, the stacking prefix system (`dark:` / `hover:` / `focus:` / `md:` / `ios:` / state prefixes), `WindRecipe` and `WindSlotRecipe` variant composition, and the Flutter constraint rules behind most overflow errors.

Two contracts do the heavy lifting: every color token carries a `dark:` peer in the same className, and conditional styling routes through `states:` plus prefixed classes rather than interpolated Dart.

Ten reference files: `tokens`, `widgets`, `forms`, `layouts`, `theme`, `tailwind-divergence`, `dynamic`, `debug`, `design-culture`, `community`.

### Recommended companion skills

`magic-framework` for architecture, routing, and data layers.

---

## magic-framework

**Package:** `magic`
**Upstream repo:** https://github.com/fluttersdk/magic

### Triggers on

Any file that imports `package:magic/magic.dart` or `package:magic/testing.dart`, or work touching `Magic.init`, a facade, a Model, a `MagicController`, a `MagicView`, `MagicFormData`, a `FormRequest`, a ServiceProvider, a migration, or the artisan CLI.

### What it provides

The Laravel-inspired half of a FlutterSDK app: IoC container, 18 facades (`Auth`, `Http`, `Cache`, `DB`, `Echo`, `Event`, `Gate`, `Config`, `Lang`, `Launch`, `Log`, `Pick`, `MagicRoute`, `Schema`, `Session`, `Storage`, `Vault`, `Crypt`), an Eloquent-style ORM with migrations and seeders, service providers and the boot lifecycle, reactive controllers with `MagicStateMixin` and `RxStatus`, GoRouter-backed routing with resource routes and middleware, forms and validation including async rules, Gate abilities and policies, and the test surface (`MagicTest`, facade fakes).

The CLI side covers `magic:install`, `key:generate`, the `make:*` generators, `make:component`, `previews:refresh`, `design:sync`, and `design:lint`, all invoked as `dart run magic:artisan <command>`.

Nineteen reference files, including one per ecosystem plugin: `magic_deeplink`, `magic_notifications`, `magic_social_auth`, `magic_starter`, and `magic_devtools`.

### Recommended companion skills

`wind-ui` for all UI styling; `fluttersdk-artisan` for the CLI substrate and MCP wiring.

---

## fluttersdk-dusk

**Package:** `fluttersdk_dusk`
**Upstream repo:** https://github.com/fluttersdk/dusk

### Triggers on

Any `dusk_*` MCP tool call, any `dusk:*` CLI command, a `./bin/fsa` invocation, or a request to drive, inspect, test, or debug a running Flutter app.

### What it provides

An E2E driver that lets an agent see (`snap`, `observe`, `screenshot`) and act (`tap`, `type`, `drag`, `scroll`, `navigate`) on a running Flutter app through a matched pair of `dusk_*` MCP tools and `dusk:*` CLI commands, one CLI verb per tool. Snapshots emit a YAML Semantics tree with stable `[ref=eN]` tokens; `dusk_find` and `dusk_observe` mint re-resolvable `q<N>` query handles that survive a rebuild where an `e<N>` does not.

Every gesture passes a six-step actionability gate whose failure reasons are substring-parseable (`not enabled`, `zero rect`, `off-viewport`, `not stable`, `obscured by`, `defunct`), so an agent can branch on why a tap was refused instead of retrying blindly.

### Recommended companion skills

`fluttersdk-artisan` (required substrate), `fluttersdk-telescope` for reading side effects after a gesture.

---

## fluttersdk-telescope

**Package:** `fluttersdk_telescope`
**Upstream repo:** https://github.com/fluttersdk/telescope

### Triggers on

Any `telescope_*` MCP tool call, any `telescope:*` CLI command, or a request to inspect HTTP traffic, logs, exceptions, events, queries, cache operations, or debug dumps from a running Flutter app.

### What it provides

A passive runtime inspector. The app captures HTTP traffic, structured logs, uncaught exceptions, debug dumps, in-app events, gate checks, DB queries, and Magic cache operations into nine in-memory ring buffers (500 entries each, FIFO eviction), surfaced as `ext.telescope.*` VM Service extensions and read through nine MCP tools or six CLI commands.

It pairs with dusk: dusk drives the app, telescope reads what the app did in response, so a verification step does not depend on what happens to be visible on screen.

### Recommended companion skills

`fluttersdk-artisan` (required substrate), `fluttersdk-dusk` for driving the UI whose side effects you are reading.

---

## fluttersdk-artisan

**Package:** `fluttersdk_artisan`
**Upstream repo:** https://github.com/fluttersdk/artisan

### Triggers on

Any `artisan_*` MCP call, a `./bin/fsa` or `dart run artisan` invocation, a mention of `.artisan/state.json`, `bin/dispatcher.dart`, or `_plugins.g.dart`, or a request to start, stop, restart, reload, inspect, or tinker with a Flutter app.

### What it provides

The substrate the other two tools plug into: a Dart CLI framework plus a stdio MCP server that boots, inspects, hot-reloads, and evaluates a running Flutter app through ten substrate MCP tools plus its builtin CLI command set. `~/.artisan/state.json` carries the running app's pid, VM Service URI, and FIFO pipe, and lazy reconnect picks it up after `artisan_start`, so a fresh agent session attaches to an app that is already running.

One wiring detail decides whether plugin tools appear at all: `dusk_*` and `telescope_*` surface only through the dispatcher path (`./bin/fsa mcp:serve`), never through the substrate-only `dart run fluttersdk_artisan:mcp`.

### Recommended companion skills

`fluttersdk-dusk` and `fluttersdk-telescope` are artisan plugins; load them when the task touches E2E driving or runtime inspection.
