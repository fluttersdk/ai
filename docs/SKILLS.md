# FlutterSDK AI Skills

Five skills are available in the registry. Each skill is a structured knowledge
file that an AI coding agent loads to generate correct code on the first try.

Skills are fetched automatically via `skills/index.json` (OpenCode) or the
Claude Code plugin marketplace. See [README.md](../README.md) for installation
options.

---

## wind-ui

**Version:** 1.0.0-alpha.6
**Upstream repo:** https://github.com/fluttersdk/wind

### Triggers on

Any mention of Wind UI's W-prefix widget API or `className` styling.

### What it provides

Build Flutter UI with Wind's utility-first className system. W-prefix widgets,
design culture, enforcement gates, theming, component-first workflow. The skill
teaches the agent the full `className` string grammar (Tailwind-style classes
mapped to Flutter render semantics), the 20 W-prefix widgets (`WDiv`, `WText`,
`WButton`, `WInput`, `WSelect`, `WCheckbox`, `WIcon`, `WImage`, `WSvg`,
`WPopover`, `WAnchor`, `WFormInput`, `WFormSelect`, `WFormMultiSelect`,
`WFormCheckbox`, `WDatePicker`, `WFormDatePicker`, `WSpacer`, `WDynamic`),
responsive breakpoints, dark mode (`dark:` class prefix), and state styling.
After loading this skill the agent will not use `Container`, `Text`, or
`ElevatedButton` where a W-widget exists, and will always supply a `dark:`
counterpart for colour classes.

### Recommended companion skills

`magic-framework` for architecture, routing, and data layers.

---

## magic-framework

**Version:** 1.0.0-alpha.13
**Upstream repo:** https://github.com/fluttersdk/magic

### Triggers on

Any file that imports `package:magic/magic.dart` or mentions Magic-specific
symbols.

### What it provides

Magic Framework: Flutter IoC + 17 Facades (Auth, Http, Cache, DB, Echo, Log,
Event, Gate, MagicRoute...), Eloquent ORM, Service Providers, GoRouter,
MagicController/View, forms, testing, 4 plugins. The skill covers the full
framework surface: `Magic.init()` bootstrap, singleton controller pattern
(`Magic.findOrPut`), IoC bindings in Service Providers, all 17 facades,
Eloquent Model conventions (typed `get<T>()` accessors, `table`/`resource`/
`fillable` declarations), `MagicFormData` form handling, `ValidatesRequests`
mixin, context-free UI helpers (`Magic.snackbar`, `Magic.toast`, `Magic.dialog`,
`MagicRoute.to`), and the four optional plugins (`magic_deeplink`,
`magic_notifications`, `magic_social_auth`, `magic_starter`).

### Recommended companion skills

`wind-ui` for all UI styling; `fluttersdk-artisan` for CLI scaffolding and MCP
integration.

---

## fluttersdk-dusk

**Version:** 0.0.2
**Upstream repo:** https://github.com/fluttersdk/dusk

### Triggers on

Any `dusk_*` MCP tool call, `dusk:*` CLI command, or request to drive or
inspect a running Flutter app.

### What it provides

fluttersdk_dusk: E2E driver for Flutter apps that lets an LLM agent see (snap,
observe, screenshot) and act (tap, type, drag, scroll, navigate) on a running
Flutter app via 31 MCP tools (`dusk_*`) and 32 matching CLI commands
(`./bin/fsa dusk:*`). Snapshots emit a YAML Semantics tree with stable
`[ref=eN]` tokens; `dusk_find` and `dusk_observe` mint re-resolvable `q<N>`
query handles. Every gesture passes a 6-step actionability gate with
substring-parseable failure reasons (`not enabled`, `zero rect`, `off-viewport`,
`not stable`, `obscured by`, `defunct`). TRIGGER when: any `dusk_*` MCP tool
call, any `dusk:*` CLI command, `./bin/fsa` invocation, the user asks the agent
to drive / inspect / test / debug a running Flutter app, the user mentions snap /
observe / actionability / ref / eN / qN, or the conversation touches
end-to-end testing of a Flutter UI. DO NOT TRIGGER when: only authoring
`flutter_test` widget tests, only reading telescope ring buffers without driving
the UI (use fluttersdk-telescope), or only modifying Dart source without running
it.

### Recommended companion skills

`fluttersdk-artisan` (required substrate), `fluttersdk-telescope` for passive
runtime inspection without driving UI.

---

## fluttersdk-telescope

**Version:** 0.0.1
**Upstream repo:** https://github.com/fluttersdk/telescope

### Triggers on

Any `telescope_*` MCP tool call, `TelescopePlugin.install()` reference, or
request to inspect HTTP, logs, or Magic framework state in a running app.

### What it provides

fluttersdk_telescope: runtime inspector plugin for Flutter apps. Captures HTTP
traffic, structured logs, uncaught exceptions, Magic Model lifecycle events,
Magic Cache operations, in-app events, Gate authorization checks, debugPrint
output, and DB queries into 9 in-memory ring buffers. Surfaces all 9 buffers as
VM Service extensions (ext.telescope.*) and exposes 9 MCP tools
(telescope_*) for LLM-agent inspection without modifying app code or attaching
DevTools. Plugin of fluttersdk_artisan: contributes 6 CLI commands and 9 MCP
tools via TelescopeArtisanProvider. TRIGGER when: package:fluttersdk_telescope
import, TelescopePlugin.install() call, TelescopeWatcher / TelescopeHttpAdapter
mention, ext.telescope.* VM extension, telescope_* MCP tool call, or user asks
about inspecting HTTP, logs, exceptions, or Magic framework state in a running
Flutter app. DO NOT TRIGGER when code only uses fluttersdk_artisan substrate
tools without telescope.

### Recommended companion skills

`fluttersdk-artisan` (required substrate), `fluttersdk-dusk` for active UI
driving alongside passive inspection.

---

## fluttersdk-artisan

**Version:** 0.0.1
**Upstream repo:** https://github.com/fluttersdk/artisan

### Triggers on

Any `dart run fluttersdk_artisan` command, `artisan_*` MCP tool call, or
mention of `install.yaml`, `bin/dispatcher.dart`, or `ArtisanCommand`.

### What it provides

fluttersdk_artisan: composable Dart 3.4+ CLI framework + stdio MCP server for
Flutter and Dart. 21 builtin commands across 6 groups (lifecycle, scaffolding,
plugin management, MCP, introspection, codegen) including install, make:plugin,
plugin:install, mcp:serve, tinker. Declarative install.yaml plugin manifest +
procedural PluginInstaller fluent DSL with 26 sealed InstallOperation variants.
10 substrate MCP tools (artisan_*) including artisan_tinker for VM expression
eval, plus plugin-contributed tools from sibling plugins (fluttersdk_dusk,
fluttersdk_telescope; see each plugin's MCP tool reference for the current
catalog). TRIGGER when: package:fluttersdk_artisan import, fluttersdk_artisan in
pubspec, dart run fluttersdk_artisan command, bin/dispatcher.dart present,
install.yaml manifest, ArtisanCommand / ArtisanServiceProvider /
McpToolDescriptor / PluginInstaller mention, .mcp.json fluttersdk entry, or user
asks about artisan, plugin scaffold, MCP setup, dev loop, signature DSL. DO NOT
TRIGGER when code only uses Wind UI or Magic without artisan touchpoint.

### Recommended companion skills

`fluttersdk-dusk` and `fluttersdk-telescope` are Artisan plugins; load them
when the task touches E2E testing or runtime inspection.
