# install.yaml schema reference

Authoritative source: `lib/src/installer/install_manifest.dart` (schema classes) + `lib/src/installer/manifest_parser.dart` (regex validation). Canonical example transcribed from `test/installer/manifest_parser_test.dart:14-105`.

The `install.yaml` manifest sits at the plugin package root (or under `assets/install.yaml`). When `plugin:install <name>` runs, the manifest is parsed into `InstallManifest`, walked by `ManifestInstaller`, and committed atomically (`.tmp` + rename through `InstallTransaction`). Every applied operation is recorded at `.artisan/installed/<plugin>.json` so `plugin:uninstall` can walk it in reverse.

## Top-level fields

| Field | Type | Required | Description |
|-------|------|:--------:|-------------|
| `plugin_name` | string | yes | Snake_case package name. Regex `^[a-z_][a-z0-9_]*$` per Dart pubspec rules. |
| `dependencies` | object | no | `pubspec` + `dev_pubspec` + `pubspec_assets` injected into the consumer's pubspec.yaml. |
| `publish` | map | no | `stub_path: target_path` map. Stub renders via placeholder substitution. |
| `json_merge` | map | no | Deep-merge a stub JSON into a target JSON file. |
| `magic` | object | no | Magic framework integration hooks (provider, config_factory, routes). |
| `native` | object | no | Per-platform native config (android, ios, macos, web). |
| `env` | map | no | Environment variables for `.env` with defaults + comments. |
| `prompts` | list | no | Interactive prompts (string / choice / bool). |
| `placeholders` | map | no | Template values, supports `{{ prompts.KEY }}` interpolation. |
| `post_install` | object | no | `run` + `ask_to_run` shell ops + final `message`. |
| `bootstrap_command` | string | no | Plugin command name to chain after registration (e.g. `logger:install`). |

## `plugin_name`

Regex at `lib/src/installer/manifest_parser.dart:31`: `^[a-z_][a-z0-9_]*$`. Matches Dart's pubspec `name:` rule.

```yaml
plugin_name: example_plugin
```

## `dependencies`

```yaml
dependencies:
  pubspec:
    intl: ^0.20.0
    crypto: ^3.0.0
  dev_pubspec:
    mocktail: ^1.0.0
  pubspec_assets:
    - assets/example/
    - assets/lang/en.json
```

| Sub-key | Type | Purpose |
|---------|------|---------|
| `pubspec` | map | Runtime deps. Caret form (`^x.y.z`) is the pub.dev convention. |
| `dev_pubspec` | map | Dev-only deps. |
| `pubspec_assets` | list | Asset paths added under `flutter.assets:` in pubspec.yaml. |

Caret form only: never use `path:` local-dev syntax in install.yaml.

## `publish`

```yaml
publish:
  install/example_config.dart.stub: lib/config/example.dart
  install/example_routes.dart.stub: lib/routes/example.dart
```

Each entry copies a stub from the plugin's `assets/stubs/` (resolution-relative to the plugin package root via `package_config.json`) into the consumer at the target path, rendering `{{ name }}`, `{{ pascalName }}`, `{{ commandPrefix }}` placeholders.

## `json_merge`

```yaml
json_merge:
  assets/lang/en.json:
    source: install/lang/en.json
    additive: true
```

| Sub-key | Type | Purpose |
|---------|------|---------|
| `source` | string | Stub file path (resolved against plugin's `assets/stubs/`). |
| `additive` | bool | `true`: deep-merge only (preserve existing keys). `false`: overwrite collisions. |

## `magic`

```yaml
magic:
  provider: ExampleServiceProvider
  config_factory: exampleConfig
  routes: registerExampleRoutes
```

| Sub-key | Type | Validation | Purpose |
|---------|------|------------|---------|
| `provider` | string | PascalCase regex `^[A-Z][A-Za-z0-9]*$` at `manifest_parser.dart:34` | Inserted into `lib/config/app.dart` providers list |
| `config_factory` | string | none | Function name for `configFactories` registration |
| `routes` | string | none | Function name for route registration |

Optional. Only used when the consumer ships the Magic framework. Pure-Flutter consumers ignore this section.

## `native`

### `native.android`

```yaml
native:
  android:
    permissions:
      - android.permission.INTERNET
    meta_data:
      io.flutter.embedded_views_preview: "true"
    gradle:
      plugins:
        - id: com.example.gradle.plugin
          version: "1.0.0"
      dependencies:
        - scope: implementation
          notation: "com.example:lib:1.0.0"
```

| Sub-key | Type | Purpose |
|---------|------|---------|
| `permissions` | list | Strings injected as `<uses-permission android:name="...">` |
| `meta_data` | map | `<meta-data android:name="key" android:value="value">` entries |
| `gradle.plugins` | list | Plugin id + version for `android/build.gradle` |
| `gradle.dependencies` | list | `scope` + `notation` for `android/app/build.gradle` |

### `native.ios` and `native.macos`

```yaml
native:
  ios:
    info_plist:
      NSExampleUsageDescription: "Reason shown in iOS permission dialog"
      UIBackgroundModes: ["fetch"]
    entitlements:
      com.apple.security.keychain: true
    podfile:
      platform_version: "13.0"
      pods:
        - "ExamplePod"
```

Same schema for both platforms.

| Sub-key | Type | Purpose |
|---------|------|---------|
| `info_plist` | map | Info.plist entries. Values can be string, bool, num, or list. |
| `entitlements` | map | App entitlements dictionary. |
| `podfile.platform_version` | string | Minimum platform version. |
| `podfile.pods` | list | Pod names appended to the Podfile. |

### `native.web`

```yaml
native:
  web:
    head_scripts:
      - '<script src="example.js"></script>'
    meta_tags:
      - {name: "description", content: "Example plugin metadata"}
```

| Sub-key | Type | Purpose |
|---------|------|---------|
| `head_scripts` | list | Raw HTML strings injected into `web/index.html` head |
| `meta_tags` | list | Maps with `name` + `content` (or `property` + `content` for OpenGraph) |

## `env`

```yaml
env:
  EXAMPLE_KEY:
    default: example_value
    comment: "Example plugin runtime config"
```

Each entry adds (or updates) a key in the consumer's `.env` file (and `.env.example` when present). Idempotent: line-based, preserves surrounding comments, value-update on key collision.

## `prompts`

```yaml
prompts:
  - {key: configPath, type: string, default: "~/.example.conf", question: "Config file path?"}
  - {key: mode, type: choice, options: [dev, staging, prod], default: dev, question: "Deployment mode?"}
  - {key: enableFeature, type: bool, default: false, question: "Enable optional feature?"}
```

Ordered list. Each entry asks the user at install time; answers feed `placeholders` interpolation.

| Type | Required fields | Optional |
|------|-----------------|----------|
| `string` | `key`, `type: string`, `question` | `default` |
| `choice` | `key`, `type: choice`, `options` (list), `question` | `default` |
| `bool` | `key`, `type: bool`, `question` | `default` (true / false) |

Prompt keys must be unique (validated; throws `Duplicate prompt key` on collision).

## `placeholders`

```yaml
placeholders:
  configFilePath: "{{ prompts.configPath }}"
  runtimeMode: "{{ prompts.mode }}"
```

Maps placeholder names to interpolated values. The `{{ prompts.KEY }}` syntax pulls from the prompt answers above. Plain literals (no interpolation) are passed through verbatim. Whitespace variants allowed: `{{prompts.path}}`, `{{ prompts.path }}`.

Validation: placeholder values referencing unknown prompt keys throw `ManifestValidationException` at parse time.

## `post_install`

```yaml
post_install:
  run:
    - cmd: dart
      args: [format, lib/config/example.dart]
  ask_to_run:
    - prompt: "Run pub get now?"
      cmd: flutter
      args: [pub, get]
  message: |
    example_plugin installed.
    See lib/config/example.dart for the generated config.
```

| Sub-key | Type | Purpose |
|---------|------|---------|
| `run` | list | Shell commands executed unconditionally after install commit. Each: `cmd` + `args` (list). |
| `ask_to_run` | list | Same shape but prompts user first. `prompt` + `cmd` + `args`. |
| `message` | multi-line string | Printed after success. Use for "next step" guidance. |

## `bootstrap_command`

```yaml
bootstrap_command: example:install
```

Plugin command name to invoke automatically after `plugin:install` registers the provider. Use when the plugin's setup is multi-stage and the second stage is its own command.

## Validation rules

- `plugin_name` must match `^[a-z_][a-z0-9_]*$`.
- `magic.provider` must match `^[A-Z][A-Za-z0-9]*$`.
- Prompt keys must be unique.
- `placeholders` values referencing `{{ prompts.X }}` must reference a key declared in `prompts`.
- Top-level must be a YAML map (not a list or scalar).
- Invalid YAML syntax throws `FormatException` wrapping the parser error.

All four throw `ManifestValidationException` at parse time with the offending field named.

## Complete canonical example

Transcribed byte-exact from `test/installer/manifest_parser_test.dart:14-105` (the `_fullYaml` test constant; exercises every section):

```yaml
plugin_name: example_plugin

dependencies:
  pubspec:
    intl: ^0.20.0
    crypto: ^3.0.0
  dev_pubspec:
    mocktail: ^1.0.0
  pubspec_assets:
    - assets/example/
    - assets/lang/en.json

publish:
  install/example_config.dart.stub: lib/config/example.dart
  install/example_routes.dart.stub: lib/routes/example.dart

json_merge:
  assets/lang/en.json:
    source: install/lang/en.json
    additive: true

magic:
  provider: ExampleServiceProvider
  config_factory: exampleConfig
  routes: registerExampleRoutes

native:
  android:
    permissions:
      - android.permission.INTERNET
    meta_data:
      io.flutter.embedded_views_preview: "true"
    gradle:
      plugins:
        - id: com.example.gradle.plugin
          version: "1.0.0"
      dependencies:
        - scope: implementation
          notation: "com.example:lib:1.0.0"
  ios:
    info_plist:
      NSExampleUsageDescription: "Reason shown in iOS permission dialog"
      UIBackgroundModes: ["fetch"]
    entitlements:
      com.apple.security.keychain: true
    podfile:
      platform_version: "13.0"
      pods:
        - "ExamplePod"
  macos:
    info_plist:
      NSExampleUsageDescription: "Reason shown in macOS permission dialog"
    entitlements:
      com.apple.security.network.client: true
    podfile:
      platform_version: "11.0"
      pods:
        - "ExamplePod"
  web:
    head_scripts:
      - '<script src="example.js"></script>'
    meta_tags:
      - {name: "description", content: "Example plugin metadata"}

env:
  EXAMPLE_KEY:
    default: example_value
    comment: "Example plugin runtime config"

prompts:
  - {key: configPath, type: string, default: "~/.example.conf", question: "Config file path?"}
  - {key: mode, type: choice, options: [dev, staging, prod], default: dev, question: "Deployment mode?"}
  - {key: enableFeature, type: bool, default: false, question: "Enable optional feature?"}

placeholders:
  configFilePath: "{{ prompts.configPath }}"
  runtimeMode: "{{ prompts.mode }}"

post_install:
  run:
    - cmd: dart
      args: [format, lib/config/example.dart]
  ask_to_run:
    - prompt: "Run pub get now?"
      cmd: flutter
      args: [pub, get]
  message: |
    example_plugin installed.

bootstrap_command: example:install
```

## Minimal example

For plugins that only need to wire a Magic provider:

```yaml
plugin_name: my_simple_plugin

magic:
  provider: MySimplePluginServiceProvider
```

Every other section is optional. The manifest above is enough to register the provider in `lib/config/app.dart`, log the install record, and surface the new commands via `plugins:refresh`.
