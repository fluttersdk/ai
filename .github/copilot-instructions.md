# FlutterSDK AI — VS Code Copilot Instructions

You are working in a FlutterSDK ecosystem project. Follow these conventions:

## Flutter / Dart
- Use `W`-prefixed widgets from Wind UI (`WDiv`, `WText`, `WButton`) — never raw Flutter widgets when Wind equivalents exist
- All styling via `className` string — never inline `BoxDecoration`, `TextStyle`, or `EdgeInsets`
- Every `bg-`, `text-`, and `border-` class MUST have a `dark:` counterpart
- Trailing commas on last constructor parameter and list item — always
- Multi-line constructor parameters when 3 or more
- `@immutable` + `const` constructors + `copyWith` pattern for value objects
- Flutter-native state only: `InheritedWidget` + `ChangeNotifier` — no BLoC/Riverpod/Provider

## Magic Framework
- `await Magic.init()` in `main()` before any facade call
- Facade-first: `Auth`, `Http`, `Config`, `Cache`, `DB`, `Log`, `Event`, `Lang`, `Route`, `Gate`
- Singleton controllers: `static X get instance => Magic.findOrPut(X.new);`
- Models declare `fillable` — never `guarded = []`
- `MagicFormData` for form state management

## General
- English only for all code, naming, comments
- 4 spaces indent, 120-char max line width, LF endings
- Full type hints on every parameter and return type
- DartDoc (`///`) on all public APIs
