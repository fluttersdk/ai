# Flutter review core

Every FlutterSDK reviewer reads this file in full and runs every stage in it, in order, on every review. The reviewers differ in depth and in the stages they add on top; the four stages below and the reporting contract are shared, so two reviewers cannot drift into two different definitions of the same check.

## Contents

- [Where the rules live](#where-the-rules-live)
- [Scope resolution](#scope-resolution)
- [Severity and confidence](#severity-and-confidence)
- [Stage 1: Magic framework compliance](#stage-1-magic-framework-compliance)
- [Stage 2: Wind UI compliance](#stage-2-wind-ui-compliance)
- [Stage 3: Correctness, OOP, and style](#stage-3-correctness-oop-and-style)
- [Stage 4: Reuse and simplification](#stage-4-reuse-and-simplification)
- [What is not a finding](#what-is-not-a-finding)
- [Output format](#output-format)

## Where the rules live

This file does not restate the framework rules. It names which rulebook decides each check, and the reviewer reads that rulebook. The rulebooks ship with the packages and are updated when the packages change, so a rule copied into a review prompt would be the one thing in the system guaranteed to rot.

| Stage | Rulebook | The sections that carry checkable rules |
|:--|:--|:--|
| 1 | `magic-framework` skill | Core Laws (section 1), Common rationalizations (7), Anti-patterns (8), Pre-completion checklist (9) |
| 2 | `wind-ui` skill | Core Laws (1), the token catalog and its no-op list (`references/tokens.md`), Flutter constraint rules (6), Definition of done (10), Anti-patterns wall (12), `references/design-culture.md` for token choice |
| 3 | `${CLAUDE_PLUGIN_ROOT}/references/dart-style-core.md`, plus a personal style skill when the session has one loaded | all |
| 4 | both skills' reference files, plus the reviewed project's own code | Wind `references/tokens.md` recipes, magic `references/facades-api.md` |

Read both rulebooks by path at startup: `${CLAUDE_PLUGIN_ROOT}/skills/wind-ui/SKILL.md` and `${CLAUDE_PLUGIN_ROOT}/skills/magic-framework/SKILL.md`.

They are deliberately not loaded through the agent's `skills:` frontmatter field. Plugin skills live in a `plugin-name:skill-name` namespace, the bare name is documented only as an invocation fallback, and nothing documents which form that field resolves for a plugin's own skill. A name that does not resolve is skipped with a warning in the debug log and nowhere else, so the failure mode is a reviewer that silently runs with no rulebook and reports confident nonsense. A path either resolves or errors. `skills:` still carries a personal style skill, where the bare name is the documented identity.

Do not review magic or Wind code from memory: the counts, the token names, and the facade signatures change between releases, and a review that invents a rule is worse than no review.

## Scope resolution

The orchestrator resolves scope before spawning you and passes a concrete file list. When you receive a scope that is not a concrete list of paths, resolve it in this order and say in your report which branch you took:

1. Explicit paths or globs in the prompt.
2. Uncommitted work: `git status --porcelain`, then `git diff` for the content.
3. Branch work: `git diff $(git merge-base HEAD @{u} 2>/dev/null || git merge-base HEAD main)...HEAD`.
4. If none of these resolves to a file list, report `NONE` with the reason. Never review from a description of what changed; never guess at a file list.

Read every file in the resolved scope. Adjacent unmodified files are read only as evidence for a finding inside the scope (the definition of a helper the reviewed code calls, the controller a reviewed view resolves), never reviewed on their own.

## Severity and confidence

Rate every finding on both axes before reporting it.

**Severity**

| Level | Meaning |
|:--|:--|
| CRITICAL | The code is wrong: it crashes, corrupts state, leaks one user's data to another, silently drops a write, or violates a framework contract in a way that fails at runtime. Also: a Core Law violation with a runtime consequence, such as a facade call before `Magic.init()`. |
| IMPORTANT | The code works today but violates a documented rule, or carries a defect that surfaces under a condition the code does not currently hit: a missing `dark:` peer, an unvalidated `fill`, a controller resolved through a constructor, an unbounded `truncate`. |
| MINOR | Everything else. Not reported. |

**Confidence** is 0-100: how sure you are that the finding is real, given what you actually read. Report only CRITICAL and IMPORTANT findings at confidence 50 or above. Tag any finding under 80 with `[confidence: N]`.

Two rules keep the report honest:

- **Verify before reporting.** For every candidate finding, re-read the surrounding code and ask what would make it not a finding: a guard three lines up, a `dark:` peer on the next line of the same className, a validator that already ran, an override in the theme. Discard the candidate unless the disproof fails. Prefer a false negative to a false positive.
- **There is no minimum.** A clean scope reports `NONE`. Padding a report with nits to look thorough is the failure mode this section exists to prevent.

## Stage 1: Magic framework compliance

Gates the rest: report Stage 1 first, and a CRITICAL here means the review verdict is BLOCKED regardless of what the later stages find.

Check the reviewed files against the magic rulebook, in this order:

1. **Bootstrap and container.** `await Magic.init()` before any facade call and before `runApp`. Services bound in a provider's `register()`, resolved through a facade or `Magic.make<T>`, not constructed inline. Routes registered in `register()`, never `boot()`. `configFactories` rather than `configs` wherever a config value reads `Env.get()`.
2. **Controllers and views.** The singleton accessor (`static X get instance => Magic.findOrPut(X.new)`). Views resolve controllers through `Magic.find<T>()` or the `MagicView` base, never constructor injection. State flows through `MagicStateMixin` and `RxStatus` with `refreshUI()` and the `setLoading` / `setSuccess` / `setError` / `setEmpty` transitions; a bare `StatefulWidget` plus `setState` for controller-owned state is a finding. `MagicFormData` disposed in `onClose()`.
3. **Models.** Typed `get<T>('key')` and `set`, never `getAttribute`. `fillable` declared, and `fill(validated, strict: true)` after validation. No assumption of lazy loading or `with()`; a relation is embedded in the payload or fetched and set.
4. **HTTP.** `response.data`, never `.body`. No `Http.patch`. Errors surfaced through `handleApiError(response)` rather than a hand-rolled status match.
5. **Validation.** `MagicFormData` for forms, `FormRequest` for complex payloads, `Validator` for ad hoc checks, at the boundary rather than deep in a widget.
6. **Auth and authorization.** `Auth.guest` as a getter. `authorize('ability')` in the controller rather than a hand-rolled `if (!Gate.allows(...)) throw`. Client-side `Gate` treated as advisory: a write path that relies on it alone, with no server-side authorization, is a CRITICAL finding.
7. **Navigation and feedback.** `MagicRoute.*` and `Magic.snackbar` / `toast` / `dialog`, never a `BuildContext` walk. No navigation, no I/O, and no fetch inside `build()`.
8. **Imports.** `package:magic/magic.dart` and `package:magic/testing.dart`. A deep import into `package:magic/src/...` binds to internals and is a finding.

## Stage 2: Wind UI compliance

Check every file that builds UI.

1. **Dark pairing.** Every `bg-` / `text-` / `border-` / `ring-` / `shadow-` / `fill-` token carries a `dark:` peer in the same className. This is the single most common real defect in Wind code; check it token by token, not by eye.

   **Resolve the project's theme aliases before you flag anything here.** `WindThemeData.aliases` maps a bare token to a full className, and an alias value normally carries its own `dark:` peer, so an alias used on its own is correctly paired and flagging it is wrong. Find the map first: `grep -rn "aliases:" lib/` leads to it, and a project using the design-first workflow has it generated in `lib/config/wind_theme.g.dart`. Read the values, then treat every alias key whose value contains a `dark:` token as paired.

   Measured on a real app before this check shipped: 38 of 76 className strings looked unpaired and every one of them was a semantic alias (`bg-surface`, `text-fg`, `border-color-border`) whose value already read `bg-[#FFFFFF] dark:bg-[#030712]`. A dark-pairing check that skips this step reports a false positive roughly half the time, which is the whole reason a reviewer stops being read.
2. **No interpolation.** No Dart expression inside a className string. Conditional visuals route through `states:` plus prefixed classes.
3. **Layout contracts.** `flex-1` for a fill-the-row child; `h-full` inside a scrollable parent; `absolute` without a `relative` ancestor; `truncate` without a bounded width; nested flex needing `min-w-0`; `scrollPrimary: true` on the scroll chain. The Wind skill's constraint section is the authority on each.
4. **`child` XOR `children`** on every W-widget that accepts both.
5. **Tokens that do nothing.** Flag tokens the parser drops: past the size cap, logical-inline spacing, negative margins, `w-auto` / `h-auto`, a bare `transition`, and `inline-flex` used where a real flex container is intended. The Wind token catalog's no-op sections are the authority; do not flag a token without confirming it there.
6. **Widget choice.** A raw `Container` / `Text` / `ElevatedButton` where a W-widget exists is a finding. Material `Scaffold`, `AppBar`, dialogs, sheets, and virtualised lists are the correct choice and are never a finding.
7. **Design defaults.** Touch targets, one primary action per section, `semanticLabel` on icon-only controls, spacing that separates groups more than members. The design-culture reference decides these; a departure with a visible reason is not a finding.

## Stage 3: Correctness, OOP, and style

1. **Logic.** Wrong conditions, off-by-one, unreachable branches, swapped arguments, a `Future` never awaited, a stream or controller never disposed.
2. **Null and error handling.** Missing guards on the actual data flow. Boundary code (network, storage, platform channel, parsing) without an error path. An empty or swallowing `catch`.
3. **OOP shape.** One responsibility per class; dependencies declared rather than reached for; enums instead of stringly-typed state; guard clauses instead of nesting; immutability for values.
4. **Style.** `${CLAUDE_PLUGIN_ROOT}/references/dart-style-core.md`, plus the personal style skill's rules when one is loaded. Every style finding names the rule it violates; an observation with no rule behind it is not reported.

## Stage 4: Reuse and simplification

1. **Duplicated className blocks.** The same non-trivial className appearing in three or more places is a `WindRecipe` or a shared component. Cite every occurrence.
2. **Duplicated widget trees.** Two nearly identical subtrees differing in a label or a color are one parameterised widget.
3. **Hand-rolled framework work.** Code that reimplements what a facade already does (a manual `SharedPreferences` write where `Cache` exists, a hand-built query where the model's builder exists, four `MagicRoute.page()` calls where `resource()` exists).
4. **Existing helpers.** Before flagging new code as unique, grep the project for a helper that already solves it; a missed reuse names the existing symbol at `file:line`.

## What is not a finding

Report none of these, in any stage:

- A style preference no rulebook declares.
- A pre-existing issue in a file the reviewed change did not touch, unless the change made it reachable.
- A framework behavior the skill documents as intended: a silently dropped unknown token, a client-side `Gate` being advisory, `useLocal` defaulting to false, the absence of `with()` or `Http.patch`.
- Test code held to production error-handling rules.
- A missing test for code the project has no test coverage convention for.
- Anything you could not verify by reading the code, including a claim about runtime behavior you did not trace.

## Output format

Report in this shape, no preamble:

```markdown
## Scope

<How scope resolved (explicit paths / uncommitted / branch diff), and the file count.>

## Stage 1: Magic framework compliance

<Findings, or `CLEAN`.>

## Stage 2: Wind UI compliance

<Findings, or `CLEAN`.>

## Stage 3: Correctness, OOP, and style

<Findings, or `CLEAN`.>

## Stage 4: Reuse and simplification

<Findings, or `CLEAN`.>

## Verdict

**APPROVED** or **BLOCKED**
```

Every finding is one bullet in this shape:

```
- **[CRITICAL]** `lib/features/monitor/monitor_controller.dart:42` Facade call before `Magic.init()` completes.
  What breaks: `Auth.user()` runs during `main()` before providers boot, so it returns null on a cold start and the dashboard renders the guest state for a signed-in user.
  Fix: move the call into `onInit()`.
  Rule: magic-framework Core Law 1.
```

Four parts, all required: severity and location, what actually breaks (a concrete scenario, not a restatement of the rule), the fix, and the rule that decides it. A finding without a `file:line` is not a finding. A finding whose "what breaks" is a paraphrase of the rule name has not been thought through; verify it or drop it.

When every stage is CLEAN, the whole report is the scope line, four `CLEAN` lines, and `**APPROVED**`. Say `NONE` rather than inventing something to justify the run.

**Verdict rule**: any CRITICAL finding in any stage gives BLOCKED. IMPORTANT findings do not gate; they are reported for the caller to act on.
