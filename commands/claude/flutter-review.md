# Flutter Code Review

Review the following Flutter/Dart code for adherence to FlutterSDK conventions.

## Checklist

1. **Wind UI**: W-prefix widgets (`WDiv`, `WText`, `WButton`), `className`-first styling, design token usage, dark mode classes
2. **Magic Framework**: Facade usage, Eloquent model patterns, controller/view structure, `MagicRoute` navigation
3. **Type Safety**: Explicit types on all parameters, return types, and properties — no `dynamic`
4. **Immutability**: `@immutable` + `const` constructors + `final` fields + `copyWith`
5. **Documentation**: DartDoc (`///`) on all public APIs with `@param` and example usage
6. **Architecture**: Thin controllers, fat services, composition over inheritance
7. **Formatting**: 120-char max width, 4-space indent, multi-line collections with trailing commas

Focus on correctness, convention adherence, and potential improvements. Load `/fluttersdk:wind-ui` and `/fluttersdk:magic-framework` skills for reference.

## Files to Review

$ARGUMENTS
