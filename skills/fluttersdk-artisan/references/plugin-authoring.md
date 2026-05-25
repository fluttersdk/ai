# Plugin authoring (end-to-end)

Walks the full lifecycle of an artisan plugin: scaffold, structure, contract, command + MCP tool authoring, publishing, consumer registration. Pair with `installer-dsl.md` when the plugin needs procedural install logic and with `install-yaml-schema.md` when the plugin uses the declarative manifest.

## What a plugin is

An artisan plugin is a Dart package on pub.dev that exports an `ArtisanServiceProvider` subclass. When a consumer registers the provider (manually or auto-discovered via `lib/app/_plugins.g.dart`), the plugin's commands and MCP tool descriptors join the consumer's command surface.

A plugin can be any combination of:
- **Command-only**: ships commands the consumer can invoke via `dart run artisan <plugin>:<verb>`.
- **MCP-only**: ships `McpToolDescriptor` entries that surface as MCP tools but have no CLI form.
- **Both**: commands available via CLI + MCP entries available to AI agents.
- **Self-installable**: ships an `install.yaml` manifest or `ArtisanInstallCommand` so `plugin:install` can write framework wiring (Magic provider registration, native permissions, env vars).

## Scaffold a new plugin

```bash
dart run artisan make:plugin my_plugin             # generic: Magic-free
dart run artisan make:plugin my_plugin --magic     # magic-aware: adds install.yaml + ServiceProvider + install/uninstall commands
```

`make:plugin` runs the 8-phase pipeline:

1. Validate snake_case name.
2. Resolve target directory (`packages/<name>/` by default; `--path` or `--target` override).
3. `flutter create --template=package` to lay down the baseline (pubspec, LICENSE, CHANGELOG, .gitignore, etc.).
4. Render generic stubs from `assets/stubs/make_plugin/generic/` (provider, pubspec, README, runtime barrel, CLI barrel).
5. (When `--magic`) Render Magic add-ons from `assets/stubs/make_plugin/magic/` (install.yaml, ServiceProvider, install/uninstall commands, config stub).
6. Detect parent Flutter app and (when found) enroll the plugin in `pubspec.yaml` workspace.
7. Update parent's `pubspec.yaml` with `workspace:` entry.
8. Print success banner with next-step suggestions.

## Generic plugin output layout

```
packages/my_plugin/
├── bin/
│   └── my_plugin.dart                    # CLI entry (standalone use; rarely invoked)
├── lib/
│   ├── my_plugin.dart                    # Runtime barrel (public API for consumers)
│   ├── cli.dart                          # CLI barrel (re-exports provider + commands for plugin:install)
│   └── src/
│       └── my_plugin_artisan_provider.dart   # ArtisanServiceProvider subclass
├── test/
│   └── my_plugin_artisan_provider_test.dart
├── pubspec.yaml
└── README.md
```

`my_plugin_artisan_provider.dart` skeleton (the file `make:plugin` produces; placeholders rendered):

```dart
import 'package:fluttersdk_artisan/artisan.dart';

/// Entry point: the consumer's bin/dispatcher.dart registers this provider,
/// either manually (`registry.registerProvider(MyPluginArtisanProvider());`)
/// or automatically via the generated lib/app/_plugins.g.dart barrel.
final class MyPluginArtisanProvider extends ArtisanServiceProvider {
  @override
  String get providerName => 'my_plugin';

  @override
  List<ArtisanCommand> commands() => <ArtisanCommand>[
        // MyHelloCommand(),
      ];

  @override
  List<McpToolDescriptor> mcpTools() => const <McpToolDescriptor>[
        // McpToolDescriptor(...),
      ];
}
```

## Magic-mode additions

When `make:plugin --magic` runs, four generic stubs are replaced and six additional files land:

| Stub | Target |
|------|--------|
| `install_command.dart` | `lib/src/commands/install_command.dart` |
| `uninstall_command.dart` | `lib/src/commands/uninstall_command.dart` |
| `install.yaml` | `install.yaml` (plugin root) |
| `config_stub.dart` | `assets/stubs/install/<name>_config.dart.stub` |
| `install_command_test.dart` | `test/cli/install_command_test.dart` |
| `service_provider.dart` | `lib/src/<name>_service_provider.dart` |

The install.yaml manifest auto-registers the Magic ServiceProvider with the consumer's `lib/config/app.dart` providers list when `plugin:install` runs.

## ArtisanServiceProvider contract

Source: `lib/src/console/artisan_service_provider.dart:11-25`.

```dart
abstract class ArtisanServiceProvider {
  String get providerName;

  /// Commands the provider contributes to the consumer's registry.
  /// Default: empty list. Override to ship CLI commands.
  List<ArtisanCommand> commands() => const <ArtisanCommand>[];

  /// MCP tools surfaced when the consumer runs `mcp:serve`.
  /// Default: empty list. Override to ship VM-extension-backed MCP tools.
  List<McpToolDescriptor> mcpTools() => const <McpToolDescriptor>[];

  /// Optional sync registration hook. Runs when the registry registers
  /// the provider, before any command dispatch. Rare; usually unneeded.
  void register(ArtisanRegistry registry) {}
}
```

`providerName` is used for filter targeting (`--include-package=my_plugin` matches). `commands()` and `mcpTools()` are the two surface methods; most plugins override one or both.

## Writing a command

Source pattern: any of the 21 builtins. The simplest shape (no flags):

```dart
import 'package:fluttersdk_artisan/artisan.dart';

final class MyHelloCommand extends ArtisanCommand {
  @override
  String get name => 'my_plugin:hello';

  @override
  String get description => 'Say hello from my_plugin.';

  @override
  Future<int> handle(ArtisanContext ctx) async {
    ctx.output.info('Hello from my_plugin.');
    return 0;
  }
}
```

With the signature DSL:

```dart
final class MyGreetCommand extends ArtisanCommand {
  @override
  String get name => 'my_plugin:greet';

  @override
  String get signature => 'my_plugin:greet '
      '{name : Person to greet (required)} '
      '{--shout : Print in upper case}';

  @override
  String get description => 'Greet a named person, optionally in upper case.';

  @override
  Future<int> handle(ArtisanContext ctx) async {
    final name = ctx.input.argument('name');
    final shout = ctx.input.option('shout') == true;
    final greeting = 'Hello, $name!';
    ctx.output.info(shout ? greeting.toUpperCase() : greeting);
    return 0;
  }
}
```

Register both in the provider's `commands()`:

```dart
List<ArtisanCommand> commands() => <ArtisanCommand>[
  MyHelloCommand(),
  MyGreetCommand(),
];
```

Signature DSL grammar: full reference at `lib/src/console/command_signature.dart:39-220`. Argument modifiers: `?` optional, `=default` default value, `*` variadic, `?*` optional-variadic. Option shapes: `{--flag}` boolean, `{--option=value}` value option with default. Description annotation: ` : description` after the token name.

Connected commands (need VM Service):

```dart
final class MyEvalCommand extends ArtisanCommand {
  @override
  String get name => 'my_plugin:eval';

  @override
  String get signature => 'my_plugin:eval {expression}';

  @override
  String get description => 'Evaluate a Dart expression in the running app.';

  @override
  CommandBoot get boot => CommandBoot.connected;

  @override
  Future<int> handle(ArtisanContext ctx) async {
    final expr = ctx.input.argument('expression');
    final result = await ctx.evaluate(expr);
    ctx.output.writeln('$result');
    return 0;
  }
}
```

`CommandBoot.connected` requires the consumer to have run `dart run artisan start` so `~/.artisan/state.json` records the VM Service URI. The dispatcher (CLI or MCP) builds an `ArtisanContext.connected` automatically.

## Adding MCP tools

Two patterns:

### A. Substrate-style (CLI command + MCP tool)

When the plugin's command works equally well from CLI and from an AI agent, expose both. The MCP tool descriptor calls the same `handle()` method.

```dart
List<McpToolDescriptor> mcpTools() => <McpToolDescriptor>[
  McpToolDescriptor(
    name: 'my_plugin_greet',
    description: 'Greet a named person from the my_plugin sample. Use to demonstrate plugin-contributed MCP tools.\n\nUsage:\n- Pass `name` (required).\n- Pass `shout=true` to upper-case the output.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'name': {'type': 'string', 'description': 'Person to greet.'},
        'shout': {'type': 'boolean', 'description': 'Upper-case the output.'},
      },
      'required': ['name'],
    },
    extensionMethod: 'artisan:my_plugin:greet', // routes to the CLI command
  ),
];
```

The `extensionMethod` with `artisan:` prefix routes the dispatch through the in-process command runner (same as substrate tools). The MCP arguments map directly to the command's `ArtisanInput`.

### B. VM-extension-style (runtime hook in the Flutter app)

When the tool needs to read live app state or trigger app-side behavior (driving a widget, capturing a screenshot, evaluating a controller), the running Flutter app must register a VM Service extension at startup, and the MCP tool descriptor points at that extension.

```dart
// In the consumer's lib/main.dart or a service provider's onAppBoot:
import 'dart:developer';

void registerMyPluginExtensions() {
  registerExtension('ext.myPlugin.greet', (method, parameters) async {
    final name = parameters['name'] ?? 'world';
    final shout = parameters['shout'] == 'true';
    final greeting = 'Hello, $name!';
    return ServiceExtensionResponse.result(
      jsonEncode({'result': shout ? greeting.toUpperCase() : greeting}),
    );
  });
}

// In the plugin's MCP tool descriptor:
McpToolDescriptor(
  name: 'my_plugin_greet',
  description: '...',
  inputSchema: {...},
  extensionMethod: 'ext.myPlugin.greet', // no `artisan:` prefix
)
```

The MCP server's dispatcher routes any `extensionMethod` without the `artisan:` prefix through `vmClient.callExtension(method, params)`. Requires a running app (lazy-reconnect handles cold start).

`fluttersdk_dusk` and `fluttersdk_telescope` use pattern B; their MCP tools register `ext.dusk.*` and `ext.telescope.*` extensions in the Flutter app and surface the tools through MCP.

## Naming conventions

Tool name: `<plugin_prefix>_<verb>` (snake_case). Example: `my_plugin_greet`. The prefix should match the package's `providerName` (or be a recognizable abbreviation thereof).

Description: Claude Code canonical format. Imperative opening sentence (1 line), 1-2 sentence context paragraph, `Usage:` H3 or bullet list with concrete invocation guidance, parameter notes. Cap at 2 KB total (Claude Code truncates).

Input schema: JSON Schema (draft 2020). Always include `type: 'object'`, `properties:`, and `required:` when fields are mandatory. Each property must have a `description` (the model reads it during planning, not just at error time).

## Publishing

When the plugin is ready:

1. Update `pubspec.yaml`: bump version, ensure `description` is concrete, set `repository` + `homepage`, pick up to 5 pub.dev topics.
2. Run `dart pub publish --dry-run`. Inspect the archive. Verify size is reasonable (under 500 KB compressed unless assets justify more).
3. Add an `install.yaml` if the plugin needs framework wiring; consumers will get one-command install via `plugin:install`.
4. Update CHANGELOG with the new version's behavior.
5. `dart pub publish`.

Once published, consumers add via:

```bash
dart pub add my_plugin
dart run artisan plugin:install my_plugin
```

The `plugin:install` step routes by manifest presence:

- With `install.yaml`: parses the manifest, walks `ManifestInstaller`, registers in `.artisan/plugins.json`, refreshes `lib/app/_plugins.g.dart`.
- Without manifest + canonical scaffold present: writes to `.artisan/plugins.json` + refresh.
- Without manifest + no canonical scaffold: legacy injection of import + `registry.registerProvider(...)` into `bin/dispatcher.dart`.

## Consumer registration

`install` produces `bin/dispatcher.dart` that auto-discovers plugins from `lib/app/_plugins.g.dart`:

```dart
import 'package:fluttersdk_artisan/artisan.dart';
import 'package:my_consumer/app/_plugins.g.dart' as plugins;
import 'package:my_consumer/app/commands/_index.g.dart' as commands;

Future<void> main(List<String> args) async {
  exitCode = await runArtisan(
    args,
    baseProviders: plugins.autoDiscoveredProviders(),
    autoProviders: commands.consumerCommands,
  );
}
```

`autoDiscoveredProviders()` is regenerated by `plugins:refresh` from `.artisan/plugins.json`. Every installed plugin lands here automatically.

A consumer can also register providers manually for plugins that ship without an `install.yaml`:

```dart
Future<void> main(List<String> args) async {
  final registry = ArtisanRegistry();
  registry.registerAll(commands.consumerCommands);
  registry.registerProvider(MyPluginArtisanProvider());
  exit(await ArtisanApplication(registry).dispatch(args));
}
```

This bypasses `_plugins.g.dart` for the manual provider; useful for in-house plugins not published to pub.dev.

## Testing

The artisan package provides test primitives:

- `InMemoryFs` (`lib/src/installer/install_context.dart`) for filesystem isolation in installer tests.
- `BufferedOutput` for capturing command output.
- `ArtisanContext.bare(input, output)` for unit-testing commands without VM Service.

Example command test:

```dart
import 'package:fluttersdk_artisan/artisan.dart';
import 'package:test/test.dart';

void main() {
  test('my_plugin:greet prints greeting', () async {
    final command = MyGreetCommand();
    final output = BufferedOutput();
    final input = MapInput({'name': 'world'});
    final ctx = ArtisanContext.bare(input, output);

    final exitCode = await command.handle(ctx);

    expect(exitCode, 0);
    expect(output.content, contains('Hello, world!'));
  });
}
```

Installer test:

```dart
test('MyPluginInstall writes config + injects provider', () async {
  final fs = InMemoryFs();
  fs.write('pubspec.yaml', _samplePubspec);
  fs.write('lib/config/app.dart', _sampleAppConfig);

  final installer = PluginInstaller(InstallContext.test(fs: fs, vars: {}));
  await MyPluginInstallCommand().installCommand(installer, /* ctx */);
  final result = await installer.commit();

  expect(result, isA<Success>());
  expect(fs.read('lib/config/my_plugin.dart'), contains('apiUrl'));
  expect(fs.read('lib/config/app.dart'), contains('MyPluginServiceProvider'));
});
```

Run with `dart test` in the plugin package root.

## Common pitfalls

- **Missing `package:fluttersdk_artisan` dependency**: the plugin's `pubspec.yaml` must declare `fluttersdk_artisan: ^0.0.1` in `dependencies` (not `dev_dependencies`), even if the plugin is registered via `install.yaml`. The provider class needs the artisan import.
- **`final class` convention**: every public type in the plugin should be `final class X` per project convention. Generated `make:plugin` stubs already use this; manual additions must follow.
- **`path:` deps in published artifacts**: never. Use `^x.y.z` caret form. Path deps are monorepo-dev-only and will fail at `dart pub publish` validation.
- **Forgetting `plugins:refresh`**: when hand-editing `.artisan/plugins.json`, the codegen barrel `_plugins.g.dart` is stale until `plugins:refresh` runs. `plugin:install` and `plugin:uninstall` call this automatically.
- **Hardcoded paths in commands**: never assume the consumer's project root layout beyond what `install` writes. Use `ctx.projectRoot` or relative paths from cwd.
