# dowel_tinker reference

`dowel_tinker { eval: "<expr>" }` evaluates one Dart expression in the running app's root library through the VM Service `evaluate` RPC; the CLI form is `./bin/dowel tinker --eval=<expr>`. It needs a session with a `vmServiceUri`.

## Contents

- [Expression rules](#expression-rules)
- [Reading the result](#reading-the-result)
- [What a failure looks like](#what-a-failure-looks-like)
- [Recipes](#recipes)
- [When not to use tinker](#when-not-to-use-tinker)
- [dowel_tinker and tapir_evaluate](#dowel_tinker-and-tapir_evaluate)

## Expression rules

- **One expression.** The VM compiles an expression, not a program: a trailing `;`, several statements, an `import` or a declaration fail with compile error code 113. Collapse statements into a closure, `(() { var x = 1; return x + 1; })()`, or use a cascade. Dart has no comma operator.
- **`await` compiles, but returns the Future.** When the source contains the text `await`, dowel wraps it as `(() async => <expr>)()` (`VmServiceClient.evaluate`), which the VM accepts. The RPC does not wait for the Future, so the result is a reference such as `<_Future#objects/1/0>`, never the awaited value, and an asynchronous failure is not reported either. Start the work with `await`, then read the outcome with a second synchronous expression. The check is a substring match, so the word inside a string literal triggers the wrap too.
- **Scope is the root library**, usually `lib/main.dart`: its top-level symbols and whatever it imports, public names only. There is no `this`, no local variable and no symbol from a library the root does not import. A host app's singleton, top-level service or container lookup works as long as the root library reaches it.
- **The main isolate is read on every call**, so a hot restart is transparent. The MCP server drops its VM connection when the app goes away and dials the session's current URI on the next call: after a device change or a `dowel_stop` and `dowel_start`, retry, and reconnect the MCP client only if calls keep failing.
- `dowel_tinker` is one shot with no streaming. Loop in the agent, not in the expression.

## Reading the result

| Result | Rendered as |
|---|---|
| Null, bool, number | `null`, `true`, `42` |
| String | `"quoted"` (double quotes) |
| Any other object, including the Future an `await` expression returns | `<ClassName#id>` |
| `ErrorRef` (the expression threw) | `Error: <message>` |

Append `.toString()` inside the expression to read a non-primitive: `MyService.instance.state` gives `<MyState#a3f9>`, `MyService.instance.state.toString()` gives `"MyState(loaded: true, count: 12)"`. Override `toString()` on state types so the dump says something. A list or map prints as `<ClassName#id>` too, so convert it first: `keys.toList().toString()`.

## What a failure looks like

The result text starts with `` # `dowel tinker` exit N ``, and `isError` is set when `N` is not 0.

| Case | Text | Exit |
|---|---|---|
| Compile error | `[ERROR] evaluate: (113) <compiler message>` | 1 |
| The expression threw at runtime | `Error: <message>` | 0, so `isError` is false: read the text |
| A blank `eval` | `--eval needs a Dart expression, e.g. --eval "1 + 1". Omit it to start the REPL.` | 1 |
| No session | `### Error` then `Not connected to a running Flutter app. Run ...` | error |
| A session is recorded but the VM Service is unreachable | An error result from the uncaught connect exception; the text may not start with `### Error` | error |

For a compile error, rewrite as one valid expression. For a runtime error, fix the app code or the expression. A stale isolate after a hot restart recovers on the next call; if it does not, call `dowel_hot_restart`.

## Recipes

Replace `MyService` and `MyEvent` with the host app's own names.

```text
dowel_tinker { eval: "WidgetsBinding.instance.lifecycleState.toString()" }
dowel_tinker { eval: "PaintingBinding.instance.imageCache.currentSize" }
dowel_tinker { eval: "WidgetsBinding.instance.platformDispatcher.locale.toString()" }
dowel_tinker { eval: "MyService.instance.state.toString()" }
dowel_tinker { eval: "await MyService.instance.refresh()" }        # returns <_Future#...>; the work still runs
dowel_tinker { eval: "MyService.instance.state.toString()" }        # read the outcome afterwards
dowel_tinker { eval: "(MyService.instance..reset()).state.toString()" }
dowel_tinker { eval: "(() { MyService.instance.notify('boot'); return 'notified'; })()" }
```

The cascade returns the receiver, so the wrapped parentheses plus `.state.toString()` reads the state after a synchronous side effect. A closure runs several statements and returns a self-describing string. To compare before and after an action, evaluate the same read expression on either side of it; after an `await` start, poll a completion flag the app exposes (such as `isLoading`) with a timeout, because a quiet state does not prove the work finished.

## When not to use tinker

- Widget tree, gestures, waiting on UI state: the `tapir` skill's tools; tinker has no `BuildContext` and no hit testing.
- HTTP, log and exception buffers: the `crumbs` skill's tools.
- Several statements with control flow: a test under `test/`, run with `dart test`.

## dowel_tinker and tapir_evaluate

Both evaluate against the root library and both wrap `await`, so both return the Future reference rather than its value. `tapir_evaluate` comes from the `tapir` plugin (dispatcher entry only) and returns `{expression, result}`; its failures are `### Error` text starting `Runtime exception:`, `Expression compilation error:` or `Isolate sentinel encountered (kind: ...)`. Use `dowel_tinker` for inspection and triggers; its output goes through the `Tinker.casters` chain, which a host integration can extend.
