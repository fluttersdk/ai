# Dart and Flutter style core

The style rules the FlutterSDK reviewer enforces when the session has no personal style skill loaded. Every rule here is checkable from the source: it names what to look for and what makes a violation, so a reviewer can cite `file:line` rather than express a preference.

Two rules govern how this file is used:

1. **A style finding needs a rule.** If neither this file, the project's own `analysis_options.yaml`, nor a loaded style skill declares a rule, the observation is a preference and does not get reported. Taste is not a finding.
2. **A personal style skill wins.** When a `my-coding` skill (or any project style skill) is loaded in the session, its rules take precedence wherever the two disagree, and its language-specific reference is the authority for Dart. This file is the floor, not the ceiling.

## Contents

- [1. Types and nullability](#1-types-and-nullability)
- [2. Immutability](#2-immutability)
- [3. Naming](#3-naming)
- [4. Structure and control flow](#4-structure-and-control-flow)
- [5. Collections and formatting](#5-collections-and-formatting)
- [6. Documentation and comments](#6-documentation-and-comments)
- [7. Imports](#7-imports)
- [8. Errors](#8-errors)
- [9. Suppressions](#9-suppressions)
- [10. Tests](#10-tests)

## 1. Types and nullability

| Rule | Violation looks like |
|:--|:--|
| Every parameter, return type, field, and top-level variable carries an explicit type. | `void save(data)`, `final items = [];` where the element type cannot be inferred from the initializer |
| `dynamic` appears only where the data genuinely is dynamic (decoded JSON at the boundary), and is narrowed immediately. | `dynamic user` held across a method, `List<dynamic>` in a public signature |
| No `!` on a nullable the code has not proven non-null on the line above. | `user!.name` with no preceding guard |
| `late` only when initialization genuinely cannot happen at construction, with the reason in a comment. | `late String _title;` assigned in the constructor body |

Model attribute access in a magic app is typed through `get<T>('key')`; a bare `getAttribute` is both a style and a framework violation (see the magic skill's Core Law 7).

## 2. Immutability

- Widgets and value objects: `const` constructor, `final` fields, `@immutable` where the class is a value.
- A value object that needs a variant exposes `copyWith`, not a setter.
- A field that is never reassigned after construction is `final`. A `var` field that could be `final` is a finding.
- Collections held as state are not exposed directly for mutation; expose an unmodifiable view or a copy.

## 3. Naming

- English only, for every identifier, comment, docblock, commit message, and error string. A non-English identifier is a finding regardless of the project's audience.
- Names say what the thing is or does: `fetchMonitors`, `hasPendingInvite`, `MonitorStatus`. Not `data2`, `tmp`, `handle`, `doIt`.
- Booleans read as predicates: `isActive`, `hasError`, `canRetry`.
- Private members carry the leading underscore; public members do not carry it defensively.

## 4. Structure and control flow

- **Guard clauses over nesting.** Return, throw, or continue early. Nesting past two levels of conditionals is a finding.
- **A method does one thing.** A method that needs a paragraph of comments to explain its phases is asking to be split; extract the phases into named private methods.
- **Numbered step comments** on any method with three or more distinct phases, each stating why the phase exists rather than restating the code.
- **Constructor injection** for dependencies. Reaching into a service locator from inside a method body hides the dependency from the constructor signature; in a magic app the container resolves it once and the class declares what it needs.
- **Enums over magic values.** A string or int that carries meaning from a closed set is an enum. Stringly-typed status handling where an enum exists is a finding.

## 5. Collections and formatting

- Lists, maps, sets, and parameter lists that do not fit one line are multi-line with a trailing comma on the last element. The trailing comma is what makes `dart format` keep them multi-line and what keeps diffs to one line per element.
- 120-character line width. A line past it is a finding unless it is a URL or a string that cannot be broken.
- `dart format` produces no diff. If it would, that is a finding on its own, not a style opinion.

## 6. Documentation and comments

- Every public class, method, and field carries a DartDoc comment (`///`) saying what it is for. Parameters and return values get named when their role is not obvious from the signature.
- A comment explains **why**. A comment that restates the code is deleted, not improved: `// increment the counter` above `counter++` is a finding.
- A `TODO` carries an owner or an issue reference, otherwise it is a note nobody will ever action.

## 7. Imports

- Import at the top; never reference a symbol through a fully-qualified path inline.
- In a magic app the framework arrives as `package:magic/magic.dart` and its test surface as `package:magic/testing.dart`; deep imports into `package:magic/src/...` are a finding because they bind to internals.
- Same for Wind: `package:fluttersdk_wind/fluttersdk_wind.dart` is the only barrel.
- Unused imports are a finding (the analyzer catches them, so their presence usually means the analyzer is not being run).

## 8. Errors

- No empty `catch`, and no `catch` that swallows the error to keep going. Handle it deliberately or let it propagate.
- `catch (e)` without a type is acceptable only at a genuine boundary (an isolate entry point, a top-level handler); inside business logic, catch what the call can actually throw.
- An error path that logs and continues must leave the object in a state the next call can survive; a half-updated model after a failed save is a finding.
- Boundary code (I/O, network, parsing, platform channels) has an error path. Pure internal functions do not need one, and demanding it there is noise.

## 9. Suppressions

`// ignore:`, `// ignore_for_file:`, and analyzer opt-outs are findings. The underlying issue gets fixed instead. The single exception is a line that is structurally unreachable from tests (a `kDebugMode`-only branch, a platform branch the CI host cannot enter), which carries the pragma on the same line plus a one-line comment saying why.

## 10. Tests

- A bug fix has a test that fails before the fix and passes after it. A fix with no reproducing test is a finding.
- Tests assert behavior, not implementation details. A test that asserts a private method was called is coupled to the shape rather than the contract.
- In a magic app, `setUp` resets the container (`MagicTest.init()`, or `MagicApp.reset()` plus `Magic.flush()`); a suite without it leaks state between tests and produces false passes.
- A test that waits on a wall clock (`Future.delayed` sized to beat a TTL) is a flake waiting for a slow machine. Assert on a value the test controls instead.
